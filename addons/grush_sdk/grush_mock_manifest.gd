extends RefCounted

## モックが grush.json を読む。アップロードと同じ規則で読み、誤りはアップロードと
## 同じ文言で返すので、手元で確かめた時点で書き損じに気づける。

const FILE_NAME := "grush.json"
const MAX_BYTES := 64 * 1024
const MAX_LEADERBOARDS := 20
const MAX_TITLE_LENGTH := 60
const MAX_KEY_LENGTH := 64
const TOP_LEVEL_FIELDS := ["$schema", "leaderboards"]
const ENTRY_FIELDS := [
	"key",
	"title",
	"sort",
	"valueType",
	"aggregation",
	"period",
	"minValue",
	"maxValue",
	"enabled",
]
const CHOICES := {
	"sort": ["desc", "asc"],
	"valueType": ["int", "float", "duration_ms"],
	"aggregation": ["best", "last", "sum"],
	"period": ["all_time", "daily", "weekly", "monthly"],
}


## ファイルのバイト列を読む。GameRush と同じく、上限はバイト数で測り、UTF-8 として
## 読めないバイト列は JSON として読めないものとして拒む。読めたら
## {"leaderboards": [...]}、読めなければ {"error": 文言} を返す。
static func parse_bytes(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() > MAX_BYTES:
		return _too_large()
	if not _is_utf8(bytes):
		return _not_object()
	# GameRush は UTF-8 として読むときに先頭の BOM を1つ外し、JSON として読む前にもう1つ外す。
	# 3つ目は JSON として読めない。Godot は文字列にする途中や JSON として読む途中で BOM を読み飛ばすので、
	# バイト列のうちに数える。
	var start := 0
	for _removed in 3:
		if (
			bytes.size() >= start + 3
			and bytes[start] == 0xEF
			and bytes[start + 1] == 0xBB
			and bytes[start + 2] == 0xBF
		):
			start += 3
	if start > 6:
		return _not_object()
	return _parse_text(bytes.slice(start).get_string_from_utf8())


## 読めたら {"leaderboards": [...]}、読めなければ {"error": 文言} を返す。
static func parse(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_BYTES:
		return _too_large()
	for _removed in 2:
		if text.begins_with(char(0xFEFF)):
			text = text.substr(1)
	# GameRush は3つ目の BOM を JSON として読めない。Godot の JSON が読み飛ばしても通さない。
	if text.begins_with(char(0xFEFF)):
		return _not_object()
	return _parse_text(text)


static func _parse_text(text: String) -> Dictionary:
	var marked := _mark_lone_surrogates(text)
	var marker: int = marked["marker"]
	var json := JSON.new()
	if json.parse(marked["text"]) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return _not_object()
	var root: Dictionary = json.data
	for field in root:
		if not TOP_LEVEL_FIELDS.has(field):
			return {"error": "%s has an unknown field: %s" % [FILE_NAME, field]}

	var list: Variant = root.get("leaderboards", null)
	if list == null:
		return {"leaderboards": []}
	if typeof(list) != TYPE_ARRAY:
		return _invalid("leaderboards")
	if list.size() > MAX_LEADERBOARDS:
		return {
			"error": "%s can declare up to %d leaderboards." % [FILE_NAME, MAX_LEADERBOARDS]
		}

	var entries: Array = []
	var seen := {}
	for index in list.size():
		var read := _read_entry(list[index], "leaderboards[%d]" % index, seen, marker)
		if read.has("error"):
			return read
		entries.append(read)
	return {"leaderboards": entries}


# GameRush と同じ順に確かめる。誤りが複数あっても、アップロードと同じ項目を返す。
# marker は、対になっていないサロゲートの代わりに置いた文字（_mark_lone_surrogates）。
static func _read_entry(item: Variant, at: String, seen: Dictionary, marker: int) -> Dictionary:
	if typeof(item) != TYPE_DICTIONARY:
		return _invalid(at)
	for field in item:
		if not ENTRY_FIELDS.has(field):
			return {"error": "%s has an unknown field: %s.%s" % [FILE_NAME, at, field]}

	var key: Variant = item.get("key", null)
	if typeof(key) != TYPE_STRING or not _is_key(key):
		return _invalid(at + ".key")
	if seen.has(key):
		return {"error": "%s declares the leaderboard key more than once: %s" % [FILE_NAME, key]}
	seen[key] = true
	for field in ["minValue", "maxValue"]:
		var value: Variant = item.get(field, null)
		if value == null:
			continue
		var numeric := typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT
		if not numeric or not is_finite(float(value)):
			return _invalid("%s.%s" % [at, field])
	var title := _collapse_title(item.get("title", null), marker)
	var title_length := _utf16_length(title)
	if title_length < 1 or title_length > MAX_TITLE_LENGTH:
		return _invalid(at + ".title")
	for field in CHOICES:
		var value: Variant = item.get(field, null)
		if typeof(value) != TYPE_STRING or not CHOICES[field].has(value):
			return _invalid("%s.%s" % [at, field])
	if item.has("enabled") and typeof(item["enabled"]) != TYPE_BOOL:
		return _invalid(at + ".enabled")
	var min_value: Variant = item.get("minValue", null)
	var max_value: Variant = item.get("maxValue", null)
	if (min_value == null) != (max_value == null):
		return _invalid(at + ".minValue / maxValue")
	if min_value != null and float(min_value) >= float(max_value):
		return _invalid(at + ".minValue / maxValue")

	return {
		"key": key,
		"title": title,
		"sort": item["sort"],
		"value_type": item["valueType"],
		"aggregation": item["aggregation"],
		"period": item["period"],
		"min_value": null if min_value == null else float(min_value),
		"max_value": null if max_value == null else float(max_value),
		"enabled": item.get("enabled", true),
	}


static func _is_key(key: String) -> bool:
	if key.is_empty() or key.length() > MAX_KEY_LENGTH:
		return false
	for index in key.length():
		var c := key.unicode_at(index)
		var allowed := (
			(c >= 0x41 and c <= 0x5A)
			or (c >= 0x61 and c <= 0x7A)
			or (c >= 0x30 and c <= 0x39)
			or c in [0x2E, 0x5F, 0x3A, 0x2D]
		)
		if not allowed:
			return false
	return true


# 改行と制御文字を空白にしてから前後を詰める。GameRush が保存するタイトルと同じ形にする。
# GameRush と同じく、対になっていないサロゲート（marker を置いた所）を先に除く。除いた切れ端の両側の
# 制御文字は、1つの空白にまとまる。
static func _collapse_title(value: Variant, marker: int) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var text: String = value
	var collapsed := ""
	var in_run := false
	for index in text.length():
		var c := text.unicode_at(index)
		if c == marker or (c >= 0xD800 and c <= 0xDFFF):
			continue
		var breaking := (
			c < 0x20
			or (c >= 0x7F and c <= 0x9F)
			or c == 0x2028
			or c == 0x2029
			or (c >= 0x202A and c <= 0x202E)
			or (c >= 0x2066 and c <= 0x2069)
		)
		if breaking:
			if not in_run:
				collapsed += " "
			in_run = true
			continue
		in_run = false
		collapsed += text[index]
	var start := 0
	var end := collapsed.length()
	while start < end and _is_trimmed(collapsed.unicode_at(start)):
		start += 1
	while end > start and _is_trimmed(collapsed.unicode_at(end - 1)):
		end -= 1
	return collapsed.substr(start, end - start)


# GameRush は JSON の文字列の中の、対になっていないサロゲートのエスケープ（`\ud83d` など）を
# 切れ端の1文字として読む。Godot の JSON はそれを読めずに失敗するので、読む前に、ファイルに無い
# 非文字（U+FDD0〜U+FDEF）へ置き換える。置き換えた文字はタイトルから除き、key や sort などの
# 決まった値には当たらないので、GameRush と同じく誤りになる。知らない項目の名前に入っていたときは、
# 誤りの文言に切れ端の代わりにこの文字が出る。
# {"text": 置き換えた JSON, "marker": 置いた文字のコードポイント} を返す。置き換えが無ければ marker は -1。
# 32 個の非文字がすべてファイルにあるときは置き換えず、GameRush と違って JSON として読めない誤りになる。
static func _mark_lone_surrogates(text: String) -> Dictionary:
	var marker := -1
	for candidate in range(0xFDD0, 0xFDF0):
		if text.find(char(candidate)) < 0 and text.findn("\\u%04x" % candidate) < 0:
			marker = candidate
			break
	if marker < 0:
		return {"text": text, "marker": -1}
	var parts := PackedStringArray()
	var copied := 0
	var index := 0
	var in_string := false
	var length := text.length()
	while index < length:
		var c := text.unicode_at(index)
		if not in_string:
			in_string = c == 0x22
			index += 1
			continue
		if c == 0x22:
			in_string = false
			index += 1
			continue
		var skip := 1
		var lone := c >= 0xD800 and c <= 0xDFFF
		if c == 0x5C:
			var unit := _escaped_unit(text, index)
			skip = 2 if unit < 0 else 6
			if unit >= 0xD800 and unit <= 0xDBFF:
				var next := _escaped_unit(text, index + 6)
				if next >= 0xDC00 and next <= 0xDFFF:
					skip = 12
				else:
					lone = true
			elif unit >= 0xDC00 and unit <= 0xDFFF:
				lone = true
		if lone:
			parts.append(text.substr(copied, index - copied))
			parts.append(char(marker))
			copied = index + skip
		index += skip
	if parts.is_empty():
		return {"text": text, "marker": -1}
	parts.append(text.substr(copied))
	return {"text": "".join(parts), "marker": marker}


# index から `\uXXXX` のエスケープがあれば、その符号単位の値を返す。無ければ -1。
static func _escaped_unit(text: String, index: int) -> int:
	if index + 6 > text.length() or text.unicode_at(index) != 0x5C:
		return -1
	if text.unicode_at(index + 1) != 0x75:
		return -1
	var value := 0
	for offset in range(2, 6):
		var c := text.unicode_at(index + offset)
		var digit := -1
		if c >= 0x30 and c <= 0x39:
			digit = c - 0x30
		elif c >= 0x41 and c <= 0x46:
			digit = c - 0x41 + 10
		elif c >= 0x61 and c <= 0x66:
			digit = c - 0x61 + 10
		if digit < 0:
			return -1
		value = value * 16 + digit
	return value


# GameRush の trim が外す空白（ECMAScript の WhiteSpace と LineTerminator）。strip_edges は
# U+0020 以下しか外さないので使わない。制御文字と行の区切りは先に空白へ潰してある。
static func _is_trimmed(c: int) -> bool:
	return (
		c == 0x20
		or c == 0xA0
		or c == 0x1680
		or (c >= 0x2000 and c <= 0x200A)
		or c == 0x202F
		or c == 0x205F
		or c == 0x3000
		or c == 0xFEFF
	)


# GameRush はタイトルの長さを UTF-16 の単位で数える。Godot の String は1文字を1つと数えるので、
# U+FFFF を超える文字（絵文字など）を2つと数え直す。
static func _utf16_length(text: String) -> int:
	var length := 0
	for index in text.length():
		length += 2 if text.unicode_at(index) > 0xFFFF else 1
	return length


# 正しい UTF-8 か。冗長な符号化、サロゲート、U+10FFFF を超える値も拒む。NUL は JSON のどこにも
# 書けないうえ get_string_from_utf8 がそこで読むのを止めるので、ここで拒む。
static func _is_utf8(bytes: PackedByteArray) -> bool:
	var index := 0
	var size := bytes.size()
	while index < size:
		var lead := bytes[index]
		if lead == 0:
			return false
		if lead < 0x80:
			index += 1
			continue
		var count := 0
		var low := 0x80
		var high := 0xBF
		if lead >= 0xC2 and lead <= 0xDF:
			count = 1
		elif lead >= 0xE0 and lead <= 0xEF:
			count = 2
			if lead == 0xE0:
				low = 0xA0
			elif lead == 0xED:
				high = 0x9F
		elif lead >= 0xF0 and lead <= 0xF4:
			count = 3
			if lead == 0xF0:
				low = 0x90
			elif lead == 0xF4:
				high = 0x8F
		else:
			return false
		if index + count >= size:
			return false
		for offset in range(1, count + 1):
			var next := bytes[index + offset]
			var lower := low if offset == 1 else 0x80
			var upper := high if offset == 1 else 0xBF
			if next < lower or next > upper:
				return false
		index += count + 1
	return true


static func _too_large() -> Dictionary:
	return {"error": "%s is too large (%dKB at most)." % [FILE_NAME, MAX_BYTES / 1024]}


static func _not_object() -> Dictionary:
	return {"error": "%s can't be read as a JSON object." % FILE_NAME}


static func _invalid(field: String) -> Dictionary:
	return {"error": "%s has an invalid value: %s" % [FILE_NAME, field]}
