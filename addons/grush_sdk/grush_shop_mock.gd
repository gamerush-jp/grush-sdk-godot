extends RefCounted

## エディタ用の付与の合図の受け取り口。[method GRushMockShop.watch_pending] へつなぐ。

var _token := 0


func watch(handler: Callable) -> void:
	if _token == 0:
		_token = GRushMockShop.watch_pending(handler)


func unwatch() -> void:
	if _token != 0:
		GRushMockShop.unwatch_pending(_token)
		_token = 0


func dispose() -> void:
	unwatch()
