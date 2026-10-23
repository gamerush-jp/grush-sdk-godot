extends Node

const REQUIRED_PROTOCOL_VERSION := 1
const MAX_MESSAGE_BYTES := 8192
const EVERYONE := -1

const CHANNEL_RELIABLE := "reliable"
const CHANNEL_UNRELIABLE := "unreliable"

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const WebBackend := preload("res://addons/grush_sdk/grush_backend_web.gd")
const MockBackend := preload("res://addons/grush_sdk/grush_backend_mock.gd")
const PlayerApi := preload("res://addons/grush_sdk/grush_player_api.gd")
const NetApi := preload("res://addons/grush_sdk/grush_net_api.gd")
const LeaderboardsApi := preload("res://addons/grush_sdk/grush_leaderboards_api.gd")
const PlayerStateApi := preload("res://addons/grush_sdk/grush_player_state_api.gd")
const PlayerStatePreviewWeb := preload("res://addons/grush_sdk/grush_player_state_preview_web.gd")
const PlayerStatePreviewMock := preload("res://addons/grush_sdk/grush_player_state_preview_mock.gd")
const ShareApi := preload("res://addons/grush_sdk/grush_share_api.gd")
const ShareWeb := preload("res://addons/grush_sdk/grush_share_web.gd")
const ShareMock := preload("res://addons/grush_sdk/grush_share_mock.gd")
const LocaleApi := preload("res://addons/grush_sdk/grush_locale_api.gd")
const LocaleWeb := preload("res://addons/grush_sdk/grush_locale_web.gd")
const LocaleMock := preload("res://addons/grush_sdk/grush_locale_mock.gd")
const LaunchApi := preload("res://addons/grush_sdk/grush_launch_api.gd")
const LaunchWeb := preload("res://addons/grush_sdk/grush_launch_web.gd")
const LaunchMock := preload("res://addons/grush_sdk/grush_launch_mock.gd")
const AnalyticsApi := preload("res://addons/grush_sdk/grush_analytics_api.gd")
const AnalyticsWeb := preload("res://addons/grush_sdk/grush_analytics_web.gd")
const AnalyticsMock := preload("res://addons/grush_sdk/grush_analytics_mock.gd")
const InboxApi := preload("res://addons/grush_sdk/grush_inbox_api.gd")
const TradeApi := preload("res://addons/grush_sdk/grush_trade_api.gd")

var backend: RefCounted
var player: RefCounted
var net: RefCounted
var leaderboards: RefCounted
var player_state: RefCounted
var share: RefCounted
var locale: RefCounted
## 起動パラメータ。GameRush の URL に `gp.` を付けて載せたキーと値で、シェアしたリンクから
## 特定のアイテムやステージへ飛ばすのに使う。値は信用せず、ゲームの側で確かめてから使う。
var launch: RefCounted
## 作者のアナリティクスへ送るイベント。どれも同期で bool を返す。
var analytics: RefCounted
## 受信箱。同じゲームのプレイヤーへ小さい構造化メッセージを送り、受け取る。
var inbox: RefCounted
## 交換所。アイテムを出品し、同じゲームの別のプレイヤーが受ける。
var trade: RefCounted


func _ready() -> void:
	use_backend(null)


func _exit_tree() -> void:
	_dispose()
	if locale != null:
		locale.dispose()
	locale = null
	if player_state != null:
		player_state.dispose()
	player_state = null


## バックエンドを差し替える。null なら実行環境に合うものを作り直す。
## locale と player_state は作り直さないので、changed と preview_received への接続は
## 新しいバックエンドの通知を受け続ける。
func use_backend(replacement: RefCounted) -> void:
	_dispose()
	backend = replacement if replacement != null else _create_backend()
	player = PlayerApi.new(self, backend)
	net = NetApi.new(self, backend)
	leaderboards = LeaderboardsApi.new(self, backend)
	if player_state == null:
		player_state = PlayerStateApi.new(self, backend, _player_state_preview_transport(backend))
	else:
		player_state.use_backend(backend, _player_state_preview_transport(backend))
	share = ShareApi.new(self, _share_transport(backend))
	if locale == null:
		locale = LocaleApi.new(self, _locale_transport(backend))
	else:
		locale.use_transport(_locale_transport(backend))
	launch = LaunchApi.new(self, _launch_transport(backend))
	analytics = AnalyticsApi.new(self, _analytics_transport(backend))
	inbox = InboxApi.new(self, backend)
	trade = TradeApi.new(self, backend)


func _dispose() -> void:
	if net != null:
		net.dispose()
	if launch != null:
		launch.dispose()
	backend = null
	player = null
	net = null
	leaderboards = null
	share = null
	launch = null
	analytics = null
	inbox = null
	trade = null


func is_available() -> bool:
	if backend == null:
		return false
	return backend.is_available() and backend.protocol_version() >= REQUIRED_PROTOCOL_VERSION


func protocol_version() -> int:
	return 0 if backend == null else backend.protocol_version()


func mock_add_peer(display_name: String, avatar_url: Variant = null) -> RefCounted:
	if backend == null or not backend.has_method("add_peer"):
		return null
	return backend.add_peer(display_name, avatar_url)


func mock_remove_peer(peer: RefCounted) -> void:
	if backend != null and backend.has_method("remove_peer"):
		backend.remove_peer(peer)


## モックで、自分がいる部屋に [signal GRushRoom.error_received] を届ける。次のフレーム以降に届き、
## 部屋は閉じない。部屋にいないときと、モックでないときは何もせず [code]false[/code] を返す。
func mock_raise_room_error(code: String, message: String) -> bool:
	if backend == null or not backend.has_method("raise_room_error"):
		return false
	return backend.raise_room_error(code, message)


func _create_backend() -> RefCounted:
	if WebBackend.is_present():
		return WebBackend.new()
	return MockBackend.new()


func _share_transport(active: RefCounted) -> RefCounted:
	if active is WebBackend:
		return ShareWeb.new()
	if active is MockBackend:
		return ShareMock.new()
	return null


func _locale_transport(active: RefCounted) -> RefCounted:
	if active is WebBackend:
		return LocaleWeb.new()
	if active is MockBackend:
		return LocaleMock.new()
	return null


func _player_state_preview_transport(active: RefCounted) -> RefCounted:
	if active is WebBackend:
		return PlayerStatePreviewWeb.new()
	if active is MockBackend:
		return PlayerStatePreviewMock.new()
	return null


func _launch_transport(active: RefCounted) -> RefCounted:
	if active is WebBackend:
		return LaunchWeb.new()
	if active is MockBackend:
		return LaunchMock.new()
	return null


# Web の書き出しを GameRush の外で開いたときは、モックではなく送れない扱いにする（すべての呼び出しが false）。
func _analytics_transport(active: RefCounted) -> RefCounted:
	if active is WebBackend:
		return AnalyticsWeb.new()
	if active is MockBackend and not OS.has_feature("web"):
		return AnalyticsMock.new()
	return null
