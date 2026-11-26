extends RefCounted

## 作者のアイテム販売。作者が GameRush の Studio か API キーで登録した商品を、プレイヤーが買う。
## GameRush は払った人にアイテムを届けることまでを保証する。ゲームの中での使用は改ざんを防げない。
##
## 商品の種類（`type`）は 3 つ。[constant ITEM_TYPE_PERMANENT]（買い切り）は同じプレイヤーが返金されない限り
## 1 回だけ買え、[method owned] に入る。[constant ITEM_TYPE_CONSUMABLE]（消費）は同じプレイヤーが何度でも買え、
## 買うたびに付与が 1 件ずつ [method pending] に入り、[method owned] には入らない。
## [constant ITEM_TYPE_LOTTERY]（抽選）は同じプレイヤーが何度でも買え、買うたびに同じゲームの買い切りか消費の
## アイテムを 1 つ確率で引いて、その付与を [method pending] に入れる。抽選を返すのは版数が
## [constant LOTTERY_PROTOCOL_VERSION] 以上のランタイムだけ。
## 消費のアイテムを、ゲーム内通貨（ほかのアイテムや機能と交換する対価）として使ってはならない。抽選の商品を
## 作れるかは、GameRush の販売に関する取り決めに従う。
##
## 購入できるのは Web の GameRush と iOS のアプリ。Android のアプリと LINE では [method purchase] が
## unsupported、[method products] は `enabled` が false の空の一覧で、[method pending]・[method ack]・
## [method owned] も unsupported。
##
## 取りこぼさないために、次の順で使う。
## 1. [method purchase] を呼ぶ前にセーブする。`redirecting` が返ると、ページはすぐ決済の画面へ移る。
## 2. 起動時、[signal pending_received] を受けたとき、[method purchase] が `purchased` を返したときに
##    [method pending] を読む。
## 3. 付与をセーブに反映し、セーブを永続化してから [method ack] する。ack は「ゲームへ届けた」ことを表し、
##    ack するまで付与は pending に残る。
## 4. 反映した付与の id をセーブに持ち、同じ付与を二度反映しない。消費のアイテムは [method owned] で
##    組み直せないので、特に大事。
##
## ランタイムの版数が [constant SHOP_PROTOCOL_VERSION] 未満なら、どの呼び出しも unsupported。

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const Call := preload("res://addons/grush_sdk/grush_call.gd")

## アイテム販売が使えるランタイムの版数。
const SHOP_PROTOCOL_VERSION := 12

## 商品の種類の買い切り。同じプレイヤーは返金されない限り 1 回だけ買え、[method owned] に入る。
const ITEM_TYPE_PERMANENT := "permanent"
## 商品の種類の消費。同じプレイヤーが何度でも買え、[method owned] には入らない。
## ゲーム内通貨に使ってはならない。
const ITEM_TYPE_CONSUMABLE := "consumable"
## 商品の種類の抽選。同じプレイヤーが何度でも買え、買うたびに中身（`odds`）から 1 つを確率で引いて渡す。
## 抽選そのものは [method owned] に入らない。
const ITEM_TYPE_LOTTERY := "lottery"

## 抽選（[constant ITEM_TYPE_LOTTERY]）を返すランタイムの版数。これより古いランタイムでは [method products] に
## 抽選が出ず、[method purchase_detail] に `sku` などが載らず、[method owned] の `count` は 1。
const LOTTERY_PROTOCOL_VERSION := 15

## 抽選のかぶりの扱い。持っている買い切りのアイテムが当たったら、代わりに `fallback` のアイテム（消費）を渡す。
const DUPLICATE_POLICY_FALLBACK := "fallback"
## 抽選のかぶりの扱い。持っている買い切りのアイテムが当たったら、それをもう 1 つ渡し、[method owned] の
## `count` が増える。
const DUPLICATE_POLICY_STACK := "stack"

## 作者が商品に付けられる税込みの価格（円）。GameRush はこのどれかの価格だけを登録できる。値は円の額そのもので、
## `Price.YEN_120` は 120。[method products] の `price_jpy` もこのどれかの int。
enum Price {
	## 100 円。
	YEN_100 = 100,
	## 120 円。
	YEN_120 = 120,
	## 300 円。
	YEN_300 = 300,
	## 500 円。
	YEN_500 = 500,
	## 1,000 円。
	YEN_1000 = 1000,
	## 2,000 円。
	YEN_2000 = 2000,
	## 3,000 円。
	YEN_3000 = 3000,
	## 5,000 円。
	YEN_5000 = 5000,
}

## 作者が付けられる価格（円）を安い順に並べたもの。[enum Price] の値と同じ。
const PRICES := [
	Price.YEN_100,
	Price.YEN_120,
	Price.YEN_300,
	Price.YEN_500,
	Price.YEN_1000,
	Price.YEN_2000,
	Price.YEN_3000,
	Price.YEN_5000,
]

## [method purchase] の答え。ページがすぐ決済の画面へ移る（Web）。
const PURCHASE_REDIRECTING := "redirecting"
## [method purchase] の答え。買い終え、付与が [method pending] に入った（iOS のアプリ）。
const PURCHASE_PURCHASED := "purchased"
## [method purchase] の答え。支払いの確認や保護者の承認を待っている。済むと付与が [method pending] に入る
## （iOS のアプリ）。
const PURCHASE_PENDING := "pending"
## [method purchase] の答え。プレイヤーが購入をやめた。
const PURCHASE_CANCELLED := "cancelled"
## [method purchase] の答え。同じ買い切りの商品をもう持っている。消費と抽選のアイテムでは返らない。
const PURCHASE_ALREADY_OWNED := "alreadyOwned"

## GameRush と同じ sku の形。`$` は末尾の改行の前でも合うので `\z` で終える。
const SKU_PATTERN := "^[a-z0-9][a-z0-9_.-]{0,63}\\z"

## [method ack] に1回で渡せる付与の id の数。[method pending] が1回で返す付与の数の上限も同じ。
const MAX_ACK_IDS := 100

const UUID_PATTERN := "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\\z"

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
var _uuid_pattern := RegEx.create_from_string(UUID_PATTERN)


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
## `{"sku": String, "name": String, "price_jpy": int, "type": String}`。`type` は
## [constant ITEM_TYPE_PERMANENT]・[constant ITEM_TYPE_CONSUMABLE]・[constant ITEM_TYPE_LOTTERY]。種類を返さない
## 古い GameRush の商品は [constant ITEM_TYPE_PERMANENT]、この SDK が知らない種類は GameRush が返した文字列のまま入る。
## 抽選の商品は、さらに中身と確率の `"odds"`（`{"sku": String, "name": String, "percent": float}` の配列。
## `percent` は小数第 2 位までで合計 100）と、かぶりの扱いの `"duplicate_policy"`（[constant DUPLICATE_POLICY_FALLBACK]
## か [constant DUPLICATE_POLICY_STACK]）と、[constant DUPLICATE_POLICY_FALLBACK] のときに代わりに渡すアイテムの
## `"fallback"`（`{"sku": String, "name": String}`。[constant DUPLICATE_POLICY_STACK] では null）を持つ。
## 販売が止まっているときと Android のアプリ・LINE では `enabled` が false で `products` は空。
## iOS のアプリでは、App Store の価格（100・120・300・500・1,000 円）に合う商品だけが入る。
func products() -> Dictionary:
	var response := await _call("shop.products", {})
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	if not (raw is Dictionary) or not (raw.get("products") is Array):
		return Result.failure(Result.CODE_INTERNAL, "GameRush returned an unreadable product list.")
	var enabled: Variant = raw.get("enabled")
	# 止まっている販売の商品は買えないので、ランタイムが何か返しても見せない。
	if not (enabled is bool and enabled):
		return Result.ok({"enabled": false, "products": []})
	var lotteries: bool = _grush.protocol_version() >= LOTTERY_PROTOCOL_VERSION
	var items: Array = []
	for entry in raw["products"]:
		if entry is Dictionary and str(entry.get("sku", "")) != "":
			var price: Variant = entry.get("priceJpy")
			var item := {
				"sku": str(entry["sku"]),
				"name": str(entry.get("name", "")),
				"price_jpy": int(price) if price is int or price is float else 0,
				"type": type_of(entry.get("type")),
			}
			if item["type"] != ITEM_TYPE_LOTTERY:
				items.append(item)
			# 抽選は確率の表を付けずには見せない。版数 15 より古いランタイムは抽選を返さないので、来ても外す。
			elif lotteries and lottery_of(entry, item):
				items.append(item)
	return Result.ok({"enabled": true, "products": items})


## [param sku] の商品を買う。value は `PURCHASE_*` の定数の文字列で、`redirecting`（ページが決済の画面へ移る。
## Web）・`purchased`（買い終え、付与が [method pending] に入った。iOS のアプリ）・`pending`（支払いの確認や
## 保護者の承認の待ち。済むと [method pending] に入る。iOS のアプリ）・`cancelled`（プレイヤーがやめた）・
## `alreadyOwned`（同じ買い切りの商品をもう持っている。消費と抽選のアイテムでは返らない）のどれか。この SDK が知らない
## 値も文字列のまま返す。**呼ぶ前にセーブしておくこと。** `redirecting` の後、ゲームのページはすぐ閉じる。
## 付与は決済から戻ったときに [signal pending_received] と [method pending] で届く。`purchased` が返ったら
## [method pending] を読む。
## sku が `^[a-z0-9][a-z0-9_.-]{0,63}$` に合わなければ送らずに invalidParams。ゲストは signInRequired、
## Android のアプリと LINE では unsupported。プレイヤーの答えを待つので、返るまで長くかかることがある。
## 渡したアイテムも知りたいときは [method purchase_detail] を使う。
func purchase(sku: String) -> Dictionary:
	var response := await purchase_detail(sku)
	if not response["ok"]:
		return response
	return Result.ok(response["value"]["status"])


## [method purchase] と同じく [param sku] の商品を買い、value に `{"status": String, "sku": String,
## "drawn_sku": String, "fallback": bool}` を返す。`status` は [method purchase] の value と同じ。
## `sku` は渡したアイテムで、`status` が [constant PURCHASE_PURCHASED] のときだけ、GameRush が付与を知らせたら入る
## （版数 [constant LOTTERY_PROTOCOL_VERSION] 以上のランタイム）。ほかは ""。
## 抽選では、当たったアイテムが `drawn_sku` に入り、持っている買い切りのアイテムが当たって代わり（商品の
## `fallback`）を渡したときは `fallback` が true で `sku` が代わりのアイテム。抽選でなければ `drawn_sku` は ""、
## `fallback` は false。どれも届いたアイテムを見せる演出に使い、セーブへの反映は [method pending] の付与で行う。
## 送る前の確かめとエラーは [method purchase] と同じ。
func purchase_detail(sku: String) -> Dictionary:
	if _sku_pattern.search(sku) == null:
		if not _supported():
			return Result.unsupported()
		return Result.failure(Result.CODE_INVALID_PARAMS, "Invalid sku.")
	var response := await _call("shop.purchase", {"sku": sku})
	if not response["ok"]:
		return response
	var detail: Variant = purchase_detail_of(response["value"])
	if detail == null:
		return Result.failure(Result.CODE_INTERNAL, "GameRush returned an unreadable purchase result.")
	return Result.ok(detail)


## まだ ack していない付与（買って届いたアイテム）。value は `{"id": String, "sku": String,
## "created_at": String, "count": int}` の配列（`count` はいつも 1）で、1回に [constant MAX_ACK_IDS] 件まで。起動時にも読む。
## ack したら、残りがあるかもしれないのでもう一度読む（空になるまで繰り返す）。
func pending() -> Dictionary:
	return _grants(await _call("shop.pending", {}), false)


## 付与をゲームへ届けたこと（セーブに反映したこと）を伝え、value に記録した件数を返す（1 回 1〜100 件の付与の id）。
## **セーブへ反映して保存し、反映した付与の id をセーブに持ってから呼ぶこと。** ack した付与は [method pending] に戻らない。
## 件数か id の形（UUID）が合わなければ送らずに invalidParams。
func ack(ids: Array) -> Dictionary:
	if not _ids_valid(ids):
		if not _supported():
			return Result.unsupported()
		return Result.failure(Result.CODE_INVALID_PARAMS, "ids must be 1 to 100 grant ids.")
	var response := await _call("shop.ack", {"ids": ids})
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	var count: Variant = raw.get("acked") if raw is Dictionary else raw
	if not (count is int or count is float):
		return Result.failure(Result.CODE_INTERNAL, "GameRush returned an unreadable count.")
	return Result.ok(int(count))


## 持っている買い切りのアイテムを、アイテムごとに 1 件（ack 済みを含む）。value は
## `{"id", "sku", "created_at", "acked": bool, "count": int}` の配列。`count` は持っている数で、抽選
## （[constant DUPLICATE_POLICY_STACK]）で同じアイテムがまた当たると増える。`id`・`created_at`・`acked` はその
## アイテムの最初の付与のもの。数を返さない古い GameRush では 1。
## 返金された付与と、消費のアイテムの付与は入らない。セーブを失ったときに持ち物を戻すのに使う。
func owned() -> Dictionary:
	return _grants(await _call("shop.owned", {}), true)


func _call(method: String, params: Dictionary) -> Dictionary:
	# 基本機能ごと止めない。アイテム販売が使えない古いランタイムでは、この機能だけ unsupported にする。
	if not _supported():
		return Result.unsupported()
	var waiting := Call.new()
	_backend.call_api(method, params, func(result: Dictionary) -> void: waiting.resolve(result))
	return await waiting.completed


func _ids_valid(ids: Array) -> bool:
	if ids.is_empty() or ids.size() > MAX_ACK_IDS:
		return false
	for id in ids:
		if not (id is String) or _uuid_pattern.search(id) == null:
			return false
	return true


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
		# id か sku の無い付与は、反映も ack もできないので捨てる。
		if entry is Dictionary and _filled(entry.get("id")) and _filled(entry.get("sku")):
			grants.append(grant_of(entry, with_acked))
	return Result.ok(grants)


static func _filled(value: Variant) -> bool:
	return value is String and value != ""


## GameRush が返した商品の種類を、[method products] が返す `type` にする。種類を返さない古い GameRush の商品は
## どれも買い切りなので [constant ITEM_TYPE_PERMANENT]。知らない文字列は新しい GameRush の種類として、そのまま返す。
static func type_of(raw: Variant) -> String:
	return str(raw) if _filled(raw) else ITEM_TYPE_PERMANENT


## [param value] が作者の付けられる価格（[constant PRICES] のどれか）なら true。JSON から読んだ値のように、
## 整数の値の float も認める。
static func is_price(value: Variant) -> bool:
	if value is float and float(value) == roundf(float(value)):
		return PRICES.has(int(value))
	return value is int and PRICES.has(value)


static func grant_of(raw: Dictionary, with_acked: bool) -> Dictionary:
	var grant := {
		"id": str(raw.get("id", "")),
		"sku": str(raw.get("sku", "")),
		"created_at": str(raw.get("createdAt", "")),
	}
	if with_acked:
		var acked: Variant = raw.get("acked")
		grant["acked"] = acked is bool and acked
	# pending の付与は 1 件で 1 つ。Unity の GRushShopGrant.Count と揃える。
	grant["count"] = _count_of(raw.get("count")) if with_acked else 1
	return grant


# JSON の数は float で届く。整数でない値・1 未満・count を返さない古い GameRush は 1。
static func _count_of(raw: Variant) -> int:
	if raw is int and raw >= 1:
		return raw
	if raw is float and raw >= 1.0 and raw == roundf(raw):
		return int(raw)
	return 1


## GameRush が返した抽選の中身と確率・かぶりの扱い・代わりのアイテムを [param item] へ足し、読めれば true。
## 読めない抽選は確率を見せずに売ることになるので、[method products] は外す。
static func lottery_of(raw: Dictionary, item: Dictionary) -> bool:
	var list: Variant = raw.get("odds")
	if not (list is Array) or list.is_empty():
		return false
	var odds: Array = []
	for entry in list:
		if not (entry is Dictionary) or not _filled(entry.get("sku")):
			return false
		var percent: Variant = entry.get("percent")
		if not (percent is float or percent is int):
			return false
		odds.append(
			{"sku": str(entry["sku"]), "name": str(entry.get("name", "")), "percent": float(percent)}
		)
	var policy: Variant = raw.get("duplicatePolicy")
	var fallback: Variant = null
	if policy == DUPLICATE_POLICY_FALLBACK:
		var given: Variant = raw.get("fallback")
		if not (given is Dictionary) or not _filled(given.get("sku")):
			return false
		fallback = {"sku": str(given["sku"]), "name": str(given.get("name", ""))}
	elif policy != DUPLICATE_POLICY_STACK:
		return false
	item["odds"] = odds
	item["duplicate_policy"] = str(policy)
	item["fallback"] = fallback
	return true


## GameRush が返した購入の結果を、[method purchase_detail] の value にする。読めなければ null。
static func purchase_detail_of(raw: Variant) -> Variant:
	var status: Variant = raw.get("status") if raw is Dictionary else raw
	if not (status is String) or status == "":
		return null
	var detail := {"status": status, "sku": "", "drawn_sku": "", "fallback": false}
	if status != PURCHASE_PURCHASED or not (raw is Dictionary) or not _filled(raw.get("sku")):
		return detail
	detail["sku"] = raw["sku"]
	var fallback: Variant = raw.get("fallback")
	if _filled(raw.get("drawnSku")) and fallback is bool:
		detail["drawn_sku"] = raw["drawnSku"]
		detail["fallback"] = fallback
	return detail


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
