class_name NetCodec
extends RefCounted
## Packs soldier states into bytes for the network: about 25 bytes a soldier,
## so a full 16-a-side snapshot fits in one small packet.

const CROUCHED := 1
const ON_FLOOR := 2
const ZOOMED := 4
const RELOADING := 8
const RIFLE := 16
const ALIVE := 32
const FIRING := 64  # the Maxim, when this soldier is on it


static func flags_of(s: Soldier, firing := false) -> int:
	var f := 0
	if s.crouched:
		f |= CROUCHED
	if s.on_ground():
		f |= ON_FLOOR
	if s.zoomed:
		f |= ZOOMED
	if s.weapon.is_reloading():
		f |= RELOADING
	if s.weapon.kind == "rifle":
		f |= RIFLE
	if s.alive:
		f |= ALIVE
	if firing:
		f |= FIRING
	return f


static func put_angle(buf: StreamPeerBuffer, a: float) -> void:
	buf.put_u16(int(wrapf(a, 0.0, TAU) / TAU * 65535.0))


static func get_angle(buf: StreamPeerBuffer) -> float:
	return buf.get_u16() / 65535.0 * TAU


static func put_pitch(buf: StreamPeerBuffer, a: float) -> void:
	buf.put_16(clampi(int(a * 10000.0), -32767, 32767))


static func get_pitch(buf: StreamPeerBuffer) -> float:
	return buf.get_16() / 10000.0


## Position, velocity, look and flags: what another machine needs to draw
## and animate this soldier. A state from get_motion can stand in for the
## soldier's own position, velocity and look.
static func put_motion(buf: StreamPeerBuffer, s: Soldier, flags: int, st := {}) -> void:
	var pos: Vector3 = st.get("pos", s.global_position)
	var vel: Vector3 = st.get("vel", s.velocity)
	buf.put_u8(s.net_id)
	buf.put_u8(flags)
	buf.put_float(pos.x)
	buf.put_float(pos.y)
	buf.put_float(pos.z)
	for v in [vel.x, vel.y, vel.z]:
		buf.put_16(clampi(int(v * 100.0), -32767, 32767))
	put_angle(buf, st.get("yaw", s.look_yaw))
	put_pitch(buf, st.get("pitch", s.look_pitch))


static func get_motion(buf: StreamPeerBuffer) -> Dictionary:
	var st := {}
	st["id"] = buf.get_u8()
	st["flags"] = buf.get_u8()
	st["pos"] = Vector3(buf.get_float(), buf.get_float(), buf.get_float())
	st["vel"] = Vector3(buf.get_16() / 100.0, buf.get_16() / 100.0, buf.get_16() / 100.0)
	st["yaw"] = get_angle(buf)
	st["pitch"] = get_pitch(buf)
	return st
