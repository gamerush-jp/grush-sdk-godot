extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const JsonDepth := preload("res://addons/grush_sdk/grush_json_depth.gd")
const JsText := preload("res://addons/grush_sdk/grush_js_text.gd")

var _room: JavaScriptObject = null
var _room_callbacks: Array = []
# JavaScriptBridge.create_callback の戻りは、参照を持たないと回収される。
# 部屋のリスナは部屋が生きている間抱え、差し替えでは1世代ぶん遅れて解放する。
# JS のコールバックの実行中に、そのコールバック自身を解放しないため。
var _retired_callbacks: Array = []
var _pending: Dictionary = {}
var _next_token := 1
var _net_handler := Callable()


static func is_present() -> bool:
	if not OS.has_feature("web"):
		return false
	return (
		JavaScriptBridge.get_interface("GRushInfo") != null
		and JavaScriptBridge.get_interface("GRushNet") != null
		and JavaScriptBridge.get_interface("GRushPlayer") != null
	)


func is_available() -> bool:
	return is_present()


func protocol_version() -> int:
	var info := JavaScriptBridge.get_interface("GRushInfo")
	if info == null:
		return 0
	var version: Variant = info.protocolVersion
	return int(version) if version != null else 0


func set_net_event_handler(handler: Callable) -> void:
	_net_handler = handler


func call_api(method: String, params: Dictionary, on_done: Callable) -> void:
	if method == "net.leave" and _room == null:
		on_done.call_deferred(Result.ok(null))
		return
	# Godot の JSON.stringify が書き出せない値は、壊れた JSON を渡さずに断る（grush_json_depth.gd）。
	# 検証は GameRush の側に置くのが原則だが、これは SDK で確かめる。壊れた JSON はこの SDK の中で生じ、
	# GameRush には壊れた後の文字列しか届かず、元の値が見えないため。
	if not JsonDepth.params_writable(method, params):
		on_done.call_deferred(
			Result.failure(Result.CODE_INVALID_PARAMS, JsonDepth.UNWRITABLE_MESSAGE)
		)
		return
	# 文字列の対になっていないサロゲートは、JavaScript へ渡す前に U+FFFD に替える（grush_js_text.gd）。
	var promise: Variant = _invoke(method, JsText.sanitized(params))
	if promise == null:
		on_done.call_deferred(
			Result.failure(Result.CODE_UNSUPPORTED, "GameRush does not expose %s here." % method)
		)
		return
	var token := _next_token
	_next_token += 1
	var on_ok := JavaScriptBridge.create_callback(
		func(args: Array) -> void: _settle(token, method, on_done, true, args)
	)
	var on_error := JavaScriptBridge.create_callback(
		func(args: Array) -> void: _settle(token, method, on_done, false, args)
	)
	_pending[token] = [on_ok, on_error]
	promise.then(on_ok, on_error)


func send(payload: PackedByteArray, channel: String, to: int) -> void:
	if _room == null:
		return
	var options := JavaScriptBridge.create_object("Object")
	options.channel = channel
	options.to = to
	_room.sendBase64(Marshalls.raw_to_base64(payload), options)


func _invoke(method: String, params: Dictionary) -> Variant:
	var player := JavaScriptBridge.get_interface("GRushPlayer")
	var net := JavaScriptBridge.get_interface("GRushNet")
	var boards := JavaScriptBridge.get_interface("GRushLeaderboards")
	var states := JavaScriptBridge.get_interface("GRushPlayerState")
	var inbox := JavaScriptBridge.get_interface("GRushInbox")
	var trade := JavaScriptBridge.get_interface("GRushTrade")
	match method:
		"player.getSelf":
			return player.getSelf() if player != null else null
		"player.requestProfile":
			return player.requestProfile() if player != null else null
		"player.revokeProfile":
			return player.revokeProfile() if player != null else null
		"net.join":
			if net == null:
				return null
			return net.join(_to_js(params))
		"net.leave":
			var leaving := _room
			_release_room()
			return leaving.leave() if leaving != null else null
		"leaderboard.list":
			return boards.list() if boards != null else null
		"leaderboard.submit":
			if boards == null:
				return null
			return boards.submit(
				params.get("key", ""),
				params.get("value", 0.0),
				_js_value(params.get("metadata")),
				params.get("operationId")
			)
		"leaderboard.top":
			return boards.top(params.get("key", ""), _js_value(params)) if boards != null else null
		"leaderboard.aroundMe":
			if boards == null:
				return null
			return boards.aroundMe(params.get("key", ""), _js_value(params))
		"leaderboard.friends":
			if boards == null:
				return null
			return boards.friends(params.get("key", ""), _js_value(params))
		"playerState.getMine":
			return states.getMine() if states != null else null
		"playerState.setMine":
			if states == null:
				return null
			# rating は、それを読めるランタイムのときだけ params にある（grush_player_state_api.gd）。
			if params.has("rating"):
				return states.setMine(
					_js_value(params.get("payload", {})),
					params.get("baseRevision"),
					_js_value({"rating": params["rating"]})
				)
			return states.setMine(
				_js_value(params.get("payload", {})), params.get("baseRevision")
			)
		"playerState.get":
			var shim := _shim()
			if states == null or shim == null:
				return null
			return shim.playerStateGet(_js_value(params.get("pseudoIds", [])))
		"playerState.report":
			return states.report(params.get("pseudoId", "")) if states != null else null
		"playerState.sample":
			return states.sample(_js_value(params)) if states != null else null
		"inbox.send":
			if inbox == null:
				return null
			return inbox.send(
				params.get("to", ""), params.get("kind", ""), _js_value(params.get("payload", {}))
			)
		"inbox.list":
			return inbox.list(_js_value(params)) if inbox != null else null
		"inbox.markRead":
			return inbox.markRead(_js_value(params.get("ids", []))) if inbox != null else null
		"inbox.remove":
			return inbox.remove(_js_value(params.get("ids", []))) if inbox != null else null
		"inbox.report":
			return inbox.report(params.get("messageId", "")) if inbox != null else null
		"trade.create":
			return trade.create(_js_value(params)) if trade != null else null
		"trade.list":
			return trade.list(_js_value(params)) if trade != null else null
		"trade.mine":
			return trade.mine() if trade != null else null
		"trade.accept":
			if trade == null:
				return null
			return trade.accept(params.get("tradeId", ""), _js_value(params.get("give", {})))
		"trade.cancel":
			return trade.cancel(params.get("tradeId", "")) if trade != null else null
		"trade.ack":
			return trade.ack(_js_value(params.get("ids", []))) if trade != null else null
		"trade.report":
			return trade.report(params.get("tradeId", "")) if trade != null else null
	return null


const SHIM_JS := """
(function () {
  if (window.__grushSdkShim) return;
  window.__grushSdkShim = {
    playerStateGet: function (ids) {
      return window.GRushPlayerState ? window.GRushPlayerState.get(ids) : null;
    }
  };
})();
"""


static var _shim_installed := false


static func _shim() -> JavaScriptObject:
	if not _shim_installed:
		JavaScriptBridge.eval(SHIM_JS, true)
		_shim_installed = true
	return JavaScriptBridge.get_interface("__grushSdkShim")


static func _js_value(value: Variant) -> Variant:
	if value == null:
		return null
	var js_json := JavaScriptBridge.get_interface("JSON")
	if js_json == null:
		return null
	return js_json.parse(JSON.stringify(value))


static func _gd_value(value: Variant) -> Variant:
	if value == null:
		return null
	var js_json := JavaScriptBridge.get_interface("JSON")
	if js_json == null:
		return null
	var text: Variant = js_json.stringify(value)
	return null if text == null else JSON.parse_string(str(text))


func _settle(token: int, method: String, on_done: Callable, ok: bool, args: Array) -> void:
	_forget_pending.call_deferred(token)
	var value: Variant = args[0] if args.size() > 0 else null
	if not ok:
		on_done.call(Result.failure(_code_of(value), _message_of(value)))
		return
	on_done.call(Result.ok(_value_of(method, value)))


func _value_of(method: String, value: Variant) -> Variant:
	if method == "net.join":
		return _bind_room(value)
	if method.begins_with("player."):
		return _player_of(value)
	match method:
		"leaderboard.list":
			var boards: Variant = _gd_value(value)
			return {"leaderboards": boards if boards is Array else []}
		"leaderboard.submit":
			return {"result": _gd_value(value)}
		"leaderboard.top", "leaderboard.aroundMe", "leaderboard.friends":
			return {"leaderboard": _gd_value(value)}
		"playerState.getMine", "playerState.setMine":
			return {"state": _gd_value(value)}
		"playerState.get":
			var states: Variant = _gd_value(value)
			return {"states": states if states is Array else []}
		"playerState.report":
			return {"reported": bool(value) if value != null else false}
		"playerState.sample":
			return _envelope(_gd_value(value), "states")
		"inbox.send":
			return _envelope(_gd_value(value), "sent")
		"inbox.markRead", "inbox.remove":
			return _envelope(_gd_value(value), "updated")
		"inbox.report", "trade.report":
			return _envelope(_gd_value(value), "reported")
		"trade.create", "trade.cancel":
			return _envelope(_gd_value(value), "trade")
		"trade.ack":
			return _envelope(_gd_value(value), "acked")
		"inbox.list", "trade.list", "trade.mine", "trade.accept":
			return _gd_value(value)
	return null


# ランタイムは包んだ RPC の結果（{"states": …}）も、中身だけも返しうる。どちらも包んだ形にそろえる。
static func _envelope(value: Variant, key: String) -> Dictionary:
	if value is Dictionary and value.has(key):
		return value
	return {key: value}


func _bind_room(room: Variant) -> Variant:
	_release_room()
	if room == null:
		return null
	_room = room
	_listen("message", func(args: Array) -> void: _emit(_message_of_js(args)))
	_listen(
		"peerjoin",
		func(args: Array) -> void: _emit({"kind": "peerjoin", "peer": _peer_of(args[0])})
	)
	_listen(
		"peerleave",
		func(args: Array) -> void: _emit({"kind": "peerleave", "index": int(args[0]["index"])})
	)
	_listen("host", func(args: Array) -> void: _emit({"kind": "host", "index": int(args[0]["index"])}))
	_listen(
		"transportchange",
		func(args: Array) -> void: _emit(
			{"kind": "transportchange", "transport": str(args[0]["transport"])}
		)
	)
	_listen("error", func(args: Array) -> void: _on_error(args))
	_listen("close", func(args: Array) -> void: _on_close(args))
	return JSON.parse_string(str(_room.describeJson()))


func _listen(event_name: String, handler: Callable) -> void:
	var callback := JavaScriptBridge.create_callback(handler)
	_room_callbacks.append(callback)
	_room.on(event_name, callback)


func _on_error(args: Array) -> void:
	var code := ""
	var message := ""
	if args.size() > 0 and args[0] != null:
		if args[0]["code"] != null:
			code = str(args[0]["code"])
		if args[0]["message"] != null:
			message = str(args[0]["message"])
	_emit({"kind": "error", "code": code, "message": message})


func _on_close(args: Array) -> void:
	var reason := ""
	if args.size() > 0 and args[0] != null and args[0]["reason"] != null:
		reason = str(args[0]["reason"])
	_emit({"kind": "close", "reason": reason})
	_release_room()


func _forget_pending(token: int) -> void:
	_pending.erase(token)


func _release_room() -> void:
	_room = null
	_retired_callbacks = _room_callbacks
	_room_callbacks = []


func _emit(event: Dictionary) -> void:
	if _net_handler.is_valid():
		_net_handler.call(event)


func _message_of_js(args: Array) -> Dictionary:
	var message: Variant = args[0]
	var payload := PackedByteArray()
	var raw: Variant = message["payload"]
	if raw != null and JavaScriptBridge.is_js_buffer(raw):
		payload = JavaScriptBridge.js_buffer_to_packed_byte_array(raw)
	return {
		"kind": "message",
		"from": int(message["from"]),
		"channel": str(message["channel"]),
		"seq": int(message["seq"]),
		"payload": payload,
	}


static func _peer_of(peer: Variant) -> Dictionary:
	if peer == null:
		return {}
	var display_name: Variant = peer["displayName"]
	var avatar_url: Variant = peer["avatarUrl"]
	return {
		"index": int(peer["index"]),
		"pseudoId": str(peer["pseudoId"]),
		"displayName": null if display_name == null else str(display_name),
		"avatarUrl": null if avatar_url == null else str(avatar_url),
	}


static func _player_of(player: Variant) -> Dictionary:
	if player == null:
		return {}
	var profile: Variant = player["profile"]
	var normalized := {
		"pseudoId": str(player["pseudoId"]),
		"isGuest": bool(player["isGuest"]),
		"profileConsent": bool(player["profileConsent"]),
	}
	if profile != null:
		normalized["profile"] = {
			"displayName": profile["displayName"],
			"avatarUrl": profile["avatarUrl"],
		}
	return normalized


static func _code_of(error: Variant) -> String:
	if error == null or error["code"] == null:
		return Result.CODE_INTERNAL
	return Result.map_code(str(error["code"]))


static func _message_of(error: Variant) -> String:
	if error == null or error["message"] == null:
		return "GameRush API call failed."
	return str(error["message"])


static func _to_js(params: Dictionary) -> JavaScriptObject:
	var object := JavaScriptBridge.create_object("Object")
	object.mode = params.get("mode", "default")
	if params.has("roomCode"):
		object.roomCode = params["roomCode"]
	return object
