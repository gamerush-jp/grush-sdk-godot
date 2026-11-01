extends RefCounted

# Godot の JSON.stringify で書き出して、応答から読み戻せる入れ子の深さを、書き出す前に確かめる。
#
# JSON.stringify は値を1つ書くたびに1段深く呼び直し、JSON_MAX_LEVEL 段を超えると書き出しを打ち切って、`[...]` を含む
# JSON でない文字列を返す（エラーは出すが、呼び出し元へは分からない）。そのまま GameRush へ渡すと壊れた値が届くので、
# SDK は書き出す前に段数を数え、超えた呼び出しは送らずに invalidParams で返す。モックも同じ上限で返す。
#
# 段数は、値を囲む配列と辞書の数に 1 を足したもの（一番外の値が 1 段目）。文字列や数を中に持つ配列と辞書は
# 1024 段まで、空の配列と辞書は 1025 段まで書き出せる。Packed*Array は配列として書き出され、中の値が1段深くなる。
# Godot 4.7・4.7.1・4.7.2 で、配列・辞書・その交互の入れ子について確かめた。Godot の JSON.parse_string も同じ段数まで
# しか読めない。
#
# 書き込んだ値は、応答で何段か包まれて読み戻される。get_mine の状態は1段、get_many と sample の状態の一覧は2段、
# ランキングの top と around_me の行の metadata は3段（ページ・行の配列・行）。包まれた値も JSON_MAX_LEVEL 段を
# 超えると読めないので、書き込める段数は、いちばん深く包む3段を引いた MAX_LEVEL までにする。
#
# 検証は GameRush の側に置くのが原則だが、この上限は SDK に置く。壊れた JSON は SDK の中の JSON.stringify で
# 生じ、GameRush には壊れた後の文字列しか届かず、元の値が見えないので、GameRush では正しく断れないため。

# Godot の JSON.stringify と JSON.parse_string が扱える段数。
const JSON_MAX_LEVEL := 1025
# 読み戻すときに応答が値を包む、いちばん深い段数。
const RESPONSE_WRAP_LEVELS := 3
# 書き込める段数。
const MAX_LEVEL := JSON_MAX_LEVEL - RESPONSE_WRAP_LEVELS

const UNWRITABLE_MESSAGE := "The value is nested too deeply or too large for Godot to send and read back as JSON (1022 levels and 500000 values at most)."

# params をまるごと JSON にして JavaScript へ渡すメソッド（grush_backend_web.gd の _invoke）。ほかのメソッドは
# params の値を1つずつ渡すので、値ごとに数える。
const WHOLE_PARAMS_METHODS := [
	"leaderboard.top",
	"leaderboard.aroundMe",
	"leaderboard.friends",
	"playerState.sample",
	"inbox.list",
	"trade.create",
	"trade.list",
]

# 数える値の数の上限。同じ配列や辞書を何度も指す値は、数えきれないほど大きくなりうる。数え切れない値は、
# どこかに深すぎる枝が残っていても見落とすので、書き出せないとみなして断る。この数は GameRush が値を辿る数の
# 上限と同じなので、ここで断る値は GameRush でも JSON でないとして断られる。
const MAX_VISITS := 500000


# method を params で呼ぶときに JSON にする値を、Godot が書き出せるか。
static func params_writable(method: String, params: Dictionary) -> bool:
	if method in WHOLE_PARAMS_METHODS:
		return writable(params)
	for value in params.values():
		if not writable(value):
			return false
	return true


# value を JSON.stringify が書き出せるか。自分を含む値は段数が尽きないので、書き出せないとみなす。
# 深い入れ子でスタックを使い切らないよう、再帰でなく手元の配列で数える。
static func writable(value: Variant) -> bool:
	var nodes: Array = [value]
	var levels: Array = [1]
	var visits := 0
	while not nodes.is_empty():
		var current: Variant = nodes.pop_back()
		var level: int = levels.pop_back()
		if level > MAX_LEVEL:
			return false
		visits += 1
		if visits > MAX_VISITS:
			return false
		for child in children(current):
			nodes.append(child)
			levels.append(level + 1)
	return true


# 配列・辞書・Packed*Array の中の値。辞書はキーを除いた値。ほかの値は空の配列。
static func children(value: Variant) -> Array:
	if value is Dictionary:
		return value.values()
	if value is Array:
		return value
	if typeof(value) >= TYPE_PACKED_BYTE_ARRAY and typeof(value) < TYPE_MAX:
		return Array(value)
	return []
