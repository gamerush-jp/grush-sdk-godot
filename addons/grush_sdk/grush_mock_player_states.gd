class_name GRushMockPlayerStates
extends RefCounted

## エディタ用の「他プレイヤーの公開状態」。実サーバへ繋がずに、他人の進捗を
## 読む側のコードを試せるようにする。
##
## hidden の扱いも再現する。運営が伏せた状態が get から返らないことは、
## ゲーム側が「必ず全員分返る」前提で書いていないかを確かめる唯一の場所。
##
## モックの相手（[constant GRushMock.RIVALS]）は、はじめから rating 付きの状態を持つので、
## 相手探し（[code]GRush.player_state.sample[/code]）がそのまま試せる。[method reset] の後も持ち直す。

const Result := preload("res://addons/grush_sdk/grush_result.gd")

const SAMPLE_DEFAULT_COUNT := 10
const SAMPLE_MAX_COUNT := 20
const RATING_LIMIT := 1e9
const RIVAL_RATINGS := [1000.0, 1200.0, 1500.0]

static var _states: Dictionary = {}
static var _seeded := false
# 確認用の表示。GameRush と同じく、受け取る相手は1つで後から来たものに置き換え、同じ状態は1回だけ渡し、
# 受け取る相手が状態より後に来ても、来たときに渡す。
static var _preview: Variant = null
static var _preview_seq := 0
static var _preview_delivered_seq := 0
static var _preview_handler := Callable()
static var _preview_token := 0
static var _next_preview_token := 1


## [param rating] を渡すと、相手探しの範囲の絞り込みを試せる。
static func define(
	pseudo_id: String, payload: Dictionary, hidden: bool = false, rating: Variant = null
) -> void:
	_ensure_rivals()
	_put(pseudo_id, payload, hidden, rating)


## 置いた状態と、まだ渡していない確認用の表示の状態を消し、モックの相手の状態を置き直す。
static func reset() -> void:
	_states.clear()
	_seeded = false
	_preview = null
	_preview_delivered_seq = _preview_seq
	_ensure_rivals()


## GameRush の確認用の表示を起こす。[param pseudo_id] と [param payload] を持つ公開プレイヤー状態が、
## [code]GRush.player_state.preview_received[/code] で後のフレームに届く（`updated_at` は呼んだ時刻）。
## 呼ぶたびに1回だけ届く。接続が無いうちに呼んだ分は、最後に呼んだ分だけが接続した後に届く。
## GameRush が渡す `pseudo_id` は本物の疑似 ID ではない決まった値で、`rating` は null。
## [param pseudo_id] が空、[param revision] が負、[param rating] が有限の数値でも null でもないときは何もしない。
static func preview(
	pseudo_id: String, payload: Dictionary, revision: int = 1, rating: Variant = null
) -> void:
	if pseudo_id == "" or revision < 0:
		return
	if rating != null and not _is_finite_number(rating):
		return
	_preview = {
		"pseudoId": pseudo_id,
		"payload": payload.duplicate(true),
		"revision": revision,
		"rating": null if rating == null else float(rating),
		"updatedAt": Time.get_datetime_string_from_system(true) + "Z",
	}
	_preview_seq += 1
	_deliver_preview()


## 確認用の表示の状態を受け取る相手を置き、外すときに渡す番号を返す。SDK のモックの受け取り口が呼ぶ。
static func watch_preview(handler: Callable) -> int:
	_preview_handler = handler
	_preview_token = _next_preview_token
	_next_preview_token += 1
	_deliver_preview()
	return _preview_token


static func unwatch_preview(token: int) -> void:
	if token != _preview_token:
		return
	_preview_handler = Callable()
	_preview_token = 0


# GameRush と同じく、受け取る相手を呼ぶのは後に回す。
static func _deliver_preview() -> void:
	if not _preview_handler.is_valid() or _preview == null:
		return
	if _preview_delivered_seq == _preview_seq:
		return
	_preview_delivered_seq = _preview_seq
	_preview_handler.call_deferred(_preview.duplicate(true))


static func exists(pseudo_id: String) -> bool:
	_ensure_rivals()
	return _states.has(pseudo_id)


## 運営が伏せていない状態があるか。get・report から見える相手かどうか。
static func is_visible(pseudo_id: String) -> bool:
	_ensure_rivals()
	return _states.has(pseudo_id) and not bool(_states[pseudo_id]["hidden"])


## 実サーバと同じく、未ログインと、見えない相手（無い・伏せた）への通報を弾く。
static func handle_report(params: Dictionary) -> Dictionary:
	if not GRushMock.signed_in:
		return Result.failure(Result.CODE_SIGN_IN_REQUIRED, "Reporting requires sign-in.")
	var pseudo_id: Variant = params.get("pseudoId")
	if not (pseudo_id is String) or not is_visible(pseudo_id):
		return _invalid("No player state for that id.")
	return Result.ok({"reported": GRushMock.confirm_player_state_report})


static func is_rating(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var number := float(value)
	return is_finite(number) and number > -RATING_LIMIT and number < RATING_LIMIT


static func get_many(pseudo_ids: Variant) -> Array:
	_ensure_rivals()
	var ids: Array = pseudo_ids if pseudo_ids is Array else []
	var out: Array = []
	for id in ids:
		var key := str(id)
		if not _states.has(key):
			continue
		# hidden は返さない（実サーバと同じ）。
		if bool(_states[key]["hidden"]):
			continue
		out.append(_wire(key))
	return out


## 実サーバの相手探しと同じく、自分と伏せた状態を除いてランダムに引く。範囲を渡したときは、
## rating の無い状態を返さない。
static func sample(params: Dictionary, self_id: String) -> Dictionary:
	_ensure_rivals()
	var count := SAMPLE_DEFAULT_COUNT
	var raw_count: Variant = params.get("count")
	if raw_count != null:
		if not _is_integer(raw_count) or int(raw_count) < 1 or int(raw_count) > SAMPLE_MAX_COUNT:
			return _invalid("count must be an integer from 1 to %d." % SAMPLE_MAX_COUNT)
		count = int(raw_count)
	var min_rating: Variant = params.get("minRating")
	var max_rating: Variant = params.get("maxRating")
	var ranged: bool = min_rating != null
	if ranged != (max_rating != null):
		return _invalid("minRating and maxRating must be given together.")
	if ranged:
		if not is_rating(min_rating) or not is_rating(max_rating):
			return _invalid("Invalid rating range.")
		if float(min_rating) > float(max_rating):
			return _invalid("minRating must not exceed maxRating.")
	var candidates: Array = []
	for key in _states:
		var entry: Dictionary = _states[key]
		if bool(entry["hidden"]) or key == self_id:
			continue
		if ranged:
			var rating: Variant = entry["rating"]
			if rating == null or float(rating) < float(min_rating) or float(rating) > float(max_rating):
				continue
		candidates.append(key)
	candidates.shuffle()
	var states: Array = []
	for key in candidates.slice(0, count):
		states.append(_wire(key))
	return Result.ok({"states": states})


static func _ensure_rivals() -> void:
	if _seeded:
		return
	_seeded = true
	for index in range(GRushMock.RIVALS.size()):
		_put(GRushMock.RIVALS[index], {"level": (index + 1) * 5}, false, RIVAL_RATINGS[index])


static func _put(pseudo_id: String, payload: Dictionary, hidden: bool, rating: Variant) -> void:
	_states[pseudo_id] = {
		"payload": payload,
		"hidden": hidden,
		"revision": 1,
		"rating": float(rating) if is_rating(rating) else null,
	}


static func _wire(key: String) -> Dictionary:
	var entry: Dictionary = _states[key]
	return {
		"pseudoId": key,
		"payload": entry["payload"],
		"revision": int(entry["revision"]),
		"rating": entry["rating"],
		"updatedAt": "",
	}


static func _is_finite_number(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value))


static func _is_integer(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floor(value))


static func _invalid(message: String) -> Dictionary:
	return Result.failure(Result.CODE_INVALID_PARAMS, message)
