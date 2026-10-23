extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const MockPeer := preload("res://addons/grush_sdk/grush_mock_peer.gd")

const STATE_PATH := GRushMock.STATE_PATH
const STATE_SECTION := GRushMock.STATE_SECTION
# モックが実装している一番新しい機能（公開プレイヤー状態の確認用の表示）の版数。
const MOCK_PROTOCOL_VERSION := 10

var _members: Array = []
var _outgoing_seq: Dictionary = {}
var _local_index := -1
var _consented := false
var _room_code := ""
var _net_handler := Callable()
var _random := RandomNumberGenerator.new()


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
	var peer := MockPeer.new(self)
	peer.index = _next_free_index()
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
	match method:
		"player.getSelf":
			return Result.ok(_player_wire(_consented))
		"player.requestProfile":
			return _request_profile()
		"player.revokeProfile":
			_set_consent(false)
			return Result.ok(_player_wire(false))
		"net.join":
			return Result.ok(_join(params))
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


func _submit_score(params: Dictionary) -> Dictionary:
	var key := str(params.get("key", ""))
	if key == "":
		return Result.failure(Result.CODE_INVALID_PARAMS, "A leaderboard key is required.")
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


func _join(params: Dictionary) -> Dictionary:
	if _room_code == "":
		_room_code = str(params.get("roomCode", "MOCKROOM"))
	var existing: Array = []
	for entry in _members:
		existing.append(_peer_wire(int(entry["index"])))
	_local_index = _next_free_index()
	_members.append({"index": _local_index, "peer": null})
	_members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["index"] < b["index"])
	_announce("peerjoin", _local_index, _peer_wire(_local_index))
	return {
		"roomId": "mock:%s:%s" % [str(params.get("mode", "default")), _room_code],
		"roomCode": _room_code,
		"localPeerIndex": _local_index,
		"peers": existing,
		"hostIndex": _host_index(),
		"epoch": 1,
		"transport": "ws",
		"serverTimeMs": Time.get_unix_time_from_system() * 1000.0,
	}


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
	return GRushMock.max_peers - 1


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
