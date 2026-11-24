extends RefCounted

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const Call := preload("res://addons/grush_sdk/grush_call.gd")

var _grush: Node
var _backend: RefCounted


func _init(grush: Node, backend: RefCounted) -> void:
	_grush = grush
	_backend = backend


## 自分のプレイヤー。値は pseudo_id・is_guest・profile_consent・is_creator・display_name・avatar_url を持つ。
## is_creator は、このゲームのオーナーか承諾済みの共同制作者なら true で、GameRush のサーバが決める。
## 作者にだけ見せる表示の出し分けに使う。権限ではない。ゲームは遊ぶ人の手元で動き、書き換えれば true に
## 見せられるので、守りたい操作は GameRush が確かめるもの（ショップのテスト購入など）に任せる。
## ゲストは常に false。
func get_self() -> Dictionary:
	return await _call("player.getSelf")


func request_profile() -> Dictionary:
	return await _call("player.requestProfile")


func revoke_profile() -> Dictionary:
	return await _call("player.revokeProfile")


func _call(method: String) -> Dictionary:
	if not _grush.is_available():
		return Result.unsupported()
	var pending := Call.new()
	_backend.call_api(method, {}, func(result: Dictionary) -> void: pending.resolve(result))
	var response: Dictionary = await pending.completed
	if not response["ok"]:
		return response
	return Result.ok(_normalize(response["value"]))


static func _normalize(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var consent: bool = source.get("profileConsent", false)
	var profile: Variant = source.get("profile", null)
	var display_name: Variant = null
	var avatar_url: Variant = null
	if consent and profile is Dictionary:
		display_name = profile.get("displayName", null)
		avatar_url = profile.get("avatarUrl", null)
	return {
		"pseudo_id": source.get("pseudoId", ""),
		"is_guest": source.get("isGuest", true),
		"profile_consent": consent,
		"is_creator": source.get("isCreator", false) == true,
		"display_name": display_name,
		"avatar_url": avatar_url,
	}
