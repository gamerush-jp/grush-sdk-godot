extends RefCounted

## ランキング。定義は作者が Studio で宣言するもので、ゲームからは作れない
## （作らせると値域も並び順も後から書き換えられて異常検知が成立しない）。
## ゲームができるのは、宣言済みの枠へ投稿することと読むことだけ。
##
## スコアは自己申告であり GameRush は値を検証していない。応答の
## `verified` は常に false で、表示側はそれを隠さないこと。

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const Call := preload("res://addons/grush_sdk/grush_call.gd")

var _grush: Node
var _backend: RefCounted


func _init(grush: Node, backend: RefCounted) -> void:
	_grush = grush
	_backend = backend


func list() -> Dictionary:
	var response := await _call("leaderboard.list", {})
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	var boards: Array = []
	if raw is Dictionary and raw.get("leaderboards") is Array:
		for entry in raw["leaderboards"]:
			boards.append(_definition_of(entry))
	return Result.ok(boards)


## スコアを投稿する。`metadata` は 1KB 以下の辞書（省略可）。session は親が
## 付けるのでゲームは指定できない。有効プレイが 10 秒に満たないセッション
## からの投稿は保存されない。Godot は `metadata` を JSON にして渡すので、Godot が書き出せない
## ほど深い入れ子（文字列や数を持つ配列と辞書が 1024 段を超えるもの）は、送らずに invalidParams で返す。
##
## `operation_id` は同じ投稿の再送を弾く識別子。**集約が sum のランキングで
## 投稿を再送するなら必ず渡すこと** — 加算は冪等でないため、応答が失われて
## 送り直すと二重に足され、集約後の値からは元へ戻せない。
func submit(
	key: String, value: float, metadata: Variant = null, operation_id: Variant = null
) -> Dictionary:
	var params := {"key": key, "value": value}
	if metadata != null:
		params["metadata"] = metadata
	if operation_id != null:
		params["operationId"] = str(operation_id)
	var response := await _call("leaderboard.submit", params)
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	var result: Variant = raw.get("result") if raw is Dictionary else null
	if not (result is Dictionary):
		return Result.failure(Result.CODE_INTERNAL, "GameRush returned an unreadable score result.")
	return Result.ok(
		{
			"accepted": bool(result.get("accepted", false)),
			"updated": bool(result.get("updated", false)),
			"value": float(result.get("value", 0.0)),
			"rank": result.get("rank", null),
			"verified": false,
		}
	)


func top(key: String, options: Dictionary = {}) -> Dictionary:
	var params := {"key": key}
	if options.has("limit"):
		params["limit"] = int(options["limit"])
	if options.has("offset"):
		params["offset"] = int(options["offset"])
	return await _page("leaderboard.top", params)


## 自分の前後を返す。まだ自分が載っていないときは `entries` が空になる
## （先頭を返すと「自分が1位」と読めてしまう）。
func around_me(key: String, options: Dictionary = {}) -> Dictionary:
	var params := {"key": key}
	if options.has("range"):
		params["range"] = int(options["range"])
	return await _page("leaderboard.aroundMe", params)


## 相互フォローだけに絞ったランキング。ゲームごとのフレンド同意が前提で、
## 同意の仕組みが入るまでは consentDeclined を返す。
func friends(key: String, options: Dictionary = {}) -> Dictionary:
	var params := {"key": key}
	if options.has("limit"):
		params["limit"] = int(options["limit"])
	return await _page("leaderboard.friends", params)


func _page(method: String, params: Dictionary) -> Dictionary:
	var response := await _call(method, params)
	if not response["ok"]:
		return response
	var raw: Variant = response["value"]
	var page: Variant = raw.get("leaderboard") if raw is Dictionary else null
	if not (page is Dictionary):
		return Result.failure(Result.CODE_INTERNAL, "GameRush returned an unreadable leaderboard.")
	var entries: Array = []
	if page.get("entries") is Array:
		for entry in page["entries"]:
			entries.append(_entry_of(entry))
	return Result.ok(
		{
			"key": str(page.get("key", "")),
			"title": str(page.get("title", "")),
			"sort": str(page.get("sort", "desc")),
			"value_type": str(page.get("valueType", "int")),
			"period": str(page.get("period", "all_time")),
			"period_key": str(page.get("period_key", page.get("periodKey", ""))),
			"verified": false,
			"entries": entries,
			"total": int(page.get("total", 0)),
		}
	)


func _call(method: String, params: Dictionary) -> Dictionary:
	if not _grush.is_available():
		return Result.unsupported()
	var pending := Call.new()
	_backend.call_api(method, params, func(result: Dictionary) -> void: pending.resolve(result))
	return await pending.completed


static func _definition_of(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	return {
		"key": str(source.get("key", "")),
		"title": str(source.get("title", "")),
		"sort": str(source.get("sort", "desc")),
		"value_type": str(source.get("valueType", "int")),
		"aggregation": str(source.get("aggregation", "best")),
		"period": str(source.get("period", "all_time")),
		"min_value": source.get("minValue", null),
		"max_value": source.get("maxValue", null),
	}


## 表示名とアイコンは、その相手がこのゲームでの公開に同意しているときだけ
## 入る。ゲストは常に匿名なので `is_guest` を見て固定ラベルを出す。
static func _entry_of(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	return {
		"rank": int(source.get("rank", 0)),
		"pseudo_id": str(source.get("pseudoId", "")),
		"display_name": source.get("displayName", null),
		"avatar_url": source.get("avatarUrl", null),
		"is_guest": bool(source.get("isGuest", true)),
		"value": float(source.get("value", 0.0)),
		"metadata": source.get("metadata", null),
		"submitted_at": str(source.get("submittedAt", "")),
		"is_self": bool(source.get("isSelf", false)),
	}
