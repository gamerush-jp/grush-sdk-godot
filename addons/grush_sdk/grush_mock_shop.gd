class_name GRushMockShop
extends RefCounted

## エディタ用のアイテム販売。[member products] を売り、[code]GRush.shop.purchase[/code] は決済の画面へ移らずに
## その場で付与を pending に積んで `redirecting` を返し、[code]GRush.shop.pending_received[/code] を後のフレームで
## 起こす。sku の形・ack の id（1〜100 件の UUID）・持っている買い切りの商品の `alreadyOwned` は GameRush と同じ
## 規則で弾く。消費の商品は GameRush と同じく何度でも買え、[code]GRush.shop.owned[/code] に入らない。
## 抽選の商品は確率どおりに（[member lottery_draw] を置けばそのアイテムを）1 つ引いて付与する。当たりが持っている
## 買い切りのアイテムなら、かぶりの扱いに従って代わりのアイテムを渡すか、もう 1 つ渡す（owned の `count` が増える）。
## 付与はプロセスの中だけに持ち、[method reset] で消える。

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const ShopApi := preload("res://addons/grush_sdk/grush_shop_api.gd")

const MAX_ACK_IDS := ShopApi.MAX_ACK_IDS
# GameRush と同じ抽選の規則。確率はベーシスポイント（1 = 0.01%）で、合計がこの値。
const LOTTERY_BP_TOTAL := 10000
const LOTTERY_MIN_ENTRIES := 2
const LOTTERY_MAX_ENTRIES := 30

## 売っている商品。[code]GRush.shop.products[/code] が返すのと同じ形（`sku`・`name`・`price_jpy`・`type`）の
## Dictionary。`price_jpy` は作者が付けられる価格（[code]GRush.ShopApi.Price[/code] のどれか。
## 例: [code]GRush.ShopApi.Price.YEN_120[/code]）で、ほかの値の商品は警告を出して売らない。
## `type` は `"permanent"`（買い切り）・`"consumable"`（消費）・`"lottery"`（抽選）で、省くと `"permanent"`。
## 抽選は、GameRush の Studio で登録するときと同じく、中身と確率を `"odds"`（`{"sku": String, "weight_bp": int}`
## の配列。`weight_bp` はベーシスポイントで 1 = 0.01%、合計 10000、2〜30 件の別々の sku）、かぶりの扱いを
## `"duplicate_policy"`（[code]GRush.ShopApi.DUPLICATE_POLICY_FALLBACK[/code] か
## [code]GRush.ShopApi.DUPLICATE_POLICY_STACK[/code]）、fallback のときに代わりに渡すアイテムを `"fallback_sku"` で
## 書く。中身と `fallback_sku` は [member products] のほかの商品で、中身は買い切りか消費、`fallback_sku` は消費の商品。
## 合わない抽選は警告を出して売らない。[code]GRush.shop.products[/code] は、抽選を GameRush と同じく名前と
## `percent` の `odds`・`duplicate_policy`・`fallback` で返す。
## ほかの形は確かめずにそのまま返す。
static var products: Array = [
	{"sku": "starter_pack", "name": "Starter Pack", "price_jpy": ShopApi.Price.YEN_120},
	{"sku": "remove_ads", "name": "Remove Ads", "price_jpy": ShopApi.Price.YEN_500},
]
## false にすると、Android のアプリと LINE の GameRush と同じく products が `enabled: false` の空の一覧になり、
## purchase が unsupported になる。
static var purchase_available := true
## purchase が返す答え。`"cancelled"` にすると、プレイヤーが決済をやめたときを試せる（付与は積まない）。
## `"purchased"` にすると、iOS のアプリと同じく付与を pending に積んで `purchased` を返す（合図は起こさない）。
## `"pending"` にすると、承認の待ちと同じく付与を積まずに `pending` を返す。
static var purchase_status := "redirecting"
## 抽選で必ず当てるアイテムの sku。その抽選の中身に無い sku と `""` では、確率どおりに引く。かぶりの扱いを試すのに
## 使う。
static var lottery_draw := ""

static var _grants: Array = []
static var _sku_pattern := RegEx.create_from_string(ShopApi.SKU_PATTERN)
static var _uuid_pattern := RegEx.create_from_string(ShopApi.UUID_PATTERN)
# 付与の合図。GameRush と同じく、受け取る相手は1つで後から来たものに置き換え、受け取る相手より先に来た合図は
# 来たときに1回だけ渡す（先に来た合図が2つ以上あれば最後の1つ）。
static var _signal_sku := ""
static var _pending_handler := Callable()
static var _pending_token := 0
static var _next_pending_token := 1


## 決済を通さずに [param sku] の付与を pending に積み、合図を起こす。別の端末で買った分が届くのを試すのに使う。
## sku の形が合わなければ何もせず null、積めば付与（[code]GRush.shop.pending[/code] と同じ形）を返す。
## [member products] の消費の商品の付与は [code]GRush.shop.owned[/code] に入らない。
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
		if _listed(entry):
			var item := {
				"sku": entry.get("sku", ""),
				"name": entry.get("name", ""),
				"priceJpy": entry.get("price_jpy", 0),
				"type": ShopApi.type_of(entry.get("type")),
			}
			var lottery: Variant = _lottery(entry)
			if lottery != null:
				item["odds"] = lottery["odds"].map(
					func(odd: Dictionary) -> Dictionary:
						return {
							"sku": odd["sku"],
							"name": _name_of(odd["sku"]),
							"percent": odd["weight_bp"] / 100.0,
						}
				)
				item["duplicatePolicy"] = lottery["duplicate_policy"]
				var fallback_sku: String = lottery["fallback_sku"]
				item["fallback"] = (
					null
					if fallback_sku == ""
					else {"sku": fallback_sku, "name": _name_of(fallback_sku)}
				)
			listed.append(item)
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
	var lottery: Variant = _lottery(_product(sku))
	# 買い切りの商品は、ack 済みを含め付与済みなら買えない。消費と抽選の商品は何度でも買える。
	if lottery == null and not _consumable(sku) and _owns(sku):
		return Result.ok({"status": ShopApi.PURCHASE_ALREADY_OWNED})
	if purchase_status != ShopApi.PURCHASE_PURCHASED and purchase_status != ShopApi.PURCHASE_REDIRECTING:
		return Result.ok({"status": purchase_status})
	var result := {"sku": sku}
	if lottery != null:
		result = _draw(lottery)
	_grant(result["sku"])
	if purchase_status == ShopApi.PURCHASE_PURCHASED:
		# iOS のアプリは決済の画面へ移らないので、戻りの合図は無い。
		result["status"] = ShopApi.PURCHASE_PURCHASED
		return Result.ok(result)
	_signal(result["sku"])
	return Result.ok({"status": ShopApi.PURCHASE_REDIRECTING})


static func handle_pending() -> Dictionary:
	var grants: Array = []
	for entry in _grants:
		if not bool(entry["acked"]) and grants.size() < MAX_ACK_IDS:
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


# GameRush と同じく、消費のアイテムの付与は owned に入れず、買い切りのアイテムごとに 1 件にする。`count` は持っている
# 数（抽選の stack で同じアイテムがまた当たると増える）で、id・createdAt・acked は最初の付与のもの。
static func handle_owned() -> Dictionary:
	var grants: Array = []
	var by_sku := {}
	for entry in _grants:
		if bool(entry["consumable"]):
			continue
		if by_sku.has(entry["sku"]):
			by_sku[entry["sku"]]["count"] += 1
			continue
		var wire := _wire(entry, true)
		wire["count"] = 1
		by_sku[entry["sku"]] = wire
		grants.append(wire)
	return Result.ok({"grants": grants})


## 確率の表 [param odds]（`{"sku", "weight_bp"}` の配列）から、[param random]（0 以上 1 未満）で 1 つを引いて sku を返す。
static func draw(odds: Array, random: float) -> String:
	var rest := int(floor(random * LOTTERY_BP_TOTAL))
	for entry in odds:
		if rest < int(entry["weight_bp"]):
			return entry["sku"]
		rest -= int(entry["weight_bp"])
	return odds[odds.size() - 1]["sku"]


# 抽選を 1 回引き、渡すアイテム（sku）と、当たったアイテム（drawnSku）と、代わりを渡したか（fallback）を返す。
static func _draw(lottery: Dictionary) -> Dictionary:
	var odds: Array = lottery["odds"]
	var drawn := ""
	for entry in odds:
		if entry["sku"] == lottery_draw:
			drawn = lottery_draw
	if drawn == "":
		drawn = draw(odds, randf())
	var fallback: bool = (
		not _consumable(drawn)
		and lottery["duplicate_policy"] == ShopApi.DUPLICATE_POLICY_FALLBACK
		and _owns(drawn)
	)
	return {
		"sku": lottery["fallback_sku"] if fallback else drawn,
		"drawnSku": drawn,
		"fallback": fallback,
	}


static func _owns(sku: String) -> bool:
	return _grants.any(func(entry: Dictionary) -> bool: return entry["sku"] == sku)


static func _name_of(sku: String) -> String:
	var product: Variant = _product(sku)
	return sku if product == null else str(product.get("name", ""))


# 抽選の商品なら、GameRush が受け付ける形に確かめた `{"odds", "duplicate_policy", "fallback_sku"}`（stack では
# fallback_sku が ""）を返す。抽選でなければ null。受け付けない抽選は [method _listed] が外す。
static func _lottery(entry: Variant) -> Variant:
	if not (entry is Dictionary) or ShopApi.type_of(entry.get("type")) != ShopApi.ITEM_TYPE_LOTTERY:
		return null
	var problem := _lottery_problem(entry)
	if problem != "":
		return null
	var policy: String = entry["duplicate_policy"]
	var fallback_sku := ""
	if policy == ShopApi.DUPLICATE_POLICY_FALLBACK:
		fallback_sku = entry["fallback_sku"]
	var odds: Array = []
	for odd in entry["odds"]:
		odds.append({"sku": odd["sku"], "weight_bp": int(odd["weight_bp"])})
	return {"odds": odds, "duplicate_policy": policy, "fallback_sku": fallback_sku}


# GameRush が抽選を受け付けない理由。受け付けるなら ""。
static func _lottery_problem(entry: Dictionary) -> String:
	var odds: Variant = entry.get("odds")
	if not (odds is Array) or odds.size() < LOTTERY_MIN_ENTRIES or odds.size() > LOTTERY_MAX_ENTRIES:
		return "odds must list 2 to 30 items"
	var seen := {}
	var total := 0
	for odd in odds:
		if not (odd is Dictionary) or not (odd.get("sku") is String) or seen.has(odd["sku"]):
			return "odds must list different skus"
		var weight: Variant = odd.get("weight_bp")
		if weight is float and float(weight) == roundf(float(weight)):
			weight = int(weight)
		if not (weight is int) or weight < 1:
			return "weight_bp must be a whole number of 1 or more"
		var content: Variant = _content(odd["sku"])
		if content == null:
			return "odds must be permanent or consumable products: %s" % odd["sku"]
		seen[odd["sku"]] = true
		total += weight
	if total != LOTTERY_BP_TOTAL:
		return "weight_bp must add up to %d" % LOTTERY_BP_TOTAL
	var policy: Variant = entry.get("duplicate_policy")
	if policy == ShopApi.DUPLICATE_POLICY_STACK:
		var given: Variant = entry.get("fallback_sku")
		if given != null and given != "":
			return "fallback_sku is only for duplicate_policy fallback"
		return ""
	if policy != ShopApi.DUPLICATE_POLICY_FALLBACK:
		return "duplicate_policy must be fallback or stack"
	var fallback: Variant = entry.get("fallback_sku")
	var fallback_product: Variant = _content(fallback) if fallback is String else null
	if (
		fallback_product == null
		or ShopApi.type_of(fallback_product.get("type")) != ShopApi.ITEM_TYPE_CONSUMABLE
	):
		return "fallback_sku must be a consumable product"
	return ""


# 抽選の中身になれる商品（買い切りか消費）。
static func _content(sku: String) -> Variant:
	for entry in products:
		if not (entry is Dictionary) or entry.get("sku") != sku or not _priced(entry):
			continue
		var type := ShopApi.type_of(entry.get("type"))
		if type == ShopApi.ITEM_TYPE_PERMANENT or type == ShopApi.ITEM_TYPE_CONSUMABLE:
			return entry
	return null


static func _sells(sku: String) -> bool:
	return _product(sku) != null


static func _product(sku: String) -> Variant:
	for entry in products:
		if entry is Dictionary and entry.get("sku") == sku and _listed(entry):
			return entry
	return null


# GameRush は作者が付けられる価格の商品しか登録できないので、ほかの価格の商品は売らない。受け付けない抽選も売らない。
static func _listed(entry: Variant) -> bool:
	if not (entry is Dictionary) or not _priced(entry):
		return false
	if ShopApi.type_of(entry.get("type")) != ShopApi.ITEM_TYPE_LOTTERY:
		return true
	var problem := _lottery_problem(entry)
	if problem == "":
		return true
	push_warning("[GRushMock] shop lottery %s left out: %s." % [str(entry.get("sku", "")), problem])
	return false


static func _priced(entry: Dictionary) -> bool:
	var price: Variant = entry.get("price_jpy")
	if ShopApi.is_price(price):
		return true
	push_warning(
		(
			"[GRushMock] shop product %s left out: price_jpy %s is not one of %s."
			% [str(entry.get("sku", "")), str(price), str(ShopApi.PRICES)]
		)
	)
	return false


static func _consumable(sku: String) -> bool:
	var product: Variant = _product(sku)
	return product != null and ShopApi.type_of(product.get("type")) == ShopApi.ITEM_TYPE_CONSUMABLE


static func _grant(sku: String) -> Dictionary:
	var entry := {
		"id": GRushMockInbox.new_id(),
		"sku": sku,
		"createdAt": GRushMockInbox.timestamp(Time.get_unix_time_from_system()),
		"acked": false,
		"consumable": _consumable(sku),
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
