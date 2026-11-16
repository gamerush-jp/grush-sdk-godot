extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const Call := preload("res://addons/grush_sdk/grush_call.gd")
const Room := preload("res://addons/grush_sdk/grush_room.gd")

## 部屋の定員・形・ホストの選び方（[method join_with] の [code]max_peers[/code]・[code]topology[/code]・
## [code]host_selection[/code]）を渡せるランタイムの版数。
const ROOM_CONFIG_PROTOCOL_VERSION := 11
## [method join_with] で渡せる部屋の形。全員が全員へ送る。定員は 16 まで。
const TOPOLOGY_MESH := "mesh"
## [method join_with] で渡せる部屋の形。非ホストはホストへだけ送り、ホストが全員へ配る。
const TOPOLOGY_HUB := "hub"

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
	var params := {"mode": mode}
	if room_code != "":
		params["roomCode"] = room_code
	if target_room_size != 0:
		params["targetRoomSize"] = target_room_size
	return await _join(params)


## 部屋へ入る。[method join] に、部屋の定員と形、ホストの選び方を足した形。[param options] のキーは次のとおりで、
## どれも省略できる。値の検査は GameRush がし、合わなければ invalidParams。
## [br]- [code]mode[/code]: String。既定 [code]"default"[/code]。
## [br]- [code]room_code[/code]: String。指定した部屋へ入る。その部屋が違う定員か形で既にあれば invalidParams。
## [br]- [code]target_room_size[/code]: 部屋の目安の人数で、1〜定員の整数。働きは [method join] と同じ。
## [br]- [code]max_peers[/code]: 部屋の定員で、1〜100 の整数。既定 8。
## [br]- [code]topology[/code]: [constant TOPOLOGY_MESH]（既定。定員 16 まで）か [constant TOPOLOGY_HUB]。
## hub の部屋の非ホストが送れるのはホスト宛てと全員宛て（ホスト宛てとして読まれる）だけで、ほかの宛先は
## [signal GRushRoom.error_received] の [code]"targetNotAllowed"[/code] で捨てられる。部屋は非ホストの入力を
## 50ms ごとにまとめてホストへ渡し、ホストには1通ずつ [signal GRushRoom.message_received] で届く。
## hub のホストは、入力を受けている間は少なくとも 2 秒ごとに送る。送らないと止まったとみなされ、ホストが替わる。
## [br]- [code]host_selection[/code]: [code]"auto"[/code] を渡すと、端末の性能と遅延で部屋がホストを選ぶ。
## 渡さなければ最初に入った peer がホスト。どちらでもホストは替わることがあるので、
## [signal GRushRoom.host_changed] を受ける。
## [br][code]max_peers[/code]・[code]topology[/code]・[code]host_selection[/code] のどれかを渡したとき、
## ランタイムの版数が [constant ROOM_CONFIG_PROTOCOL_VERSION] 未満なら unsupported。
## 古いアプリの GameRush は定員と形を無視して 8 人の mesh の部屋へ入るので、入った部屋の定員と形は
## [member GRushRoom.max_peers] と [member GRushRoom.topology] で確かめる。
func join_with(options: Dictionary = {}) -> Dictionary:
	if not _grush.is_available():
		return Result.unsupported()
	var mode: Variant = options.get("mode")
	var params := {"mode": mode if mode != null else "default"}
	var keys := {
		"room_code": "roomCode",
		"target_room_size": "targetRoomSize",
		"max_peers": "maxPeers",
		"topology": "topology",
		"host_selection": "hostSelection",
	}
	for key in keys:
		if options.has(key) and options[key] != null:
			params[keys[key]] = options[key]
	var needs_room_config := (
		params.has("maxPeers") or params.has("topology") or params.has("hostSelection")
	)
	if needs_room_config and _grush.protocol_version() < ROOM_CONFIG_PROTOCOL_VERSION:
		return Result.unsupported()
	return await _join(params)


func _join(params: Dictionary) -> Dictionary:
	_bind()
	var previous := room
	room = null
	if previous != null:
		previous.close_locally("replaced")
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
