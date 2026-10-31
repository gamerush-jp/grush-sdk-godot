extends RefCounted

## Web に書き出したゲームを GameRush の外で開いたときのバックエンド。どの呼び出しも unsupported を返す。

const Result := preload("res://addons/grush_sdk/grush_result.gd")


func is_available() -> bool:
	return false


func protocol_version() -> int:
	return 0


func set_net_event_handler(_handler: Callable) -> void:
	pass


func call_api(_method: String, _params: Dictionary, on_done: Callable) -> void:
	on_done.call_deferred(
		Result.failure(Result.CODE_UNSUPPORTED, "GameRush GameAPI is not available here.")
	)


func send(_payload: PackedByteArray, _channel: String, _to: int) -> void:
	pass
