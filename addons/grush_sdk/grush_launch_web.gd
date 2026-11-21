extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")

var _pending: Dictionary = {}
var _next_token := 1

# GDScript から JavaScriptObject の get() を呼ぶと Object.get になるので、Promise を返す get() は shim から呼ぶ。
const SHIM_JS := """
(function () {
  if (window.__grushLaunchShim) return;
  function api() {
    return window.GRushLaunch || window.GameRushLaunch;
  }
  window.__grushLaunchShim = {
    fetch: function () {
      var launch = api();
      return launch ? launch.get() : null;
    }
  };
})();
"""

static var _shim_installed := false


static func _api() -> JavaScriptObject:
	var api := JavaScriptBridge.get_interface("GRushLaunch")
	if api == null:
		api = JavaScriptBridge.get_interface("GameRushLaunch")
	return api


static func snapshot_of(value: Variant) -> Variant:
	var json := JavaScriptBridge.get_interface("JSON")
	if value == null or json == null:
		return null
	var parsed: Variant = JSON.parse_string(str(json.stringify(value)))
	if not (parsed is Dictionary) or not (parsed.get("params") is Dictionary):
		return null
	var params := {}
	var raw: Dictionary = parsed["params"]
	for key in raw:
		if raw[key] is String:
			params[str(key)] = raw[key]
	return {"params": params, "invite": invite_of(parsed.get("invite"))}


# 招待から開いたときの部屋。版数 13 未満のランタイムは送らないので null になる。
static func invite_of(value: Variant) -> Variant:
	if not (value is Dictionary):
		return null
	var mode: Variant = value.get("mode")
	var room_code: Variant = value.get("roomCode")
	if not (mode is String) or mode == "" or not (room_code is String) or room_code == "":
		return null
	return {"mode": mode, "room_code": room_code}


static func _shim() -> JavaScriptObject:
	if not _shim_installed:
		JavaScriptBridge.eval(SHIM_JS, true)
		_shim_installed = true
	return JavaScriptBridge.get_interface("__grushLaunchShim")


func current() -> Variant:
	var api := _api()
	if api == null:
		return null
	return snapshot_of(api.current())


func fetch(on_done: Callable) -> void:
	var api := _api()
	var promise: Variant = _shim().fetch() if api != null else null
	if promise == null:
		on_done.call_deferred(Result.unsupported())
		return
	var token := _next_token
	_next_token += 1
	var on_ok := JavaScriptBridge.create_callback(
		func(args: Array) -> void: _settle(token, on_done, true, args)
	)
	var on_error := JavaScriptBridge.create_callback(
		func(args: Array) -> void: _settle(token, on_done, false, args)
	)
	_pending[token] = [on_ok, on_error]
	promise.then(on_ok, on_error)


func _settle(token: int, on_done: Callable, ok: bool, args: Array) -> void:
	_forget_pending.call_deferred(token)
	var value: Variant = args[0] if args.size() > 0 else null
	if not ok:
		on_done.call(Result.failure(_code_of(value), _message_of(value)))
		return
	var info: Variant = snapshot_of(value)
	if info == null:
		on_done.call(
			Result.failure(Result.CODE_INTERNAL, "GameRush returned unreadable launch parameters.")
		)
		return
	on_done.call(Result.ok(info))


func _forget_pending(token: int) -> void:
	_pending.erase(token)


static func _code_of(error: Variant) -> String:
	if error == null or error["code"] == null:
		return Result.CODE_INTERNAL
	return Result.map_code(str(error["code"]))


static func _message_of(error: Variant) -> String:
	if error == null or error["message"] == null:
		return "GameRush API call failed."
	return str(error["message"])
