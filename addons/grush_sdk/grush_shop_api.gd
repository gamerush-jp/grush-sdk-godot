extends RefCounted

## 作者のアイテム販売。作者が GameRush の Studio か API キーで登録した商品を、プレイヤーが買う。
## GameRush は払った人にアイテムを届けることまでを保証する。ゲームの中での使用は改ざんを防げない。
##
## 購入できるのは Web の GameRush だけ。アプリと LINE では [method purchase] が unsupported、
## [method products] は `enabled` が false の空の一覧。[method pending]・[method ack]・[method owned] は
## どこでも動く。
##
## 取りこぼさないために、次の順で使う。
## 1. [method purchase] を呼ぶ前にセーブする。`redirecting` が返ると、ページはすぐ決済の画面へ移る。
## 2. 起動時と [signal pending_received] を受けたときに [method pending] を読む。
## 3. 付与をセーブに反映し、セーブを永続化してから [method ack] する。ack するまで付与は pending に残る。
## 4. 反映済みの付与の id をセーブに持ち、同じ付与を二度反映しない。
##
## ランタイムの版数が [constant SHOP_PROTOCOL_VERSION] 未満なら、どの呼び出しも unsupported。

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const Call := preload("res://addons/grush_sdk/grush_call.gd")

## アイテム販売が使えるランタイムの版数。
const SHOP_PROTOCOL_VERSION := 12

## GameRush と同じ sku の形。`$` は末尾の改行の前でも合うので `\z` で終える。
const SKU_PATTERN := "^[a-z0-9][a-z0-9_.-]{0,63}\\z"

const PURCHASE_STATUSES := ["redirecting", "cancelled", "alreadyOwned"]

## 決済から戻って付与が届いたときに、買った商品の [param sku] で発火する。受けたら [method pending] を
## 読んで反映する。接続より先に届いた分は、接続した後に1回だけ届く。JavaScript の呼び出しの中ではなく
## `call_deferred` で後から配る。版数が [constant SHOP_PROTOCOL_VERSION] 未満のランタイムと GameRush の外では
## 発火しない。[method GRush.use_backend] でバックエンドを差し替えても接続はそのまま、新しいバックエンドから届く。
signal pending_received(sku: String)

var _grush: Node
var _backend: RefCounted
var _pending_transport: RefCounted
var _pending_watching := false
var _disposed := false
# use_backend のたびに増やす。差し替える前の受け取り口から call_deferred で積まれた合図を捨てるため。
var _generation := 0
var _sku_pattern := RegEx.create_from_string(SKU_PATTERN)


func _init(grush: Node, backend: RefCounted, pending_transport: RefCounted = null) -> void:
	_grush = grush
	use_backend(backend, pending_transport)


## 呼び出し先と、付与の合図の受け取り口を差し替える。[signal pending_received] への接続はそのまま、
## 新しい受け取り口から届く。GRush.use_backend が呼ぶ。
func use_backend(backend: RefCounted, pending_transport: RefCounted = null) -> void:
	_backend = backend
	_stop_poll()
	if _pending_transport != null:
		_pending_transport.dispose()
	_pending_transport = pending_transport
	_pending_watching = false
	_generation += 1
	_sync_watch()


func dispose() -> void:
	_disposed = true
	_stop_poll()
	if _pending_transport != null:
		_pending_transport.dispose()
	_pending_transport = null
	_grush = null


## 売っている商品。value は `{"enabled": bool, "products": Array}` で、商品は
## `{"sku": String, "name": String, "price_jpy": int}`。販売が止まっているときとアプリ・LINE では
## `enabled` が false で `products` は空。
func products() -> Dictionary:
	var response := await _call("shop.products", {})
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	if not (raw is Dictionary) or not (raw.get("products") is Array):
		return Result.failure(Result.CODE_INTERNAL, "GameRush returned an unreadable product list.")
	var items: Array = []
	for entry in raw["products"]:
		if entry is Dictionary and str(entry.get("sku", "")) != "":
			var price: Variant = entry.get("priceJpy")
			items.append(
				{
					"sku": str(entry["sku"]),
					"name": str(entry.get("name", "")),
					"price_jpy": int(price) if price is int or price is float else 0,
				}
			)
	var enabled: Variant = raw.get("enabled")
	return Result.ok({"enabled": enabled is bool and enabled, "products": items})


## [param sku] の商品を買う。value は `redirecting`（ページが決済の画面へ移る）・`cancelled`（プレイヤーが
## やめた）・`alreadyOwned`（もう持っている）のどれか。**呼ぶ前にセーブしておくこと。** `redirecting` の後、
## ゲームのページはすぐ閉じる。付与は決済から戻ったときに [signal pending_received] と [method pending] で届く。
## sku が `^[a-z0-9][a-z0-9_.-]{0,63}$` に合わなければ送らずに invalidParams。ゲストは signInRequired、
## アプリと LINE では unsupported。プレイヤーの答えを待つので、返るまで長くかかることがある。
func purchase(sku: String) -> Dictionary:
	if _sku_pattern.search(sku) == null:
		if not _supported():
			return Result.unsupported()
		return Result.failure(Result.CODE_INVALID_PARAMS, "Invalid sku.")
	var response := await _call("shop.purchase", {"sku": sku})
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	var status: Variant = raw.get("status") if raw is Dictionary else raw
	if not (status is String) or status == "":
		return Result.failure(Result.CODE_INTERNAL, "GameRush returned an unreadable purchase result.")
	return Result.ok(status)


## まだ ack していない付与（買って届いたアイテム）。value は `{"id": String, "sku": String,
## "created_at": String}` の配列。起動時にも読む。
func pending() -> Dictionary:
	return _grants(await _call("shop.pending", {}), false)


## 付与をセーブに反映したことを伝え、value に記録した件数を返す（1 回 1〜100 件の付与の id）。
## **セーブへ反映して保存してから呼ぶこと。** ack した付与は [method pending] に戻らない。
func ack(ids: Array) -> Dictionary:
	var response := await _call("shop.ack", {"ids": ids})
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	var count: Variant = raw.get("acked") if raw is Dictionary else raw
	if not (count is int or count is float):
		return Result.failure(Result.CODE_INTERNAL, "GameRush returned an unreadable count.")
	return Result.ok(int(count))


## 持っている付与のすべて（ack 済みを含む）。value は `{"id", "sku", "created_at", "acked": bool}` の配列。
## セーブを失ったときに持ち物を戻すのに使う。
func owned() -> Dictionary:
	return _grants(await _call("shop.owned", {}), true)


func _call(method: String, params: Dictionary) -> Dictionary:
	# 基本機能ごと止めない。アイテム販売が使えない古いランタイムでは、この機能だけ unsupported にする。
	if not _supported():
		return Result.unsupported()
	var waiting := Call.new()
	_backend.call_api(method, params, func(result: Dictionary) -> void: waiting.resolve(result))
	return await waiting.completed


func _supported() -> bool:
	return (
		not _disposed
		and _grush != null
		and _grush.is_available()
		and _grush.protocol_version() >= SHOP_PROTOCOL_VERSION
	)


static func _grants(response: Dictionary, with_acked: bool) -> Dictionary:
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	if not (raw is Dictionary) or not (raw.get("grants") is Array):
		return Result.failure(Result.CODE_INTERNAL, "GameRush returned unreadable items.")
	var grants: Array = []
	for entry in raw["grants"]:
		if entry is Dictionary and str(entry.get("id", "")) != "":
			grants.append(grant_of(entry, with_acked))
	return Result.ok(grants)


static func grant_of(raw: Dictionary, with_acked: bool) -> Dictionary:
	var grant := {
		"id": str(raw.get("id", "")),
		"sku": str(raw.get("sku", "")),
		"created_at": str(raw.get("createdAt", "")),
	}
	if with_acked:
		var acked: Variant = raw.get("acked")
		grant["acked"] = acked is bool and acked
	return grant


# ランタイムへの登録を、pending_received に接続があるときだけにそろえる（grush_player_state_api.gd の
# _sync_preview_watch と同じ理由）。ランタイムは登録より先に来た合図を、登録したときに1回だけ渡す。
# 接続が無いうちに登録すると、その1回を受け手がいないまま捨てることになる。
func _sync_watch() -> void:
	if not _watch_supported():
		_stop_poll()
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and not tree.process_frame.is_connected(_sync_watch):
		tree.process_frame.connect(_sync_watch)
	# Object.has_connections は Godot 4.4 からなので、4.3 にもある接続の一覧で確かめる。
	var connected := not get_signal_connection_list("pending_received").is_empty()
	if connected == _pending_watching:
		return
	_pending_watching = connected
	if connected:
		var generation := _generation
		_pending_transport.watch(func(sku: String) -> void: _on_pending(generation, sku))
	else:
		_pending_transport.unwatch()


func _stop_poll() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.process_frame.is_connected(_sync_watch):
		tree.process_frame.disconnect(_sync_watch)


# JavaScript の呼び出しの中でゲームのコードを動かさない。
func _on_pending(generation: int, sku: String) -> void:
	_emit_pending.call_deferred(generation, sku)


func _emit_pending(generation: int, sku: String) -> void:
	if not _disposed and generation == _generation:
		pending_received.emit(sku)


func _watch_supported() -> bool:
	return _pending_transport != null and _supported()
