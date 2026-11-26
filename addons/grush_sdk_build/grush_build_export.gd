@tool
extends RefCounted

const Settings := preload("res://addons/grush_sdk_build/grush_build_settings.gd")

const MAX_BUILD_FILE_COUNT := 2000
const MAX_BUILD_BYTES := 104857600
const WARN_BUILD_BYTES := 15728640
const REQUIRED_OUTPUTS := ["index.html", "index.pck", "index.wasm", "index.js"]
const MODIFIED_TIME_TOLERANCE := 2
const GDIGNORE_FILE := ".gdignore"
const SHARED_PARENT_WARNING := "書き出し先の親フォルダにほかのファイルがあるため、取り込み対象から外していません。エディタが書き出したファイルを取り込み、.import ファイルを作ることがあります。アップロードの前に .import ファイルを消すか、build/gamerush のような専用のフォルダかプロジェクトの外へ書き出してください"

const CODE_OK := 0
const CODE_EXPORT_FAILED := 1
const CODE_BAD_ARGS := 2
const CODE_LIMIT_EXCEEDED := 4


static func run(output_dir: String) -> Dictionary:
	var problem := environment_problem()
	if not problem.is_empty():
		return _result(CODE_BAD_ARGS, problem)
	var absolute := Settings.absolute_dir(output_dir)
	var unsafe := Settings.unsafe_reason(absolute)
	if not unsafe.is_empty():
		return _result(CODE_BAD_ARGS, unsafe)
	var inside_project := Settings.is_inside_project(absolute)
	var ignore_parent := inside_project and _is_dedicated_parent(absolute)
	var made := DirAccess.make_dir_recursive_absolute(absolute)
	if made != OK:
		return _result(CODE_BAD_ARGS, "出力先を作れませんでした: %s（error %d）" % [absolute, made])
	if ignore_parent:
		_write_gdignore(absolute.get_base_dir())
	var started := int(Time.get_unix_time_from_system())
	var output: Array = []
	var exit_code := OS.execute(OS.get_executable_path(), export_arguments(absolute), output, true)
	var export_log := _join_output(output)
	var missing := _missing_outputs(absolute, started)
	if exit_code != 0 or not missing.is_empty():
		return _result(CODE_EXPORT_FAILED, _failure_message(exit_code, missing), 0, 0, export_log)
	var result := _check_limits(absolute, export_log)
	if inside_project and not ignore_parent:
		var warnings: PackedStringArray = result["warnings"]
		warnings.append(SHARED_PARENT_WARNING)
		result["warnings"] = warnings
	return result


static func export_arguments(absolute: String) -> PackedStringArray:
	return PackedStringArray([
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"--export-release",
		Settings.PRESET_NAME,
		absolute.path_join(Settings.EXPORT_FILE_NAME),
	])


static func format_megabytes(bytes: int) -> String:
	return "%.1f MB" % (float(bytes) / 1048576.0)


static func environment_problem() -> String:
	return Settings.environment_problem()


static func _check_limits(absolute: String, export_log: String) -> Dictionary:
	var totals := {"files": 0, "bytes": 0}
	_tally(absolute, totals)
	var file_count := int(totals["files"])
	var total_bytes := int(totals["bytes"])
	var summary := "合計 %s / %d ファイル" % [format_megabytes(total_bytes), file_count]
	var problems := PackedStringArray()
	if file_count > MAX_BUILD_FILE_COUNT:
		problems.append("ファイル数が上限 %d を超えています" % MAX_BUILD_FILE_COUNT)
	if total_bytes > MAX_BUILD_BYTES:
		problems.append("合計サイズが上限 %s を超えています" % format_megabytes(MAX_BUILD_BYTES))
	if not problems.is_empty():
		var over := "GameRush にアップロードできません（%s）: %s" % [summary, "、".join(problems)]
		return _result(CODE_LIMIT_EXCEEDED, over, total_bytes, file_count, export_log)
	var message := "書き出しました: %s（%s）" % [absolute, summary]
	var warnings := PackedStringArray()
	if total_bytes > WARN_BUILD_BYTES:
		warnings.append("%s を超えると、スマホ回線では読み込みに時間がかかります。テクスチャや音声の圧縮を見直してください" % format_megabytes(WARN_BUILD_BYTES))
	var result := _result(CODE_OK, message, total_bytes, file_count, export_log)
	result["warnings"] = warnings
	return result


static func _tally(dir: String, totals: Dictionary) -> void:
	for file_name: String in DirAccess.get_files_at(dir):
		totals["files"] = int(totals["files"]) + 1
		var file := FileAccess.open(dir.path_join(file_name), FileAccess.READ)
		if file != null:
			totals["bytes"] = int(totals["bytes"]) + file.get_length()
	for child: String in DirAccess.get_directories_at(dir):
		_tally(dir.path_join(child), totals)


static func _missing_outputs(absolute: String, started: int) -> PackedStringArray:
	var missing := PackedStringArray()
	for file_name: String in REQUIRED_OUTPUTS:
		var path := absolute.path_join(file_name)
		if not FileAccess.file_exists(path):
			missing.append(file_name)
		elif FileAccess.get_modified_time(path) + MODIFIED_TIME_TOLERANCE < started:
			missing.append(file_name + "（更新されていない）")
	return missing


static func _failure_message(exit_code: int, missing: PackedStringArray) -> String:
	var lines := PackedStringArray(["書き出しに失敗しました（終了コード %d）" % exit_code])
	if not missing.is_empty():
		lines.append("出力にありません: %s" % ", ".join(missing))
	lines.append("よくある原因: Web 用の書き出しテンプレートが未インストール（Editor > Manage Export Templates から導入）")
	return "\n".join(lines)


static func _is_dedicated_parent(absolute: String) -> bool:
	var parent := absolute.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent):
		return true
	if not DirAccess.get_files_at(parent).is_empty():
		return false
	for child: String in DirAccess.get_directories_at(parent):
		if child != absolute.get_file():
			return false
	return true


static func _write_gdignore(absolute: String) -> void:
	var path := absolute.path_join(GDIGNORE_FILE)
	if FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.close()


static func _join_output(output: Array) -> String:
	var parts := PackedStringArray()
	for chunk: Variant in output:
		parts.append(str(chunk))
	return "".join(parts)


static func _result(code: int, message: String, total_bytes: int = 0, file_count: int = 0, export_log: String = "") -> Dictionary:
	return {
		"code": code,
		"message": message,
		"total_bytes": total_bytes,
		"file_count": file_count,
		"log": export_log,
		"warnings": PackedStringArray(),
	}
