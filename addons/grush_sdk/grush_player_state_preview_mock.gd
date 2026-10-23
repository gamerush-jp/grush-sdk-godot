extends RefCounted

var _token := 0


func watch(handler: Callable) -> void:
	if _token == 0:
		_token = GRushMockPlayerStates.watch_preview(handler)


func dispose() -> void:
	if _token != 0:
		GRushMockPlayerStates.unwatch_preview(_token)
		_token = 0
