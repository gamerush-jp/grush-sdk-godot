extends RefCounted

var _watch_callback: JavaScriptObject = null
var _watch_id := 0

# onPreview の戻り値（登録を外す関数）を JavaScript の側で持つ。
const SHIM_JS := """
(function () {
  if (window.__grushPlayerStatePreviewShim) return;
  var subscriptions = {};
  var nextId = 1;
  window.__grushPlayerStatePreviewShim = {
    watch: function (handler) {
      var api = window.GRushPlayerState;
      if (!api || typeof api.onPreview !== "function") return 0;
      var id = nextId++;
      subscriptions[id] = api.onPreview(handler);
      return id;
    },
    unwatch: function (id) {
      var off = subscriptions[id];
      delete subscriptions[id];
      if (typeof off === "function") off();
    }
  };
})();
"""

static var _shim_installed := false


static func _shim() -> JavaScriptObject:
	if not _shim_installed:
		JavaScriptBridge.eval(SHIM_JS, true)
		_shim_installed = true
	return JavaScriptBridge.get_interface("__grushPlayerStatePreviewShim")


## handler には、ランタイムが渡した状態を JSON から読んだ Dictionary（キーはランタイムのまま）が渡る。
func watch(handler: Callable) -> void:
	if _watch_callback != null or JavaScriptBridge.get_interface("GRushPlayerState") == null:
		return
	_watch_callback = JavaScriptBridge.create_callback(
		func(args: Array) -> void: _on_watch(handler, args)
	)
	_watch_id = int(_shim().watch(_watch_callback))


func dispose() -> void:
	if _watch_id != 0:
		_shim().unwatch(_watch_id)
		_watch_id = 0
	_watch_callback = null


func _on_watch(handler: Callable, args: Array) -> void:
	var json := JavaScriptBridge.get_interface("JSON")
	if args.is_empty() or args[0] == null or json == null:
		return
	var parsed: Variant = JSON.parse_string(str(json.stringify(args[0])))
	if parsed is Dictionary:
		handler.call(parsed)
