class_name Acoustics
extends RefCounted
## How the world shapes what you hear, in the spirit of Peak and Big Walk.
## Sounds carry naturally, falling off with distance, with no blanket muffling.
## Air only takes a little treble off far sounds. A sound is muffled when
## something solid stands between you and it, and a little when it's behind
## you. Each sound takes on the space it's in: outdoors, the
## mountains throw back a dull echo, more of it the farther away the source;
## the tower's stairwell, the Command Center and the roofed side paths give a
## tight, boomy room instead.

const FAR := 35.0  # metres: beyond this, a sound comes to you mostly as echo
const BLOCKED_DB := -4.0  # extra loss when the way is blocked
const MUFFLED := {"Outdoors": "Muffled", "Outdoors Far": "Muffled Far", "Indoors": "Muffled Indoors"}

static var level: AscensionLevel


## Sets up the effect buses once, and remembers the level's enclosed spaces.
static func setup(p_level: AscensionLevel) -> void:
	level = p_level
	if AudioServer.get_bus_index("Outdoors") >= 0:
		return
	_add_bus("Outdoors", "Master", [_reverb(0.7, 0.6, 0.08, 60.0), _echo(420.0, -12.0, 2600.0)])
	_add_bus("Outdoors Far", "Master", [_reverb(0.85, 0.7, 0.22, 90.0), _echo(420.0, -8.0, 1800.0)])
	_add_bus("Indoors", "Master", [_reverb(0.45, 0.35, 0.3, 8.0)])
	# Over a ledge or round a rock outdoors loses less than through stone.
	_add_bus("Muffled", "Outdoors", [_lowpass(1600.0)])
	_add_bus("Muffled Far", "Outdoors Far", [_lowpass(1300.0)])
	_add_bus("Muffled Indoors", "Indoors", [_lowpass(900.0)])


static func _add_bus(bus: String, send: String, effects: Array) -> void:
	var i := AudioServer.bus_count
	AudioServer.add_bus(i)
	AudioServer.set_bus_name(i, bus)
	AudioServer.set_bus_send(i, send)
	for e: AudioEffect in effects:
		AudioServer.add_bus_effect(i, e)


static func _reverb(room: float, damping: float, wet: float, predelay_ms: float) -> AudioEffectReverb:
	var r := AudioEffectReverb.new()
	r.room_size = room
	r.damping = damping
	r.wet = wet
	r.dry = 1.0
	r.spread = 1.0
	r.hipass = 0.15
	r.predelay_msec = predelay_ms
	return r


## A single echo off distant rock, repeating fainter and duller each time.
static func _echo(delay_ms: float, level_db: float, lowpass_hz: float) -> AudioEffectDelay:
	var d := AudioEffectDelay.new()
	d.dry = 1.0
	d.tap1_active = false
	d.tap2_active = false
	d.feedback_active = true
	d.feedback_delay_ms = delay_ms
	d.feedback_level_db = level_db
	d.feedback_lowpass = lowpass_hz
	return d


static func _lowpass(hz: float) -> AudioEffectLowPassFilter:
	var f := AudioEffectLowPassFilter.new()
	f.cutoff_hz = hz
	return f


static func indoors(pos: Vector3) -> bool:
	if level == null:
		return false
	for box: AABB in level.indoor_boxes:
		if box.has_point(pos):
			return true
	return false


## Routes a positional sound from where the listener stands: through the
## right space, muffled if the way is blocked, duller from behind.
static func route_3d(p: AudioStreamPlayer3D, pos: Vector3, volume_db: float) -> void:
	var cam := p.get_viewport().get_camera_3d() if p.is_inside_tree() else null
	if cam == null:
		return
	var ear := cam.global_position
	var inside := indoors(pos) or indoors(ear)
	var far := ear.distance_to(pos) > FAR
	var blocked := _blocked(p, ear, pos)
	var space := "Indoors" if inside else ("Outdoors Far" if far else "Outdoors")
	p.bus = MUFFLED[space] if blocked >= 0.75 else space
	p.volume_db = volume_db + BLOCKED_DB * blocked
	# Air takes only a little treble off with distance (Godot's default muffles
	# everything past a few metres). Sounds behind you are a touch duller.
	var behind := clampf(-(pos - ear).normalized().dot(-cam.global_transform.basis.z), 0.0, 1.0)
	p.attenuation_filter_cutoff_hz = lerpf(9000.0, 3500.0, behind)
	p.attenuation_filter_db = -6.0 - 6.0 * behind
	# A head only shades the far ear; full stereo panning puts side sounds
	# entirely in one ear.
	p.panning_strength = 0.5


## Routes a non-positional sound (your own gun, your own voice) through the
## space you're standing in.
static func route_2d(p: AudioStreamPlayer) -> void:
	var cam := p.get_viewport().get_camera_3d() if p.is_inside_tree() else null
	p.bus = "Indoors" if cam and indoors(cam.global_position) else "Outdoors"


## How much of the way is blocked, 0 to 1. Sound bends round small things
## (a gun shield, a post), so four lines are tried: to the source, above it
## and to either side. Only when most are blocked is it really muffled.
static func _blocked(p: Node3D, ear: Vector3, pos: Vector3) -> float:
	var space := p.get_world_3d().direct_space_state
	var side := (pos - ear).cross(Vector3.UP).normalized() * 1.2
	var hits := 0
	for target: Vector3 in [pos, pos + Vector3(0, 1.5, 0), pos + side, pos - side]:
		var q := PhysicsRayQueryParameters3D.create(ear, target, GameConfig.LAYER_WORLD | GameConfig.LAYER_MOVING)
		var hit := space.intersect_ray(q)
		# Something solid in the way, and not just the wall the sound came from.
		if not hit.is_empty() and (hit.position as Vector3).distance_to(target) > 0.6:
			hits += 1
	return hits / 4.0
