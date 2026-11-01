extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const JsonDepth := preload("res://addons/grush_sdk/grush_json_depth.gd")

# 共有に添える起動パラメータの、GameRush と同じ規則。読む側と違い、1つでも合わなければ共有ごと拒む。
const LAUNCH_KEY_PATTERN := "^[A-Za-z0-9_-]{1,32}$"
const LAUNCH_VALUE_PATTERN := "^[A-Za-z0-9._~:,-]{0,128}$"
const LAUNCH_MAX_PARAMS := 8

static var _launch_key: RegEx
static var _launch_value: RegEx


func call_api(method: String, params: Dictionary, on_done: Callable) -> void:
	on_done.call_deferred(_handle(method, params))


func _handle(method: String, params: Dictionary) -> Dictionary:
	if method == "share.getAvailability":
		return Result.ok(GRushMock.share_available)
	# Web 書き出しの SDK と同じく、Godot が JSON に書き出せない深さの起動パラメータは送る前に断る。
	if not JsonDepth.writable(params.get("launchParams")):
		return Result.failure(Result.CODE_INVALID_PARAMS, JsonDepth.TOO_DEEP_MESSAGE)
	# GameRush は親へ送る前に起動パラメータを確かめるので、共有できない環境でも invalidParams が先に返る。
	if not _launch_params_valid(params.get("launchParams")):
		return Result.failure(Result.CODE_INVALID_PARAMS, "Invalid launch params.")
	if not GRushMock.share_available:
		return Result.failure(Result.CODE_UNAVAILABLE, "Sharing is unavailable here.")
	print(
		(
			"[GRushMock] share text=%s image=%s launch_params=%s"
			% [params.get("text", ""), _describe(params.get("image")), params.get("launchParams", {})]
		)
	)
	return Result.ok(GRushMock.share_status)


static func _describe(image: Variant) -> String:
	if image is Dictionary:
		return "%s (%d base64 chars)" % [image.get("mimeType", ""), str(image.get("base64", "")).length()]
	return "none" if image == null else str(image)


static func _launch_params_valid(launch_params: Variant) -> bool:
	if launch_params == null:
		return true
	if not launch_params is Dictionary or launch_params.size() > LAUNCH_MAX_PARAMS:
		return false
	if _launch_key == null:
		_launch_key = RegEx.create_from_string(LAUNCH_KEY_PATTERN)
		_launch_value = RegEx.create_from_string(LAUNCH_VALUE_PATTERN)
	for key in launch_params:
		var value: Variant = launch_params[key]
		if not key is String or key == "__proto__" or not _matches_whole(_launch_key, key):
			return false
		if not value is String or not _matches_whole(_launch_value, value):
			return false
	return true


# RegEx の $ は末尾の改行の手前でも合うので、合った範囲が文字列の全体かも確かめる。
static func _matches_whole(pattern: RegEx, text: String) -> bool:
	var found := pattern.search(text)
	return found != null and found.get_string() == text
