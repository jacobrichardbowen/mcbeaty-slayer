class_name SoldierAnims
extends RefCounted
## Turns the Mixamo clips into game-ready loops, once per run. Mixamo moves
## the hips across the floor, starts each cycle on a different foot and gives
## every clip its own length. Here each loop runs in place, starts as the left
## foot lands and lasts CYCLE seconds, so the run and strafes blend cleanly.
## The airborne pose is one frame of the jump.

const DIR := "res://assets/characters/soldier/"
const CHARACTER := DIR + "Soldier_White_A_v008_JBO.fbx"
## The clips were downloaded from Mixamo for an earlier version of the
## character (v005), whose hips stood this high in its own units. A new
## version only needs its own Mixamo rig: a clip is joint rotations, which
## carry over as they are, plus the hips' movement, scaled here to the new
## legs so the feet stay on the ground.
const CLIP_HIPS_HEIGHT := 1.2997
const FPS := 30.0
const CYCLE := 0.7  # seconds per gait cycle (two steps)
const HIPS := "Skeleton3D:mixamorig_Hips"
# name -> [file, loops in step with the feet]
const CLIPS := {
	"idle": ["rifle aiming idle", false],
	"run": ["rifle run", true],
	"back": ["run backwards", true],
	"strafe_l": ["strafe left", true],
	"strafe_r": ["strafe right", true],
}
const AIR_CLIP := "jump forward"
const AIR_TIME := 0.3  # the top of the leap
const AIR_DROP := 0.08  # tuck the hips a little in the air

## Metres the hips travel per cycle in each loop, in the character's own
## units, so playback can match the soldier's speed.
static var stride := {}
static var _library: AnimationLibrary
static var _rest := {}  # bone -> rest transform, from the character
static var _hip_scale := 1.0  # the character's hips height over the clips'


static func library() -> AnimationLibrary:
	if _library:
		return _library
	_read_rest()
	_library = AnimationLibrary.new()
	for name: String in CLIPS:
		var spec: Array = CLIPS[name]
		var src := _clip(spec[0])
		_library.add_animation(name, _make_loop(src, spec[1], name))
	_library.add_animation("air", _make_pose(_clip(AIR_CLIP), AIR_TIME))
	return _library


static func _clip(file: String) -> Animation:
	var lib := load(DIR + "anims/" + file + ".fbx") as AnimationLibrary
	return lib.get_animation(lib.get_animation_list()[0])


static func _read_rest() -> void:
	var scene := (load(CHARACTER) as PackedScene).instantiate()
	var sk := scene.get_node("Skeleton3D") as Skeleton3D
	for b in sk.get_bone_count():
		_rest[sk.get_bone_name(b)] = sk.get_bone_rest(b)
	_hip_scale = (_rest["mixamorig_Hips"] as Transform3D).origin.y / CLIP_HIPS_HEIGHT
	scene.free()


## Where a clip puts the hips at `t`, fitted to the character's legs.
static func _hips_at(src: Animation, track: int, t: float) -> Vector3:
	return src.position_track_interpolate(track, t) * _hip_scale


## Resamples a clip into an in-place loop. Gait loops are shifted to start as
## the left foot lands and stretched to CYCLE.
static func _make_loop(src: Animation, gait: bool, name: String) -> Animation:
	var length := src.length
	var hips := src.find_track(HIPS, Animation.TYPE_POSITION_3D)
	var p0 := _hips_at(src, hips, 0.0)
	var drift := _hips_at(src, hips, length) - p0
	drift.y = 0.0
	stride[name] = drift.length()
	var start := _left_foot_down(src) if gait else 0.0
	var out_length := CYCLE if gait else length
	var n := maxi(1, roundi(out_length * FPS))
	# Hips travel with the drift removed, then centred over the feet.
	var hips_keys: Array[Vector3] = []
	var centre := Vector3.ZERO
	for i in n:
		var t := fmod(start + length * i / n, length)
		var p := _hips_at(src, hips, t) - drift * (t / length)
		hips_keys.append(p)
		centre += Vector3(p.x, 0, p.z) / n
	var anim := Animation.new()
	anim.length = out_length
	anim.loop_mode = Animation.LOOP_LINEAR
	for track in src.get_track_count():
		var type := src.track_get_type(track)
		if type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_ROTATION_3D:
			continue
		var out := anim.add_track(type)
		anim.track_set_path(out, src.track_get_path(track))
		for i in n:
			var t := fmod(start + length * i / n, length)
			var at := out_length * i / n
			if track == hips:
				anim.position_track_insert_key(out, at, hips_keys[i] - centre)
			elif type == Animation.TYPE_POSITION_3D:
				anim.position_track_insert_key(out, at, src.position_track_interpolate(track, t))
			else:
				anim.rotation_track_insert_key(out, at, src.rotation_track_interpolate(track, t))
	return anim


## One frame of a clip as a still pose, hips over the feet.
static func _make_pose(src: Animation, time: float) -> Animation:
	var anim := Animation.new()
	anim.length = 0.1
	anim.loop_mode = Animation.LOOP_LINEAR
	var hips := src.find_track(HIPS, Animation.TYPE_POSITION_3D)
	var stand_y: float = (_rest["mixamorig_Hips"] as Transform3D).origin.y
	for track in src.get_track_count():
		var type := src.track_get_type(track)
		if type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_ROTATION_3D:
			continue
		var out := anim.add_track(type)
		anim.track_set_path(out, src.track_get_path(track))
		if track == hips:
			anim.position_track_insert_key(out, 0.0, Vector3(0, stand_y - AIR_DROP, 0))
		elif type == Animation.TYPE_POSITION_3D:
			anim.position_track_insert_key(out, 0.0, src.position_track_interpolate(track, time))
		else:
			anim.rotation_track_insert_key(out, 0.0, src.rotation_track_interpolate(track, time))
	return anim


## When the left foot is lowest in the clip, by forward kinematics.
static func _left_foot_down(src: Animation) -> float:
	var chain := ["mixamorig_Hips", "mixamorig_LeftUpLeg", "mixamorig_LeftLeg", "mixamorig_LeftFoot"]
	var best_t := 0.0
	var best_y := INF
	var t := 0.0
	while t < src.length:
		var xf := Transform3D.IDENTITY
		for bone: String in chain:
			var rest: Transform3D = _rest[bone]
			var pos := rest.origin
			var rot := rest.basis.get_rotation_quaternion()
			var pt := src.find_track("Skeleton3D:" + bone, Animation.TYPE_POSITION_3D)
			var rt := src.find_track("Skeleton3D:" + bone, Animation.TYPE_ROTATION_3D)
			if pt >= 0:
				pos = _hips_at(src, pt, t) if bone == "mixamorig_Hips" else src.position_track_interpolate(pt, t)
			if rt >= 0:
				rot = src.rotation_track_interpolate(rt, t)
			xf = xf * Transform3D(Basis(rot), pos)
		if xf.origin.y < best_y:
			best_y = xf.origin.y
			best_t = t
		t += 1.0 / FPS
	return best_t
