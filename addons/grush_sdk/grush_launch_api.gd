extends RefCounted

## 起動パラメータ。GameRush の URL に `gp.` を付けて載せたキーと値（`?gp.item=sword` なら
## `{"item": "sword"}`）。シェアしたリンクから特定のアイテムやステージへ飛ばすのに使う。
## キーは英数字と `_-` で 32 文字まで（`__proto__` は使えない）、値は英数字と `._~:,-` で 128 文字まで、8 個まで。
## 形の合わないものは GameRush が落とす。
##
## **値を信用しない。** リンクは誰でも作れる。存在するか・持っているか・解放済みかをゲームの側で
## 確かめてから使い、確かめられなければ無視する。
##
## 渡るのは、プレイヤーが最初に開いたスライドのゲームだけ。別のゲームへスワイプして戻ったときは空。
## フィードではページを読み直すと空になるが、単体表示や埋め込みでは読み直すと同じ値がまた渡ることが
## あるので、何度渡っても困らないように書く。ランタイムの版数が [constant LAUNCH_PROTOCOL_VERSION] 未満のときと
## GameRush の外では、[method fetch] が unsupported、[method current] が null。

const Result := preload("res://addons/grush_sdk/grush_result.gd")
const Call := preload("res://addons/grush_sdk/grush_call.gd")

## 起動パラメータが読めるランタイムの版数。
const LAUNCH_PROTOCOL_VERSION := 8

var _grush: Node
var _transport: RefCounted
var _disposed := false


func _init(grush: Node, transport: RefCounted) -> void:
	_grush = grush
	_transport = transport


## 起動パラメータが届くまで待って返す。value は `{"params": Dictionary, "invite": Dictionary か null}`
## （`params` のキーも値も String）。パラメータの無い起動では `params` が空。
## `invite` は、招待（[code]GRush.net.invite()[/code]）から開いたときの、招いた人の部屋
## `{"mode": String, "room_code": String}`。[code]GRush.net.join(invite["mode"], invite["room_code"])[/code] で
## その部屋へ入る。招待の通知から開いたスライドだけが持ち、ほかと、版数 13 未満のランタイムでは null。
func fetch() -> Dictionary:
	if not _supported():
		return Result.unsupported()
	var pending := Call.new()
	_transport.fetch(func(result: Dictionary) -> void: pending.resolve(result))
	return await pending.completed


## 届いていれば `{"params": Dictionary, "invite": Dictionary か null}`、まだなら null。
func current() -> Variant:
	if not _supported():
		return null
	return _transport.current()


func dispose() -> void:
	_disposed = true
	_transport = null
	_grush = null


func _supported() -> bool:
	return (
		not _disposed
		and _transport != null
		and _grush.is_available()
		and _grush.protocol_version() >= LAUNCH_PROTOCOL_VERSION
	)
