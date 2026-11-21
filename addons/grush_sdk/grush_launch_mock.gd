extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")

# GameRush と同じく、招待の部屋は mode と部屋コードが join の形に合うときだけ渡す。`$` は末尾の改行の前でも合うので
# `\z` で終える。
static var _mode_pattern := RegEx.create_from_string("^[A-Za-z0-9._:-]{1,32}\\z")
static var _room_code_pattern := RegEx.create_from_string("^[A-Za-z0-9]{4,12}\\z")


func current() -> Variant:
	var params := {}
	for key in GRushMock.launch_params:
		var value: Variant = GRushMock.launch_params[key]
		if value is String:
			params[str(key)] = value
	return {"params": params, "invite": _invite()}


static func _invite() -> Variant:
	var value: Variant = GRushMock.launch_invite
	if not (value is Dictionary):
		return null
	var mode: Variant = value.get("mode")
	var room_code: Variant = value.get("room_code")
	if not (mode is String) or _mode_pattern.search(mode) == null:
		return null
	if not (room_code is String) or _room_code_pattern.search(room_code) == null:
		return null
	return {"mode": mode, "room_code": room_code}


func fetch(on_done: Callable) -> void:
	on_done.call_deferred(Result.ok(current()))
