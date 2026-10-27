class_name Sfx
extends RefCounted
## Sound effects. Weapons, voices and the wind are recordings in
## assets/sounds (prepared by tools/prepare_sounds.py); each play picks one
## of a sound's takes at random, never the same one twice running. Small
## mechanical sounds are still synthesized once into an AudioStreamWAV.

const DIR := "res://assets/sounds/"
const RATE := 22050
# name -> takes (file names in DIR, without extension)
const RECORDED := {
	"shotgun": ["Shotgun 1", "Shotgun 2", "Shotgun 3", "Shotgun 4", "Shotgun 5"],
	"rifle": ["Pistol Heavy Shot 1", "Pistol Heavy Shot 2", "Pistol Heavy Shot 3", "Pistol Heavy Shot 4", "Pistol Heavy Shot 5"],
	"shell": ["Insert Shell 01", "Insert Shell 02", "Insert Shell 03", "Insert Shell 04"],
	"rack": ["Shotgun Reload 01", "Shotgun Reload 02", "Shotgun Reload 03"],
	"rifle_reload": ["Generic 01", "Generic 02", "Generic 03"],
	"pain": ["Grunt-Pain 01", "Grunt-Pain 02", "Grunt-Pain 03", "Grunt-Pain 04", "Grunt-Pain 05"],
	"whiz": ["Whiz 01", "Whiz 02", "Whiz 03", "Whiz 04", "Whiz 05", "Whiz 06", "Whiz 07", "Whiz 08", "Whiz 09", "Whiz 10"],
	"maxim_loop": ["Machinegun 4 Loop"],
	"maxim_end": ["Machinegun 4 Loop End"],
	"wind": ["Howling Wind and Snow"],
}

static var _cache := {}
static var _last_take := {}


static func stream(sound: String) -> AudioStream:
	if RECORDED.has(sound):
		var takes: Array = RECORDED[sound]
		var i := randi() % takes.size()
		if takes.size() > 1 and i == _last_take.get(sound, -1):
			i = (i + 1 + randi() % (takes.size() - 1)) % takes.size()
		_last_take[sound] = i
		return _recording(takes[i])
	if _cache.has(sound):
		return _cache[sound]
	var s: PackedFloat32Array
	match sound:
		"bolt":
			s = _mix([_click(0.0, 0.6), _click(0.09, 0.5), _tone(520.0, 0.04, 0.01, 0.2)])
		"dry":
			s = _click(0.0, 0.3)
		"swing":
			s = _swish(0.22)
		"melee_hit":
			s = _mix([_tone(85.0, 0.3, 0.07, 1.0), _noise(0.15, 0.03, 900.0, 0.8)])
		"step":
			s = _noise(0.07, 0.018, 700.0, 0.35)
		"land":
			s = _mix([_noise(0.15, 0.04, 500.0, 0.7), _tone(60.0, 0.15, 0.05, 0.5)])
		"teleport":
			s = _sweep(220.0, 1300.0, 0.55, 0.5)
		"pickup":
			s = _mix([_tone(880.0, 0.12, 0.05, 0.4), _delay(_tone(1320.0, 0.15, 0.06, 0.4), 0.08)])
		"mount":
			s = _mix([_tone(420.0, 0.4, 0.09, 0.4), _tone(1130.0, 0.3, 0.05, 0.3), _noise(0.08, 0.01, 4000.0, 0.4)])
		_:
			s = _click(0.0, 0.2)
	var wav := _to_wav(s)
	_cache[sound] = wav
	return wav


static func _recording(file: String) -> AudioStream:
	if not _cache.has(file):
		var path := DIR + file + ".wav"
		if not ResourceLoader.exists(path):
			path = DIR + file + ".ogg"
		_cache[file] = load(path)
	return _cache[file]


## Loads and renders everything up front so the first shots of a match don't
## hitch, and puts a limiter on the master bus so a firefight never clips.
static func warm_up() -> void:
	for sound in ["bolt", "dry", "swing", "melee_hit", "step", "land", "teleport", "pickup", "mount"]:
		stream(sound)
	for sound: String in RECORDED:
		for file: String in RECORDED[sound]:
			_recording(file)
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
			return
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, limiter)


static func play_3d(parent: Node, sound: String, pos: Vector3, volume_db := 0.0, jitter := 0.06, max_dist := 160.0,
		pitch := 1.0, unit_size := 8.0) -> AudioStreamPlayer3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(sound)
	p.volume_db = volume_db
	p.pitch_scale = pitch * (1.0 + randf_range(-jitter, jitter))
	p.max_distance = max_dist
	p.unit_size = unit_size
	parent.add_child(p)
	p.global_position = pos
	Acoustics.route_3d(p, pos, volume_db)
	p.finished.connect(p.queue_free)
	p.play()
	return p


static func play_2d(parent: Node, sound: String, volume_db := 0.0, jitter := 0.04, pitch := 1.0) -> AudioStreamPlayer:
	if parent == null or not parent.is_inside_tree():
		return null
	var p := AudioStreamPlayer.new()
	p.stream = stream(sound)
	p.volume_db = volume_db
	p.pitch_scale = pitch * (1.0 + randf_range(-jitter, jitter))
	parent.add_child(p)
	Acoustics.route_2d(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p


# --- synthesis helpers ---------------------------------------------------------

static func _noise(dur: float, tau: float, cutoff: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y += a * (randf_range(-1.0, 1.0) - y)
		out[i] = y * exp(-t / tau) * amp
	return out


static func _tone(freq: float, dur: float, tau: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * freq * t) * exp(-t / tau) * amp
	return out


static func _click(start: float, amp: float) -> PackedFloat32Array:
	var lead := int(start * RATE)
	var n := lead + int(0.04 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in range(lead, n):
		var t := float(i - lead) / RATE
		var w := randf_range(-1.0, 1.0)
		out[i] = (w - prev) * 0.5 * exp(-t / 0.006) * amp
		prev = w
	return out


static func _swish(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var k := float(i) / n
		var a := 1.0 - exp(-TAU * (300.0 + 2500.0 * k) / RATE)
		y += a * (randf_range(-1.0, 1.0) - y)
		out[i] = y * sin(PI * k) * 0.6
	return out


static func _sweep(f0: float, f1: float, dur: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var k := float(i) / n
		phase += TAU * lerpf(f0, f1, k) / RATE
		out[i] = sin(phase) * sin(PI * k) * amp * (0.7 + 0.3 * sin(TAU * 18.0 * k))
	return out


static func _delay(s: PackedFloat32Array, seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * RATE))
	out.append_array(s)
	return out


static func _mix(parts: Array) -> PackedFloat32Array:
	var n := 0
	for p in parts:
		n = maxi(n, (p as PackedFloat32Array).size())
	var out := PackedFloat32Array()
	out.resize(n)
	for p in parts:
		var arr: PackedFloat32Array = p
		for i in arr.size():
			out[i] += arr[i]
	return out


static func _to_wav(s: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.001
	for v in s:
		peak = maxf(peak, absf(v))
	var gain := 0.9 / peak
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i] * gain, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
