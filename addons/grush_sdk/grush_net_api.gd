extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const Call := preload("res://addons/grush_sdk/grush_call.gd")
const Room := preload("res://addons/grush_sdk/grush_room.gd")

var room: GRushRoom = null

var _grush: Node
var _backend: RefCounted
var _bound := false


func _init(grush: Node, backend: RefCounted) -> void:
	_grush = grush
	_backend = backend


## 部屋へ入る。[param target_room_size] は部屋の目安の人数で、1〜8 の整数。渡すと、新しい部屋から最大 8 部屋を
## 確かめ、目安に届いていない部屋のうち最も人数の少ない部屋へ入る。確かめた部屋がどれも目安以上なら新しい部屋が
## できる。範囲の外は invalidParams。0 は未指定で、目安を送らない。[param room_code] で部屋を指定したときは、指定した部屋へ入る。
## 目安を知らない版の GameRush では無視され、ゲームからは見分けられない。
func join(mode := "default", room_code := "", target_room_size := 0) -> Dictionary:
	if not _grush.is_available():
		return Result.unsupported()
	_bind()
	var previous := room
	room = null
	if previous != null:
		previous.close_locally("replaced")
	var params := {"mode": mode}
	if room_code != "":
		params["roomCode"] = room_code
	if target_room_size != 0:
		params["targetRoomSize"] = target_room_size
	var pending := Call.new()
	_backend.call_api("net.join", params, func(result: Dictionary) -> void: pending.resolve(result))
	var response: Dictionary = await pending.completed
	if not response["ok"]:
		return response
	var info: Variant = response["value"]
	if not (info is Dictionary) or str(info.get("roomId", "")) == "":
		return Result.failure(Result.CODE_INTERNAL, "GameRush returned an unreadable room.")
	room = Room.new(_grush, _backend, self, info)
	return Result.ok(room)


func forget(closed_room: GRushRoom) -> void:
	if room == closed_room:
		room = null


func dispose() -> void:
	if _backend != null and _bound:
		_backend.set_net_event_handler(Callable())
	room = null
	_backend = null
	_grush = null
	_bound = false


func _bind() -> void:
	if _bound:
		return
	_bound = true
	_backend.set_net_event_handler(func(event: Dictionary) -> void: _on_event(event))


func _on_event(event: Dictionary) -> void:
	if room != null:
		room.apply(event)
