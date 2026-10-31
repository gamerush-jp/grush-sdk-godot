extends RefCounted

## 交換所。プレイヤーがアイテムを出品し、同じゲームの別のプレイヤーが受ける。出品も受諾も
## ゲストができる。GameRush はアイテムの正当性を確かめず、交換が片方だけ成立しないことと、
## 終わった取引を取りこぼさないことだけを保証する。
##
## **offer・want・give で文章や画像は送れない。** どれも辞書で、文字列の値とキーは識別子
## （`^[A-Za-z0-9_.:-]{1,32}$`）だけ、ほかは数値・真偽値・null。入れ子は最上位を 1 段目として
## 4 段まで、値は合計 64 個まで。JSON にして offer 2KB・want 1KB・give 2KB まで。
## 利用者どうしの文章や画像のやりとりには使わないこと。
##
## 取りこぼさないために、次の順で使う。
## 1. 出品の前に、出すアイテムを手元のセーブで仮置き（使えない状態）にする。
## 2. operation_id をセーブに保存してから [method create] を呼ぶ。
## 3. 応答が失われたら、同じ operation_id で呼び直す。同じ operation_id の再送は先に作った出品を返す。
## 4. [method mine] の `pending` をセーブに反映し、セーブを永続化してから [method ack] する
##    （ack に渡せる id は 1 回 50 件まで）。
## 5. 反映済みの取引 ID をセーブに持ち、同じ取引を二度反映しない。
##
## 出品は `{"id", "from", "to", "taker", "offer", "want", "offer_key", "want_key", "give", "status",
## "created_at", "expires_at", "settled_at"}`。`status` は `open` / `matched` / `cancelled` /
## `expired`（知らない値もそのまま渡す）。`give` は当事者（出品者と受けた側）にだけ入る。
##
## ランタイムの版数が [constant TRADE_PROTOCOL_VERSION] 未満なら、どの呼び出しも unsupported。

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const Call := preload("res://addons/grush_sdk/grush_call.gd")

## 交換所が使えるランタイムの版数。
const TRADE_PROTOCOL_VERSION := 7

const OUTCOMES := ["matched", "taken", "expired", "cancelled", "notFound"]

var _grush: Node
var _backend: RefCounted


func _init(grush: Node, backend: RefCounted) -> void:
	_grush = grush
	_backend = backend


## 出品する。[param operation_id] は `^[A-Za-z0-9._:-]{1,64}$` の出品の識別子で、呼ぶ前に
## セーブへ保存しておく。[param options] は `offer_key` / `want_key`（一覧の絞り込みに使う識別子）・
## `to`（指名の出品の相手の疑似 ID）・`expires_in_sec`（600〜604800、既定 3 日）。
## 受付中の出品が 10 件あるときは invalidParams（待っても直らない。取り下げるか、成立・期限切れを待つ）。
## 毎日 30 件の出品の上限は rateLimited（時間が経てば回復する）。
func create(offer: Dictionary, want: Dictionary, operation_id: String, options: Dictionary = {}) -> Dictionary:
	var params := {"offer": offer, "want": want, "operationId": operation_id}
	if options.get("offer_key") != null:
		params["offerKey"] = str(options["offer_key"])
	if options.get("want_key") != null:
		params["wantKey"] = str(options["want_key"])
	if options.get("to") != null:
		params["to"] = str(options["to"])
	if options.get("expires_in_sec") != null:
		params["expiresInSec"] = int(options["expires_in_sec"])
	return _single(await _call("trade.create", params))


## 他人の公開の出品と自分宛ての指名の出品のうち、受付中のものを新しい順に返す。[param options] は
## `offer_key` / `want_key`（絞り込み）・`limit`（1〜50、既定 20）・`cursor`。value は
## `{"trades": Array, "next_cursor": String か null}`。
func list(options: Dictionary = {}) -> Dictionary:
	var params := {}
	if options.get("offer_key") != null:
		params["offerKey"] = str(options["offer_key"])
	if options.get("want_key") != null:
		params["wantKey"] = str(options["want_key"])
	if options.has("limit"):
		params["limit"] = int(options["limit"])
	if options.get("cursor") != null:
		params["cursor"] = str(options["cursor"])
	var response := await _call("trade.list", params)
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	if not (raw is Dictionary) or not (raw.get("trades") is Array):
		return Result.failure(Result.CODE_INTERNAL, "GameRush returned an unreadable trade list.")
	var next_cursor: Variant = raw.get("nextCursor")
	return Result.ok(
		{
			"trades": _trades_of(raw["trades"]),
			"next_cursor": null if next_cursor == null or str(next_cursor) == "" else str(next_cursor),
		}
	)


## 自分の受付中の出品（`open`）と、終わったがまだ ack していない取引（`pending`、終わった順）。
## `pending` の各要素は出品の項目に `role`（`offerer` / `taker`）と `action` を足したもの。
## `action` は `receiveGive`（出品者が give を受け取る）・`returnOffer`（出品者が offer を手元へ戻す）・
## `receiveOffer`（受けた側が offer を受け取る）。知らない `action` は反映せず、ack もしない。
func mine() -> Dictionary:
	var response := await _call("trade.mine", {})
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	if not (raw is Dictionary) or not (raw.get("open") is Array) or not (raw.get("pending") is Array):
		return Result.failure(Result.CODE_INTERNAL, "GameRush returned unreadable trades.")
	var pending: Array = []
	for entry in raw["pending"]:
		if entry is Dictionary and str(entry.get("id", "")) != "":
			var trade := trade_of(entry)
			trade["role"] = str(entry.get("role", ""))
			trade["action"] = str(entry.get("action", ""))
			pending.append(trade)
	return Result.ok({"open": _trades_of(raw["open"]), "pending": pending})


## 出品を受ける。[param give] は渡すもの。先に取られた・期限切れ・取り下げ・見えない出品は
## エラーではなく `outcome`（`matched` / `taken` / `expired` / `cancelled` / `notFound`）で返る。
## 同じ取引への再送は `matched` を返す。value は `{"outcome": String, "trade": 出品か null}`。
func accept(trade_id: String, give: Dictionary) -> Dictionary:
	var response := await _call("trade.accept", {"tradeId": trade_id, "give": give})
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	if not (raw is Dictionary) or not OUTCOMES.has(raw.get("outcome")):
		return Result.failure(Result.CODE_INTERNAL, "GameRush returned an unreadable accept result.")
	var trade: Variant = raw.get("trade")
	return Result.ok(
		{
			"outcome": str(raw["outcome"]),
			"trade": trade_of(trade) if trade is Dictionary and str(trade.get("id", "")) != "" else null,
		}
	)


## 自分の受付中の出品を取り下げる。期限を過ぎていれば `expired` になり、終わっていれば今の状態を
## そのまま返す。出したアイテムは `pending` の `returnOffer` で戻す。
func cancel(trade_id: String) -> Dictionary:
	return _single(await _call("trade.cancel", {"tradeId": trade_id}))


## `pending` の取引の受け取りを確かめ、value に記録した件数を返す（1 回 50 件まで）。
## **セーブへ反映して保存してから呼ぶこと。** ack した取引は `pending` に戻らない。
func ack(ids: Array) -> Dictionary:
	var response := await _call("trade.ack", {"ids": ids})
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	var count: Variant = raw.get("acked") if raw is Dictionary else raw
	if not (count is int or count is float):
		return Result.failure(Result.CODE_INTERNAL, "GameRush returned an unreadable count.")
	return Result.ok(int(count))


## 出品を通報する。**ゲームは通報 UI を描けない。** 確認は GameRush が出し、プレイヤーが
## 承諾したら value が true。通報すると出品者をブロックし、その相手のメッセージと出品は
## 見えなくなる。ゲストは signInRequired。
func report(trade_id: String) -> Dictionary:
	var response := await _call("trade.report", {"tradeId": trade_id})
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	var value: Variant = raw.get("reported") if raw is Dictionary else raw
	return Result.ok(value is bool and value)


func _call(method: String, params: Dictionary) -> Dictionary:
	# 基本機能ごと止めない。交換所が使えない古いランタイムでは、この機能だけ unsupported にする。
	if not _grush.is_available() or _grush.protocol_version() < TRADE_PROTOCOL_VERSION:
		return Result.unsupported()
	var pending := Call.new()
	_backend.call_api(method, params, func(result: Dictionary) -> void: pending.resolve(result))
	return await pending.completed


# ランタイムは包んだ RPC の結果（{"trade": …}）も、出品だけも返しうる。
static func _single(response: Dictionary) -> Dictionary:
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	var trade: Variant = raw.get("trade", raw) if raw is Dictionary else null
	if not (trade is Dictionary) or str(trade.get("id", "")) == "":
		return Result.failure(Result.CODE_INTERNAL, "GameRush returned an unreadable trade.")
	return Result.ok(trade_of(trade))


static func _trades_of(raw: Array) -> Array:
	var trades: Array = []
	for entry in raw:
		if entry is Dictionary and str(entry.get("id", "")) != "":
			trades.append(trade_of(entry))
	return trades


static func _text_or_null(value: Variant) -> Variant:
	return null if value == null or str(value) == "" else str(value)


static func trade_of(raw: Dictionary) -> Dictionary:
	var offer: Variant = raw.get("offer")
	var want: Variant = raw.get("want")
	var give: Variant = raw.get("give")
	return {
		"id": str(raw.get("id", "")),
		"from": _text_or_null(raw.get("from")),
		"to": _text_or_null(raw.get("to")),
		"taker": _text_or_null(raw.get("taker")),
		"offer": offer if offer is Dictionary else {},
		"want": want if want is Dictionary else {},
		"offer_key": _text_or_null(raw.get("offerKey")),
		"want_key": _text_or_null(raw.get("wantKey")),
		"give": give if give is Dictionary else null,
		"status": str(raw.get("status", "")),
		"created_at": str(raw.get("createdAt", "")),
		"expires_at": str(raw.get("expiresAt", "")),
		"settled_at": _text_or_null(raw.get("settledAt")),
	}
