extends RefCounted

# モックが分析イベントに掛ける、GameRush と同じ検査。GameRush と同じ順に確かめ、最初に当たった理由で拒む。
# 通ったイベントは、GameRush へ渡すのと同じ形の Dictionary に作り直す。
# Godot の String は、UTF-16 のバイト列から作った文字列（get_string_from_utf16 など）に対になっていない
# サロゲートの code point を持ちうる。Web の SDK はそれを JSON のエスケープで GameRush へ渡し、GameRush は
# 切れ端を含む文字列を拒むので、モックも同じく拒む。

const KINDS := ["onboarding", "funnel", "custom", "economy"]
const ECONOMY_FLOWS := ["source", "sink"]
const MAX_KEY_LENGTH := 64
const MAX_SHORT_KEY_LENGTH := 32
const MAX_FIELD_KEY_LENGTH := 32
const MAX_FIELDS := 3
const MAX_TEXT_CODE_POINTS := 40
const MIN_STEP := 1
const MAX_STEP := 100
const DEFAULT_CUSTOM_VALUE := 1
const MAX_ABS_CUSTOM_VALUE := 1e9
const MAX_AMOUNT := 1e12
const MAX_ABS_ENDING_BALANCE := 1e15

# 制御文字・行と段落の区切り・双方向の上書きと isolate。連なりを1つの空白にする。
const LINE_BREAKING_OR_CONTROL := "[\\p{Cc}\\p{Zl}\\p{Zp}\\x{202A}-\\x{202E}\\x{2066}-\\x{2069}]+"
# JavaScript の trim が落とす前後の空白。制御文字と行の区切りは先に空白へ直してあるので、ここに来ない。
const EDGE_SPACES := "^[\\p{Zs}\\x{FEFF}\\t\\x{0B}\\x{0C}]+|[\\p{Zs}\\x{FEFF}\\t\\x{0B}\\x{0C}]+$"
# 空白・制御文字・書式文字・既定で描かない文字（Default_Ignorable_Code_Point）と、空白にしか見えない字形の
# 文字だけの文字列。
const VISIBLY_BLANK := (
	"^[\\s\\p{Z}\\p{Cc}\\p{Cf}"
	+ "\\x{00AD}\\x{034F}\\x{061C}\\x{115F}\\x{1160}\\x{17B4}\\x{17B5}\\x{180B}-\\x{180F}"
	+ "\\x{200B}-\\x{200F}\\x{202A}-\\x{202E}\\x{2060}-\\x{206F}\\x{3164}\\x{FE00}-\\x{FE0F}"
	+ "\\x{FEFF}\\x{FFA0}\\x{FFF0}-\\x{FFF8}\\x{1BCA0}-\\x{1BCA3}\\x{1D173}-\\x{1D17A}"
	+ "\\x{E0000}-\\x{E0FFF}\\x{2800}]*$"
)

static var _line_breaking: RegEx
static var _edges: RegEx
static var _blank: RegEx


## kind と params から作ったイベントを確かめる。通れば {"ok": true, "event": Dictionary}、拒めば
## {"ok": false, "reason": String}。
static func sanitize(kind: String, params: Dictionary) -> Dictionary:
	if not KINDS.has(kind):
		return _reject("kind")
	var fields: Variant = _sanitize_fields(params.get("fields"))
	if fields is String:
		return _reject(fields)
	match kind:
		"onboarding", "funnel":
			return _sanitize_step(kind, params, fields)
		"custom":
			return _sanitize_custom(params, fields)
		_:
			return _sanitize_economy(params, fields)


## 1行のテキストに直す。長すぎるか String でなければ null（StringName も、GameRush へは文字列として届かないので拒む）、
## 見えない文字だけなら空文字。
static func line_text(value: Variant) -> Variant:
	if not value is String:
		return null
	# GameRush は切れ端を含む文字列を拒む。空白への置き換えと前後の空白の除去は切れ端を残すので、先に確かめても
	# 結果は同じ。
	if _has_surrogate_code_point(value):
		return null
	_compile()
	var text := _line_breaking.sub(value, " ", true)
	text = _edges.sub(text, "", true)
	if text.length() > MAX_TEXT_CODE_POINTS:
		return null
	return "" if _blank.search(text) != null else text


static func _sanitize_step(kind: String, params: Dictionary, fields: Variant) -> Dictionary:
	var step: Variant = params.get("step")
	if not _is_step(step):
		return _reject("step")
	var step_name: Variant = _optional_text(params.get("stepName"))
	if step_name is bool:
		return _reject("text")
	var event := {"kind": kind}
	if kind == "funnel":
		var funnel: Variant = params.get("funnel")
		if not _is_key(funnel, MAX_KEY_LENGTH, false):
			return _reject("name")
		event["funnel"] = str(funnel)
		var session: Variant = params.get("funnelSessionId")
		if session != null and str(session) != "":
			if not _is_key(session, MAX_KEY_LENGTH, false):
				return _reject("name")
			event["funnelSessionId"] = str(session)
	event["step"] = int(step)
	if step_name != null:
		event["stepName"] = step_name
	if fields != null:
		event["fields"] = fields
	return {"ok": true, "event": event}


static func _sanitize_custom(params: Dictionary, fields: Variant) -> Dictionary:
	var event_name: Variant = params.get("name")
	if not _is_key(event_name, MAX_KEY_LENGTH, false):
		return _reject("name")
	var value: Variant = params.get("value", DEFAULT_CUSTOM_VALUE)
	if not _is_finite_number(value) or absf(float(value)) > MAX_ABS_CUSTOM_VALUE:
		return _reject("value")
	var event := {"kind": "custom", "name": str(event_name), "value": value}
	if fields != null:
		event["fields"] = fields
	return {"ok": true, "event": event}


static func _sanitize_economy(params: Dictionary, fields: Variant) -> Dictionary:
	var flow_type: Variant = params.get("flowType")
	if not (flow_type is String and ECONOMY_FLOWS.has(flow_type)):
		return _reject("flowType")
	var currency: Variant = params.get("currency")
	if not _is_key(currency, MAX_SHORT_KEY_LENGTH, false):
		return _reject("currency")
	var amount: Variant = params.get("amount")
	if not _is_finite_number(amount) or float(amount) <= 0 or float(amount) > MAX_AMOUNT:
		return _reject("amount")
	var ending_balance: Variant = params.get("endingBalance")
	if (
		not _is_finite_number(ending_balance)
		or absf(float(ending_balance)) > MAX_ABS_ENDING_BALANCE
	):
		return _reject("endingBalance")
	var transaction_type: Variant = params.get("transactionType")
	if not _is_key(transaction_type, MAX_SHORT_KEY_LENGTH, false):
		return _reject("transactionType")
	var item_sku: Variant = _optional_text(params.get("itemSku"))
	if item_sku is bool:
		return _reject("text")
	var event := {
		"kind": "economy",
		"flowType": flow_type,
		"currency": str(currency),
		"amount": amount,
		"endingBalance": ending_balance,
		"transactionType": str(transaction_type),
	}
	if item_sku != null:
		event["itemSku"] = item_sku
	if fields != null:
		event["fields"] = fields
	return {"ok": true, "event": event}


# null と空は省略で null。不正なら理由の String。キーと値を作り直し、値は1行に直したものを持つ。
static func _sanitize_fields(value: Variant) -> Variant:
	if value == null:
		return null
	if not value is Dictionary:
		return "fields"
	if value.size() > MAX_FIELDS:
		return "fields"
	var normalized := {}
	for key in value:
		var text: Variant = line_text(value[key])
		if not _is_key(str(key), MAX_FIELD_KEY_LENGTH, true) or text == null or text == "":
			return "fields"
		normalized[str(key)] = text
	return null if normalized.is_empty() else normalized


# 省略（null）と、1行に直した結果が空のものは null。不正なら false。
static func _optional_text(value: Variant) -> Variant:
	if value == null:
		return null
	var text: Variant = line_text(value)
	if text == null:
		return false
	return null if text == "" else text


static func _is_step(value: Variant) -> bool:
	if value is int:
		return value >= MIN_STEP and value <= MAX_STEP
	if value is float:
		return is_finite(value) and value == floorf(value) and value >= MIN_STEP and value <= MAX_STEP
	return false


# Godot の String は1文字を1つのコードポイントで持つので、U+D800〜U+DFFF の値が残るのは対になっていない切れ端だけ。
static func _has_surrogate_code_point(text: String) -> bool:
	for index in text.length():
		var c := text.unicode_at(index)
		if c >= 0xD800 and c <= 0xDFFF:
			return true
	return false


static func _is_finite_number(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value))


# 名前の鍵（英数字と ._:-）か、field のキー（英数字と _）。
static func _is_key(value: Variant, max_length: int, field_key: bool) -> bool:
	if not value is String:
		return false
	var text: String = value
	if text.is_empty() or text.length() > max_length:
		return false
	for index in text.length():
		var code := text.unicode_at(index)
		var alphanumeric := (
			(code >= 0x41 and code <= 0x5A) or (code >= 0x61 and code <= 0x7A) or (code >= 0x30 and code <= 0x39)
		)
		var punctuation := code == 0x5F if field_key else code in [0x2E, 0x5F, 0x3A, 0x2D]
		if not alphanumeric and not punctuation:
			return false
	return true


static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _compile() -> void:
	if _line_breaking != null:
		return
	_line_breaking = RegEx.create_from_string(LINE_BREAKING_OR_CONTROL)
	_edges = RegEx.create_from_string(EDGE_SPACES)
	_blank = RegEx.create_from_string(VISIBLY_BLANK)
