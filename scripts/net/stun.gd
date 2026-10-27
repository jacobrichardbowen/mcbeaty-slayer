class_name Stun
extends RefCounted
## Asks a public STUN server where this computer's packets appear to come
## from on the internet: the far side of the home router, address and port.
## It is one small UDP question and answer, the same one browsers and voice
## chat apps use. Nothing on the router is changed.

const MAGIC := 0x2112A442
const BINDING_REQUEST := 0x0001
const BINDING_RESPONSE := 0x0101
const MAPPED_ADDRESS := 0x0001
const XOR_MAPPED_ADDRESS := 0x0020


static func request(txn: PackedByteArray) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.big_endian = true
	buf.put_u16(BINDING_REQUEST)
	buf.put_u16(0)
	buf.put_u32(MAGIC)
	buf.put_data(txn)
	return buf.data_array


## [address, port] from the answer to request `txn`, or [] if it isn't one.
static func parse(packet: PackedByteArray, txn: PackedByteArray) -> Array:
	if packet.size() < 20:
		return []
	var buf := StreamPeerBuffer.new()
	buf.big_endian = true
	buf.data_array = packet
	if buf.get_u16() != BINDING_RESPONSE:
		return []
	var end := 20 + buf.get_u16()
	if buf.get_u32() != MAGIC or packet.slice(8, 20) != txn or packet.size() < end:
		return []
	var found := []
	buf.seek(20)
	while buf.get_position() + 4 <= end:
		var type := buf.get_u16()
		var size := buf.get_u16()
		var start := buf.get_position()
		if (type == XOR_MAPPED_ADDRESS or type == MAPPED_ADDRESS) and size >= 8:
			buf.get_u8()
			var family := buf.get_u8()
			var port := buf.get_u16()
			var ip := buf.get_u32()
			if family == 1:  # IPv4
				if type == XOR_MAPPED_ADDRESS:
					port ^= MAGIC >> 16
					ip ^= MAGIC
				found = ["%d.%d.%d.%d" % [(ip >> 24) & 255, (ip >> 16) & 255, (ip >> 8) & 255, ip & 255], port]
				if type == XOR_MAPPED_ADDRESS:
					return found
		buf.seek(start + ((size + 3) & ~3))  # attributes are padded to 4 bytes
	return found


## Blocking, so run it on a thread. Binds `local_port` (0 for any), asks the
## servers ([host, port] pairs) in turn, and returns {"local_port"} plus, if
## one answered, {"address", "port", "server": [ip, port]}; or {"error":
## "bind"} if the port is taken. `abort` is checked often and stops it early.
static func discover(local_port: int, servers: Array, abort: Callable) -> Dictionary:
	var udp := PacketPeerUDP.new()
	if udp.bind(local_port) != OK:
		return {"error": "bind"}
	var result := {"local_port": udp.get_local_port()}
	var crypto := Crypto.new()
	for attempt in 2:
		for server: Array in servers:
			if abort.call():
				udp.close()
				return result
			var ip := IP.resolve_hostname(server[0], IP.TYPE_IPV4)
			if not ip.is_valid_ip_address():
				continue
			var txn := crypto.generate_random_bytes(12)
			udp.set_dest_address(ip, server[1])
			udp.put_packet(request(txn))
			var until := Time.get_ticks_msec() + 700 * (attempt + 1)
			while Time.get_ticks_msec() < until and not abort.call():
				while udp.get_available_packet_count() > 0:
					var found := parse(udp.get_packet(), txn)
					if not found.is_empty():
						udp.close()
						result.merge({"address": found[0], "port": found[1], "server": [ip, server[1]]})
						return result
				OS.delay_msec(10)
	udp.close()
	return result
