class_name GRushMockShop
extends RefCounted

## エディタ用のアイテム販売。[member products] を売り、[code]GRush.shop.purchase[/code] は決済の画面へ移らずに
## その場で付与を pending に積んで `redirecting` を返し、[code]GRush.shop.pending_received[/code] を後のフレームで
## 起こす。sku の形・ack の id（1〜100 件の UUID）・持っている商品の `alreadyOwned` は GameRush と同じ規則で弾く。
## 付与はプロセスの中だけに持ち、[method reset] で消える。

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const ShopApi := preload("res://addons/grush_sdk/grush_shop_api.gd")

const MAX_ACK_IDS := 100

## 売っている商品。[code]GRush.shop.products[/code] が返すのと同じ形（`sku`・`name`・`price_jpy`）の Dictionary。
## 形は確かめずにそのまま返す。
static var products: Array = [
	{"sku": "starter_pack", "name": "Starter Pack", "price_jpy": 120},
	{"sku": "remove_ads", "name": "Remove Ads", "price_jpy": 480},
]
## false にすると、アプリと LINE の GameRush と同じく products が `enabled: false` の空の一覧になり、
## purchase が unsupported になる。
static var purchase_available := true
## purchase が返す答え。`"cancelled"` にすると、プレイヤーが決済をやめたときを試せる（付与は積まない）。
static var purchase_status := "redirecting"

static var _grants: Array = []
static var _sku_pattern := RegEx.create_from_string(ShopApi.SKU_PATTERN)
static var _uuid_pattern := RegEx.create_from_string(
	"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)
# 付与の合図。GameRush と同じく、受け取る相手は1つで後から来たものに置き換え、受け取る相手より先に来た合図は
# 来たときに1回だけ渡す（先に来た合図が2つ以上あれば最後の1つ）。
static var _signal_sku := ""
static var _pending_handler := Callable()
static var _pending_token := 0
static var _next_pending_token := 1


## 決済を通さずに [param sku] の付与を pending に積み、合図を起こす。別の端末で買った分が届くのを試すのに使う。
## sku の形が合わなければ何もせず null、積めば付与（[code]GRush.shop.pending[/code] と同じ形）を返す。
static func grant(sku: String) -> Variant:
	if _sku_pattern.search(sku) == null:
		return null
	var entry := _grant(sku)
	_signal(sku)
	return ShopApi.grant_of(_wire(entry, false), false)


## 付与と、まだ渡していない合図を消す。[member products] などの設定は戻さない。
static func reset() -> void:
	_grants.clear()
	_signal_sku = ""


## 付与の合図を受け取る相手を置き、外すときに渡す番号を返す。SDK のモックの受け取り口が呼ぶ。
static func watch_pending(handler: Callable) -> int:
	_pending_handler = handler
	_pending_token = _next_pending_token
	_next_pending_token += 1
	_deliver()
	return _pending_token


static func unwatch_pending(token: int) -> void:
	if token != _pending_token:
		return
	_pending_handler = Callable()
	_pending_token = 0


static func handle_products() -> Dictionary:
	if not purchase_available:
		return Result.ok({"enabled": false, "products": []})
	var listed: Array = []
	for entry in products:
		if entry is Dictionary:
			listed.append(
				{
					"sku": entry.get("sku", ""),
					"name": entry.get("name", ""),
					"priceJpy": entry.get("price_jpy", 0),
				}
			)
	return Result.ok({"enabled": true, "products": listed})


static func handle_purchase(params: Dictionary) -> Dictionary:
	if not purchase_available:
		return Result.failure(Result.CODE_UNSUPPORTED, "Purchases are not available here.")
	var sku: Variant = params.get("sku")
	if not (sku is String) or _sku_pattern.search(sku) == null:
		return _invalid("Invalid sku.")
	if not GRushMock.signed_in:
		return Result.failure(Result.CODE_SIGN_IN_REQUIRED, "Purchases require sign-in.")
	if not _sells(sku):
		return _invalid("Item not found.")
	if _grants.any(func(entry: Dictionary) -> bool: return entry["sku"] == sku):
		return Result.ok({"status": "alreadyOwned"})
	if purchase_status != "redirecting":
		return Result.ok({"status": purchase_status})
	_grant(sku)
	_signal(sku)
	return Result.ok({"status": "redirecting"})


static func handle_pending() -> Dictionary:
	var grants: Array = []
	for entry in _grants:
		if not bool(entry["acked"]):
			grants.append(_wire(entry, false))
	return Result.ok({"grants": grants})


static func handle_ack(params: Dictionary) -> Dictionary:
	var ids: Variant = params.get("ids")
	if not (ids is Array) or ids.is_empty() or ids.size() > MAX_ACK_IDS:
		return _invalid("ids must be 1 to 100 grant ids.")
	var wanted := {}
	for id in ids:
		if not (id is String) or _uuid_pattern.search(id) == null:
			return _invalid("ids must be 1 to 100 grant ids.")
		wanted[id.to_lower()] = true
	var acked := 0
	for entry in _grants:
		if wanted.has(entry["id"]) and not bool(entry["acked"]):
			entry["acked"] = true
			acked += 1
	return Result.ok({"acked": acked})


static func handle_owned() -> Dictionary:
	var grants: Array = []
	for entry in _grants:
		grants.append(_wire(entry, true))
	return Result.ok({"grants": grants})


static func _sells(sku: String) -> bool:
	for entry in products:
		if entry is Dictionary and entry.get("sku") == sku:
			return true
	return false


static func _grant(sku: String) -> Dictionary:
	var entry := {
		"id": GRushMockInbox.new_id(),
		"sku": sku,
		"createdAt": GRushMockInbox.timestamp(Time.get_unix_time_from_system()),
		"acked": false,
	}
	_grants.append(entry)
	return entry


static func _wire(entry: Dictionary, with_acked: bool) -> Dictionary:
	var wire := {"id": entry["id"], "sku": entry["sku"], "createdAt": entry["createdAt"]}
	if with_acked:
		wire["acked"] = entry["acked"]
	return wire


static func _signal(sku: String) -> void:
	_signal_sku = sku
	_deliver()


# GameRush と同じく、受け取る相手を呼ぶのは後に回す。
static func _deliver() -> void:
	if not _pending_handler.is_valid() or _signal_sku == "":
		return
	var sku := _signal_sku
	_signal_sku = ""
	_pending_handler.call_deferred(sku)


static func _invalid(message: String) -> Dictionary:
	return Result.failure(Result.CODE_INVALID_PARAMS, message)
