class_name GRushMockPeer
extends RefCounted

signal received(message: Dictionary)

var index := -1
var pseudo_id := ""
var display_name: Variant = null
var avatar_url: Variant = null

var _hub: WeakRef


func _init(hub: RefCounted) -> void:
	_hub = weakref(hub)


func send(payload: PackedByteArray, channel := "reliable", to := -1) -> void:
	var hub: Variant = _hub.get_ref()
	if hub != null:
		hub.route_from_peer(self, payload, channel, to)


func deliver(message: Dictionary) -> void:
	received.emit(message)
