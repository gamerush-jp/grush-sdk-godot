extends RefCounted

# JavaScript へ渡す値の文字列を、UTF-8 で運べる形にする。
#
# Godot の Web の書き出しは、String を UTF-8 にして JavaScript へ渡す。対になっていないサロゲートの code point
# （U+D800〜U+DFFF。UTF-16 のバイト列から作った文字列などに残る）は UTF-8 で表せない。JavaScript の側の読み方の
# 違いで、短い文字列では切れ端のまま届き、長い文字列では U+FFFD 3つになって届く。切れ端のまま届くと GameRush に
# 断られ、応答も Godot の JSON が読めない。渡す前に U+FFFD 1つに替えて、長さで結果が分かれないようにする。


# value の中の文字列（辞書のキーを含む）の切れ端を U+FFFD に替えた値。切れ端が無ければ value をそのまま返し、
# あれば元の値を変えずに写しを返す。深い入れ子でスタックを使い切らないよう、再帰でなく手元の配列で辿る。
static func sanitized(value: Variant) -> Variant:
	if not _has_lone_surrogate(value):
		return value
	if value is String or value is StringName:
		return replaced(str(value))
	var root: Variant = _empty_like(value)
	var pairs: Array = [[value, root]]
	while not pairs.is_empty():
		var pair: Array = pairs.pop_back()
		var source: Variant = pair[0]
		var target: Variant = pair[1]
		if source is Dictionary:
			for key in source:
				var copied_key: Variant = replaced(str(key)) if key is String or key is StringName else key
				target[copied_key] = _copied_item(source[key], pairs)
		else:
			for item in source:
				target.append(_copied_item(item, pairs))
	return root


# 文字列の切れ端を U+FFFD に替える。Godot の String は1文字を1つのコードポイントで持つので、対のサロゲートは
# 1つの文字に合わさっていて、U+D800〜U+DFFF の値が残るのは対になっていない切れ端だけ。
static func replaced(text: String) -> String:
	if not _has_surrogate_code_point(text):
		return text
	var parts := PackedStringArray()
	for index in text.length():
		var c := text.unicode_at(index)
		parts.append(char(0xFFFD) if c >= 0xD800 and c <= 0xDFFF else text[index])
	return "".join(parts)


static func _copied_item(item: Variant, pairs: Array) -> Variant:
	if item is String or item is StringName:
		return replaced(str(item))
	if item is Dictionary or item is Array:
		var copy: Variant = _empty_like(item)
		pairs.append([item, copy])
		return copy
	if typeof(item) == TYPE_PACKED_STRING_ARRAY:
		var strings: Array = []
		pairs.append([Array(item), strings])
		return strings
	return item


static func _empty_like(value: Variant) -> Variant:
	if value is Dictionary:
		return {}
	return []


static func _has_lone_surrogate(value: Variant) -> bool:
	var stack: Array = [value]
	while not stack.is_empty():
		var current: Variant = stack.pop_back()
		if current is String or current is StringName:
			if _has_surrogate_code_point(str(current)):
				return true
		elif current is Dictionary:
			for key in current:
				if (key is String or key is StringName) and _has_surrogate_code_point(str(key)):
					return true
				stack.append(current[key])
		elif current is Array:
			stack.append_array(current)
		elif typeof(current) == TYPE_PACKED_STRING_ARRAY:
			stack.append_array(Array(current))
	return false


static func _has_surrogate_code_point(text: String) -> bool:
	for index in text.length():
		var c := text.unicode_at(index)
		if c >= 0xD800 and c <= 0xDFFF:
			return true
	return false
