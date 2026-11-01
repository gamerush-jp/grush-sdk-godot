extends RefCounted

const JsText := preload("res://addons/grush_sdk/grush_js_text.gd")

# ランタイムの GRushAnalytics へ同期で渡す。params は JSON の文字列にしてから JavaScript の JSON.parse で
# オブジェクトにし、log(kind, params) に渡す。JavaScriptObject のプロパティへ直接書くと、StringName の値が
# undefined になり、"script" などのキーが Object の側に横取りされるため。確かめるのはランタイムで、ここでは値を見ない。


static func _api() -> JavaScriptObject:
	var api := JavaScriptBridge.get_interface("GRushAnalytics")
	if api == null:
		api = JavaScriptBridge.get_interface("GameRushAnalytics")
	return api


func is_available() -> bool:
	var api := _api()
	return api != null and api.isAvailable() == true


func log_event(kind: String, params: Dictionary) -> bool:
	var api := _api()
	var json := JavaScriptBridge.get_interface("JSON")
	if api == null or json == null:
		return false
	# 文字列の対になっていないサロゲートは、JavaScript へ渡す前に U+FFFD に替える（grush_js_text.gd）。
	var parsed: Variant = json.parse(json_of(JsText.sanitized(params)))
	if parsed == null:
		return false
	return api.log(kind, parsed) == true


## params を JSON の文字列にする。キーは文字列にする（JavaScript のプロパティ名は文字列）。値は String をそのまま
## 文字列にし、有限でない数と、String・数・bool・Dictionary のどれでもない値（StringName を含む）は null にする。
## モックも String 以外の文字列を拒むので、どちらでも同じ理由で拒まれる。小数は精度を落とさない書式で書く。
static func json_of(value: Variant) -> String:
	if value is Dictionary:
		var parts := PackedStringArray()
		for key in value:
			parts.append(JSON.stringify(str(key)) + ":" + json_of(value[key]))
		return "{" + ",".join(parts) + "}"
	if value is String:
		return JSON.stringify(value)
	if value is bool:
		return "true" if value else "false"
	if value is int:
		return str(value)
	if value is float:
		return var_to_str(value) if is_finite(value) else "null"
	return "null"
