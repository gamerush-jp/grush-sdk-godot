extends RefCounted

## アイテム販売の付与の合図（`grush:shop:pending`）を、ランタイムの `GRushShop.onPending` から受ける。

var _watch_callback: JavaScriptObject = null
var _watch_id := 0

# onPending の戻り値（登録を外す関数）を JavaScript の側で持つ。
const SHIM_JS := """
(function () {
  if (window.__grushShopShim) return;
  var subscriptions = {};
  var nextId = 1;
  window.__grushShopShim = {
    watch: function (handler) {
      var api = window.GRushShop || window.GameRushShop;
      if (!api || typeof api.onPending !== "function") return 0;
      var id = nextId++;
      subscriptions[id] = api.onPending(handler);
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


static func api() -> JavaScriptObject:
	var shop := JavaScriptBridge.get_interface("GRushShop")
	if shop == null:
		shop = JavaScriptBridge.get_interface("GameRushShop")
	return shop


static func _shim() -> JavaScriptObject:
	if not _shim_installed:
		JavaScriptBridge.eval(SHIM_JS, true)
		_shim_installed = true
	return JavaScriptBridge.get_interface("__grushShopShim")


## handler には付与された商品の sku（String）が渡る。
func watch(handler: Callable) -> void:
	if _watch_callback != null or api() == null:
		return
	_watch_callback = JavaScriptBridge.create_callback(
		func(args: Array) -> void: _on_watch(handler, args)
	)
	_watch_id = int(_shim().watch(_watch_callback))


func unwatch() -> void:
	if _watch_id != 0:
		_shim().unwatch(_watch_id)
		_watch_id = 0
	_watch_callback = null


func dispose() -> void:
	unwatch()


func _on_watch(handler: Callable, args: Array) -> void:
	var json := JavaScriptBridge.get_interface("JSON")
	if args.is_empty() or args[0] == null or json == null:
		return
	var parsed: Variant = JSON.parse_string(str(json.stringify(args[0])))
	if not (parsed is Dictionary):
		return
	var sku: Variant = parsed.get("sku")
	if sku is String and sku != "":
		handler.call(sku)
