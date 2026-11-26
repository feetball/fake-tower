extends MultiplayerPeerExtension
## Server-side MultiplayerPeer that listens on several transports at once (ENet on UDP
## and WebSocket on TCP), so one SceneMultiplayer serves desktop, mobile and browser
## clients together. Peer ids are passed through unchanged (each transport draws random
## 31-bit ids; a clash between transports is refused), so clients' get_unique_id(),
## get_remote_sender_id() on the host and the ids in Room all agree.
## Server only: unique id 1, never connects out.

var _inner: Array[MultiplayerPeer] = []
var _owner: Dictionary = {} # peer id -> inner MultiplayerPeer
## Incoming packets drained from the inner peers: [peer, channel, mode, PackedByteArray].
var _queue: Array[Array] = []
var _target := 0
var _mode: TransferMode = TRANSFER_MODE_RELIABLE
var _channel := 0
var _refusing := false
var _open := false


## Add a listening server peer (already created). Call before handing this to SceneMultiplayer.
func add(peer: MultiplayerPeer) -> void:
	_inner.append(peer)
	peer.peer_connected.connect(_on_inner_connected.bind(peer))
	peer.peer_disconnected.connect(_on_inner_disconnected.bind(peer))
	peer.refuse_new_connections = _refusing
	_open = true


## The inner peer serving `id`, or null.
func peer_transport(id: int) -> MultiplayerPeer:
	return _owner.get(id)


func _on_inner_connected(id: int, src: MultiplayerPeer) -> void:
	if id <= 1 or _owner.has(id):
		src.disconnect_peer.call_deferred(id, true) # id clash across transports: refuse
		return
	_owner[id] = src
	peer_connected.emit(id)


func _on_inner_disconnected(id: int, src: MultiplayerPeer) -> void:
	if _owner.get(id) != src:
		return
	_owner.erase(id)
	_queue = _queue.filter(func(q: Array) -> bool: return q[0] != id)
	peer_disconnected.emit(id)


# ---------------------------------------------------------------- MultiplayerPeer

func _poll() -> void:
	for p in _inner:
		p.poll()
		while p.get_available_packet_count() > 0:
			var from := p.get_packet_peer()
			var ch := p.get_packet_channel()
			var mode := p.get_packet_mode()
			var pkt := p.get_packet()
			if _owner.get(from) == p:
				_queue.append([from, ch, mode, pkt])


func _get_available_packet_count() -> int:
	return _queue.size()


func _get_packet_script() -> PackedByteArray:
	if _queue.is_empty():
		return PackedByteArray()
	return _queue.pop_front()[3]


func _get_packet_peer() -> int:
	return _queue[0][0] if not _queue.is_empty() else 0


func _get_packet_channel() -> int:
	return _queue[0][1] if not _queue.is_empty() else 0


func _get_packet_mode() -> TransferMode:
	return _queue[0][2] if not _queue.is_empty() else TRANSFER_MODE_RELIABLE


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if not _open:
		return ERR_UNCONFIGURED
	if _target > 0:
		var p: MultiplayerPeer = _owner.get(_target)
		if p == null:
			return ERR_INVALID_PARAMETER
		# A WebSocket that is already closing (its peer_disconnected is still to come, e.g.
		# when several browsers leave at once) refuses sends with an engine error: drop quietly.
		if p is WebSocketMultiplayerPeer:
			var ws := (p as WebSocketMultiplayerPeer).get_peer(_target)
			if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
				return ERR_UNAVAILABLE
		return _put(p, _target, buffer)
	# 0 = everyone, -id = everyone but id: each transport applies the same rule to its own peers.
	var err := OK
	for p in _inner:
		var e := _put(p, _target, buffer)
		if e != OK:
			err = e
	return err


func _put(p: MultiplayerPeer, target: int, buffer: PackedByteArray) -> Error:
	p.transfer_mode = _mode
	p.transfer_channel = _channel
	p.set_target_peer(target)
	return p.put_packet(buffer)


func _set_target_peer(peer: int) -> void:
	_target = peer


func _set_transfer_mode(mode: TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> TransferMode:
	return _mode


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _get_unique_id() -> int:
	return 1


func _is_server() -> bool:
	return true


func _is_server_relay_supported() -> bool:
	return true


func _get_connection_status() -> ConnectionStatus:
	return CONNECTION_CONNECTED if _open else CONNECTION_DISCONNECTED


func _get_max_packet_size() -> int:
	return 1 << 24


func _set_refuse_new_connections(enable: bool) -> void:
	_refusing = enable
	for p in _inner:
		p.refuse_new_connections = enable


func _is_refusing_new_connections() -> bool:
	return _refusing


func _disconnect_peer(peer: int, force: bool) -> void:
	var p: MultiplayerPeer = _owner.get(peer)
	if p == null:
		return
	p.disconnect_peer(peer, force)
	if force and _owner.get(peer) == p:
		# A forced drop may not be reported by the transport: report it once here.
		_on_inner_disconnected(peer, p)


func _close() -> void:
	for p in _inner:
		p.close()
	_inner.clear()
	_owner.clear()
	_queue.clear()
	_open = false
