@tool
extends EditorPlugin

const AUTOLOAD_NAME := "GRush"
const AUTOLOAD_PATH := "res://addons/grush_sdk/grush.gd"
const ExportPlugin := preload("res://addons/grush_sdk/grush_export_plugin.gd")
const Agents := preload("res://addons/grush_sdk/grush_agents.gd")

const AGENTS_MENU := "GameRush: AI エージェント向けの文書を入れる"

var _export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	_export_plugin = ExportPlugin.new()
	add_export_plugin(_export_plugin)
	add_tool_menu_item(AGENTS_MENU, _install_agent_docs)


func _exit_tree() -> void:
	remove_tool_menu_item(AGENTS_MENU)
	remove_export_plugin(_export_plugin)
	_export_plugin = null
	remove_autoload_singleton(AUTOLOAD_NAME)


func _install_agent_docs() -> void:
	var config := ConfigFile.new()
	config.load("res://addons/grush_sdk/plugin.cfg")
	var stamp := "grush_sdk " + String(config.get_value("plugin", "version", ""))
	var result: Dictionary = Agents.install(
		ProjectSettings.globalize_path(Agents.SOURCE_DIR),
		ProjectSettings.globalize_path("res://"),
		stamp
	)
	var labels := {"created": "作りました", "updated": "GameRush の段を足しました", "unchanged": "変更なし"}
	var lines := []
	if result["ok"]:
		lines.append("文書を入れました: %s（%d ファイル）" % [result["dir"], result["files"]])
		for pointer in result["pointers"]:
			if pointer["status"] != "skipped":
				lines.append("%s: %s" % [pointer["file"], labels[pointer["status"]]])
		lines.append("SDK を上げたら、もう一度実行してください。")
	else:
		lines.append("文書を入れられませんでした: " + result["error"])
		push_warning("[GameRush] " + result["error"])
	var dialog := AcceptDialog.new()
	dialog.title = "GameRush"
	dialog.dialog_text = "\n".join(lines)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()
