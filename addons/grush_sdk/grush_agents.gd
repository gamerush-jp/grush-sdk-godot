extends RefCounted

## AI エージェント向けの文書（このアドオンの agents/）を、プロジェクトの .gamerush/ へ写し、
## プロジェクトの AGENTS.md（と、あれば CLAUDE.md）から指す。エディタのメニュー（plugin.gd）から呼ぶ。
## エージェントはアドオンの中を読むとは限らないので、プロジェクトの根に置く。フォルダの名前と目印は
## agents/install.json にあり、JavaScript と Unity の SDK も同じものを読む。

const SOURCE_DIR := "res://addons/grush_sdk/agents"


## source_dir の文書を project_dir へ入れる。どちらも OS のパス。stamp は .gamerush/AGENTS.md に書く SDK の名前と版。
## 返り値は {"ok": bool, "error": String, "dir": String, "files": int, "pointers": [{"file": String, "status": String}]}。
## status は "created"・"updated"・"unchanged"・"skipped"。
static func install(source_dir: String, project_dir: String, stamp: String) -> Dictionary:
	var spec_text := FileAccess.get_file_as_string(source_dir.path_join("install.json"))
	var spec = JSON.parse_string(spec_text)
	if typeof(spec) != TYPE_DICTIONARY:
		return _failure("install.json を読めません: " + source_dir)
	var begin := String(spec.get("begin", ""))
	var end := String(spec.get("end", ""))
	# 段を足す先を先に全部確かめ、目印が壊れていれば何も書かずに止める。
	var planned := []
	for pointer in spec.get("pointers", []):
		var file := String(pointer.get("file", ""))
		var path := project_dir.path_join(file)
		var exists := FileAccess.file_exists(path)
		if not exists and not bool(pointer.get("create", false)):
			planned.append({"file": file, "path": path, "skip": true})
			continue
		var before := FileAccess.get_file_as_string(path) if exists else ""
		var after = upsert(before, begin, end, String(pointer.get("block", "")))
		if after == null:
			return _failure(
				"%s の目印（%s と %s）が1組そろっていません。目印の行を直すか消してから、もう一度実行してください。"
				% [file, begin, end]
			)
		planned.append(
			{"file": file, "path": path, "skip": false, "exists": exists, "before": before, "after": after}
		)

	var dest: String = project_dir.path_join(String(spec.get("dir", ".gamerush")))
	var dest_docs := dest.path_join("docs")
	# 前の版にあって今の版に無いファイルが残らないよう、docs/ は作り直す。
	if DirAccess.dir_exists_absolute(dest_docs) and not _remove_tree(dest_docs):
		return _failure("前の文書を消せません: " + dest_docs)
	if DirAccess.make_dir_recursive_absolute(dest_docs) != OK:
		return _failure("フォルダを作れません: " + dest_docs)

	var agents := FileAccess.get_file_as_string(source_dir.path_join("AGENTS.md"))
	if agents == "":
		return _failure("AGENTS.md を読めません: " + source_dir)
	agents = agents.replace(String(spec.get("versionPlaceholder", "")), stamp)
	if not _write(dest.path_join("AGENTS.md"), agents):
		return _failure("書き込めません: " + dest.path_join("AGENTS.md"))
	var names := Array(DirAccess.get_files_at(source_dir.path_join("docs")))
	names = names.filter(func(name: String) -> bool: return name.ends_with(".md"))
	names.sort()
	for name in names:
		var error := DirAccess.copy_absolute(
			source_dir.path_join("docs").path_join(name), dest_docs.path_join(name)
		)
		if error != OK:
			return _failure("写せません: " + name)

	var pointers := []
	for entry in planned:
		if entry["skip"]:
			pointers.append({"file": entry["file"], "status": "skipped"})
			continue
		var changed: bool = entry["after"] != entry["before"]
		if changed and not _write(entry["path"], entry["after"]):
			return _failure("書き込めません: " + entry["path"])
		var status := "created" if not entry["exists"] else ("updated" if changed else "unchanged")
		pointers.append({"file": entry["file"], "status": status})
	return {"ok": true, "error": "", "dir": dest, "files": names.size() + 1, "pointers": pointers}


## 目印で囲んだ段を入れるか置き換える。目印が無ければ末尾に足す。改行は元の文書に合わせる。
## 目印が片方だけ・2組以上・逆順のときは、置き換えると作者の文を消しかねないので null を返す。
static func upsert(content: String, begin: String, end: String, block: String) -> Variant:
	var eol := "\r\n" if content.find("\r\n") != -1 else "\n"
	var section := begin + eol + block.replace("\n", eol) + eol + end
	var begins := content.count(begin)
	var ends := content.count(end)
	if begins != 0 or ends != 0:
		var start := content.find(begin)
		var stop := content.find(end)
		if begins != 1 or ends != 1 or stop < start:
			return null
		return content.substr(0, start) + section + content.substr(stop + end.length())
	if content == "":
		return section + eol
	var separator := eol if content.ends_with(eol) else eol + eol
	return content + separator + section + eol


## dir の中身ごと消す。.gamerush/docs は SDK が作るフォルダなので、中に何があっても作り直してよい。
static func _remove_tree(dir: String) -> bool:
	for name in DirAccess.get_directories_at(dir):
		if not _remove_tree(dir.path_join(name)):
			return false
	for name in DirAccess.get_files_at(dir):
		if DirAccess.remove_absolute(dir.path_join(name)) != OK:
			return false
	return DirAccess.remove_absolute(dir) == OK


static func _write(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "dir": "", "files": 0, "pointers": []}
