extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const MockPeer := preload("res://addons/grush_sdk/grush_mock_peer.gd")
const JsonDepth := preload("res://addons/grush_sdk/grush_json_depth.gd")
const JsText := preload("res://addons/grush_sdk/grush_js_text.gd")

const STATE_PATH := GRushMock.STATE_PATH
const STATE_SECTION := GRushMock.STATE_SECTION
# モックが実装している一番新しい機能（公開プレイヤー状態の確認用の表示）の版数。
const MOCK_PROTOCOL_VERSION := 10
# GameRush と同じ mode と部屋コードの形。`$` は末尾の改行の前でも合うので `\z` で終える。
const MODE_PATTERN := "^[A-Za-z0-9._:-]{1,32}\\z"
const ROOM_CODE_PATTERN := "^[A-Za-z0-9]{4,12}\\z"

var _members: Array = []
var _outgoing_seq: Dictionary = {}
var _local_index := -1
var _consented := false
var _room_code := ""
var _net_handler := Callable()
var _random := RandomNumberGenerator.new()
var _mode_pattern := RegEx.create_from_string(MODE_PATTERN)
var _room_code_pattern := RegEx.create_from_string(ROOM_CODE_PATTERN)


func _init() -> void:
	_random.seed = 20260816
	_consented = bool(_state().get_value(STATE_SECTION, "consent", false))


func is_available() -> bool:
	return true


func protocol_version() -> int:
	return MOCK_PROTOCOL_VERSION


func set_net_event_handler(handler: Callable) -> void:
	_net_handler = handler


func call_api(method: String, params: Dictionary, on_done: Callable) -> void:
	on_done.call_deferred(_handle(method, params))


func send(payload: PackedByteArray, channel: String, to: int) -> void:
	if _local_index < 0:
		return
	route(_local_index, payload, channel, to)


func add_peer(display_name: String, avatar_url: Variant = null) -> RefCounted:
	var index := _next_free_index()
	if index < 0:
		return null
	var peer := MockPeer.new(self)
	peer.index = index
	peer.pseudo_id = "mock-peer-%d" % peer.index
	peer.display_name = display_name
	peer.avatar_url = avatar_url
	_members.append({"index": peer.index, "peer": peer})
	_members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["index"] < b["index"])
	_announce("peerjoin", peer.index, _peer_wire(peer.index))
	return peer


func remove_peer(peer: RefCounted) -> void:
	if peer == null:
		return
	_members = _members.filter(func(entry: Dictionary) -> bool: return entry.get("peer") != peer)
	_outgoing_seq.erase(peer.index)
	_announce("peerleave", peer.index, {})


func raise_room_error(code: String, message: String) -> bool:
	if _local_index < 0:
		return false
	_deliver_local.call_deferred({"kind": "error", "code": code, "message": message})
	return true


func route(from: int, payload: PackedByteArray, channel: String, to: int) -> void:
	if channel == "unreliable" and _random.randf() < GRushMock.unreliable_drop_rate:
		return
	var seq := int(_outgoing_seq.get(from, 0)) + 1
	_outgoing_seq[from] = seq
	for entry in _members.duplicate():
		var index := int(entry["index"])
		if index == from or (to != -1 and index != to):
			continue
		var message := {
			"kind": "message",
			"from": from,
			"channel": channel,
			"seq": seq,
			"payload": payload.duplicate(),
		}
		var peer: Variant = entry.get("peer")
		if peer != null:
			peer.deliver.call_deferred(message)
		else:
			_deliver_local.call_deferred(message)


func _handle(method: String, params: Dictionary) -> Dictionary:
	# Web 書き出しの SDK と同じく、Godot が JSON に書き出せない深さの値は送る前に断る（grush_json_depth.gd）。
	if not JsonDepth.params_writable(method, params):
		return Result.failure(Result.CODE_INVALID_PARAMS, JsonDepth.unwritable_message(method))
	# Web 書き出しの SDK と同じく、文字列の対になっていないサロゲートを U+FFFD に替えてから扱う（grush_js_text.gd）。
	# そのため GameRush の「対になっていないサロゲートを含む」誤りは Godot からは届かず、モックも確かめない。
	# GameRush の値の数と段数の誤りも、Godot が JSON に書き出せる範囲（grush_json_depth.gd）を上で先に確かめる
	# ので届かない（値の数の上限は GameRush と同じで、段数の上限は GameRush より浅い）。
	params = JsText.sanitized(params)
	match method:
		"player.getSelf":
			return Result.ok(_player_wire(_consented))
		"player.requestProfile":
			return _request_profile()
		"player.revokeProfile":
			_set_consent(false)
			return Result.ok(_player_wire(false))
		"net.join":
			return _join(params)
		"net.leave":
			_leave()
			return Result.ok(null)
		"leaderboard.list":
			return Result.ok(GRushMockLeaderboards.list_wire())
		"leaderboard.submit":
			return _submit_score(params)
		"leaderboard.top":
			return _leaderboard_page(params, false)
		"leaderboard.aroundMe":
			return _leaderboard_page(params, true)
		"leaderboard.friends":
			return Result.failure(
				Result.CODE_CONSENT_DECLINED,
				"Friend leaderboards require per-game friend consent."
			)
		"playerState.getMine":
			return Result.ok({"state": _mock_player_state})
		"playerState.setMine":
			return _set_player_state(params)
		"playerState.get":
			return Result.ok({"states": GRushMockPlayerStates.get_many(params.get("pseudoIds", []))})
		"playerState.report":
			return GRushMockPlayerStates.handle_report(params)
		"playerState.sample":
			return GRushMockPlayerStates.sample(params, _local_pseudo_id())
		"inbox.send":
			return GRushMockInbox.handle_send(params, _local_pseudo_id())
		"inbox.list":
			return GRushMockInbox.handle_list(params)
		"inbox.markRead":
			return GRushMockInbox.handle_mark_read(params)
		"inbox.remove":
			return GRushMockInbox.handle_remove(params)
		"inbox.report":
			return GRushMockInbox.handle_report(params)
		"trade.create":
			return GRushMockTrades.handle_create(params, _local_pseudo_id())
		"trade.list":
			return GRushMockTrades.handle_list(params, _local_pseudo_id())
		"trade.mine":
			return GRushMockTrades.handle_mine(_local_pseudo_id())
		"trade.accept":
			return GRushMockTrades.handle_accept(params, _local_pseudo_id())
		"trade.cancel":
			return GRushMockTrades.handle_cancel(params, _local_pseudo_id())
		"trade.ack":
			return GRushMockTrades.handle_ack(params, _local_pseudo_id())
		"trade.report":
			return GRushMockTrades.handle_report(params, _local_pseudo_id())
	return Result.failure(
		Result.CODE_UNSUPPORTED, "The mock backend does not implement %s." % method
	)


var _mock_player_state: Variant = null


func _set_player_state(params: Dictionary) -> Dictionary:
	var payload: Variant = params.get("payload", null)
	if not (payload is Dictionary):
		return Result.failure(
			Result.CODE_INVALID_PARAMS, "Player state payload must be a JSON object."
		)
	# サーバと同じく、文字数ではなく UTF-8 のバイト数で数える。
	if JSON.stringify(payload).to_utf8_buffer().size() > 4096:
		return Result.failure(Result.CODE_INVALID_PARAMS, "Player state payload is too large.")
	# rating の項目が無ければ今の値のまま、null なら消す。
	var rating: Variant = _mock_player_state.get("rating") if _mock_player_state is Dictionary else null
	if params.has("rating"):
		rating = params["rating"]
		if rating != null and not GRushMockPlayerStates.is_rating(rating):
			return Result.failure(Result.CODE_INVALID_PARAMS, "Invalid rating.")
	var revision := 1
	if _mock_player_state is Dictionary:
		revision = int(_mock_player_state["revision"]) + 1
	_mock_player_state = {
		"pseudoId": _local_pseudo_id(),
		"payload": payload,
		"revision": revision,
		"rating": null if rating == null else float(rating),
		"updatedAt": "",
	}
	return Result.ok({"state": _mock_player_state})


# 投稿を受ける枠（宣言してあり、止めていない）の定義。無ければ null。list の結果は、投稿を受ける枠だけを並べる。
static func _playable_definition(key: String) -> Variant:
	for board in GRushMockLeaderboards.list_wire()["leaderboards"]:
		if board["key"] == key:
			return board
	return null


# GameRush と同じく、値が有限の数か、int と duration_ms の枠では整数か、duration_ms の枠では負でないかを
# 確かめる。断るなら文言、通すなら空文字を返す。
static func _score_error(value: Variant, value_type: String) -> String:
	if not (value is int or value is float) or not is_finite(float(value)):
		return "Score must be a finite number."
	var number := float(value)
	if value_type != "float" and number != floor(number):
		return "Score must be an integer for this leaderboard."
	if value_type == "duration_ms" and number < 0:
		return "Duration must not be negative."
	return ""


func _submit_score(params: Dictionary) -> Dictionary:
	var key := str(params.get("key", ""))
	if key == "":
		return Result.failure(Result.CODE_INVALID_PARAMS, "A leaderboard key is required.")
	# GameRush と同じく、枠を確かめた後に値を確かめ、値域はその後に確かめる。投稿を受けない枠は、submit が
	# GameRush と同じく先に断る。metadata と operationId の GameRush の誤り（値の数・段数・対になっていない
	# サロゲート）は、_handle の説明のとおり Godot からは届かない。
	var definition: Variant = _playable_definition(key)
	if definition != null:
		var score_error := _score_error(params.get("value", 0.0), str(definition["valueType"]))
		if score_error != "":
			return Result.failure(Result.CODE_INVALID_PARAMS, score_error)
	var outcome := GRushMockLeaderboards.submit(
		key, float(params.get("value", 0.0)), params.get("metadata", null), _local_pseudo_id()
	)
	if outcome.has("error"):
		return Result.failure(Result.CODE_INVALID_PARAMS, str(outcome["message"]))
	return Result.ok(outcome)


func _leaderboard_page(params: Dictionary, around_me: bool) -> Dictionary:
	var key := str(params.get("key", ""))
	if key == "":
		return Result.failure(Result.CODE_INVALID_PARAMS, "A leaderboard key is required.")
	var window := int(params.get("range", 0)) if around_me else int(params.get("limit", 0))
	var outcome := GRushMockLeaderboards.page(
		key, window, int(params.get("offset", 0)), around_me
	)
	if outcome.has("error"):
		return Result.failure(Result.CODE_INVALID_PARAMS, str(outcome["message"]))
	return Result.ok(outcome)


func _request_profile() -> Dictionary:
	if not GRushMock.signed_in:
		return Result.failure(
			Result.CODE_SIGN_IN_REQUIRED, "The player is a guest and has no profile."
		)
	if not GRushMock.grant_profile_consent:
		return Result.failure(
			Result.CODE_CONSENT_DECLINED, "The player declined to share their profile."
		)
	_set_consent(true)
	return Result.ok(_player_wire(true))


func _set_consent(value: bool) -> void:
	_consented = value
	var config := _state()
	config.set_value(STATE_SECTION, "consent", value)
	config.save(STATE_PATH)


# GameRush と同じく、今の部屋を先に抜け、失敗しても戻らない。形の誤りはゲームが直すので invalidParams、
# 埋まった部屋は待てば入れるので unavailable で返す。
func _join(params: Dictionary) -> Dictionary:
	_leave()
	var mode: Variant = params.get("mode", "default")
	if not (mode is String) or _mode_pattern.search(mode) == null:
		return Result.failure(Result.CODE_INVALID_PARAMS, "Invalid mode.")
	var requested: Variant = params.get("roomCode")
	if requested != null and (not (requested is String) or _room_code_pattern.search(requested) == null):
		return Result.failure(Result.CODE_INVALID_PARAMS, "Invalid room code.")
	var index := _next_free_index()
	if index < 0:
		return Result.failure(Result.CODE_UNAVAILABLE, "The mock room is full.")
	if requested != null:
		_room_code = str(requested).to_upper()
	elif _room_code == "":
		_room_code = "MOCKROOM"
	var existing: Array = []
	for entry in _members:
		existing.append(_peer_wire(int(entry["index"])))
	_local_index = index
	_members.append({"index": _local_index, "peer": null})
	_members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["index"] < b["index"])
	_announce("peerjoin", _local_index, _peer_wire(_local_index))
	return Result.ok({
		"roomId": "mock:%s:%s" % [mode, _room_code],
		"roomCode": _room_code,
		"localPeerIndex": _local_index,
		"peers": existing,
		"hostIndex": _host_index(),
		"epoch": 1,
		"transport": "ws",
		"serverTimeMs": Time.get_unix_time_from_system() * 1000.0,
	})


func _leave() -> void:
	if _local_index < 0:
		return
	var leaving := _local_index
	_members = _members.filter(func(entry: Dictionary) -> bool: return entry["index"] != leaving)
	_outgoing_seq.erase(leaving)
	_local_index = -1
	_announce("peerleave", leaving, {})


func _announce(kind: String, subject: int, peer: Dictionary) -> void:
	for entry in _members.duplicate():
		if entry.get("peer") != null or int(entry["index"]) == subject:
			continue
		var event := {"kind": kind}
		if kind == "peerjoin":
			event["peer"] = peer
		else:
			event["index"] = subject
		_deliver_local.call_deferred(event)


func _deliver_local(event: Dictionary) -> void:
	if _net_handler.is_valid():
		_net_handler.call(event)


func _next_free_index() -> int:
	for index in range(GRushMock.max_peers):
		var taken := _members.filter(
			func(entry: Dictionary) -> bool: return int(entry["index"]) == index
		)
		if taken.is_empty():
			return index
	return -1


func _host_index() -> int:
	var host := GRushMock.max_peers
	for entry in _members:
		host = min(host, int(entry["index"]))
	return 0 if host == GRushMock.max_peers else host


func _peer_wire(index: int) -> Dictionary:
	for entry in _members:
		if int(entry["index"]) != index:
			continue
		var peer: Variant = entry.get("peer")
		if peer != null:
			return {
				"index": index,
				"pseudoId": peer.pseudo_id,
				"displayName": peer.display_name,
				"avatarUrl": peer.avatar_url,
			}
		return {
			"index": index,
			"pseudoId": _local_pseudo_id(),
			"displayName": GRushMock.display_name if _consented else null,
			"avatarUrl": GRushMock.avatar_url if _consented else null,
		}
	return {"index": index, "pseudoId": "", "displayName": null, "avatarUrl": null}


func _player_wire(consented: bool) -> Dictionary:
	return {
		"pseudoId": _local_pseudo_id(),
		"isGuest": not GRushMock.signed_in,
		"profileConsent": consented and GRushMock.signed_in,
		"profile": {"displayName": GRushMock.display_name, "avatarUrl": GRushMock.avatar_url},
	}


static func _state() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(STATE_PATH)
	return config


static func _local_pseudo_id() -> String:
	return GRushMock.local_pseudo_id()
