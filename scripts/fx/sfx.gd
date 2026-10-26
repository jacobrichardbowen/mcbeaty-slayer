class_name Sfx
extends RefCounted
## Procedurally synthesized sound effects, so the prototype ships no audio
## files. Each sound is rendered once into an AudioStreamWAV and cached.

const RATE := 22050
# Halo 2 picks one of three recordings per shot, so repeats never sound canned.
const VARIANTS := {"shotgun": 3, "rifle": 3}

static var _cache := {}


static func stream(sound: String) -> AudioStreamWAV:
	if VARIANTS.has(sound):
		sound += str(randi() % int(VARIANTS[sound]))
	if _cache.has(sound):
		return _cache[sound]
	var s: PackedFloat32Array
	match sound:
		"shotgun0", "shotgun1", "shotgun2":
			s = _shotgun(int(sound.right(1)))
		"rifle0", "rifle1", "rifle2":
			s = _rifle(int(sound.right(1)))
		"bolt":
			s = _mix([_click(0.0, 0.6), _click(0.09, 0.5), _tone(520.0, 0.04, 0.01, 0.2)])
		"clip":
			s = _mix([_click(0.0, 0.7), _noise(0.12, 0.03, 2500.0, 0.3), _click(0.1, 0.6)])
		"maxim":
			s = _mix([_noise(0.22, 0.035, 2600.0, 1.0), _tone(70.0, 0.22, 0.05, 0.7)])
		"pump":
			s = _mix([_click(0.0, 0.5), _click(0.17, 0.7), _tone(320.0, 0.05, 0.015, 0.25)])
		"shell":
			s = _click(0.0, 0.5)
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
		"hurt":
			s = _mix([_tone(140.0, 0.12, 0.04, 0.5), _noise(0.1, 0.03, 1200.0, 0.4)])
		_:
			s = _click(0.0, 0.2)
	var wav := _to_wav(s)
	_cache[sound] = wav
	return wav


## Renders every sound up front so the first shots of a match don't hitch.
static func warm_up() -> void:
	for sound in ["maxim", "pump", "bolt", "clip", "shell", "dry", "swing", "melee_hit", "step", "land", "hurt"]:
		stream(sound)
	for sound: String in VARIANTS:
		for take in int(VARIANTS[sound]):
			stream(sound + str(take))


static func play_3d(parent: Node, sound: String, pos: Vector3, volume_db := 0.0, jitter := 0.06, max_dist := 160.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(sound)
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-jitter, jitter)
	p.max_distance = max_dist
	p.unit_size = 8.0
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


static func play_2d(parent: Node, sound: String, volume_db := 0.0, jitter := 0.04) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream(sound)
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-jitter, jitter)
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# --- gunshots -------------------------------------------------------------------

## Three takes of the blast: darker or brighter, boomier or tighter, and a
## different slap back off the cliffs.
static func _shotgun(take: int) -> PackedFloat32Array:
	var thump: float = [52.0, 46.0, 59.0][take]
	var bright: float = [3200.0, 2600.0, 3900.0][take]
	var tail: float = [0.11, 0.135, 0.095][take]
	var echo: float = [0.1, 0.14, 0.075][take]
	return _mix([_noise(0.9, tail, bright, 1.0), _tone(thump, 0.9, 0.16, 0.9),
		_noise(0.02, 0.004, 9000.0, 0.6), _delay(_noise(0.7, 0.22, 800.0, 0.16), echo)])


## Sharp supersonic crack, a short body, then a rolling echo off the peaks.
static func _rifle(take: int) -> PackedFloat32Array:
	var body: float = [3800.0, 3300.0, 4300.0][take]
	var thump: float = [95.0, 86.0, 104.0][take]
	var echo: float = [0.09, 0.13, 0.065][take]
	return _mix([_noise(0.03, 0.006, 9000.0, 0.9), _noise(0.25, 0.045, body, 1.0),
		_tone(thump, 0.25, 0.07, 0.7), _delay(_noise(0.9, 0.28, 900.0, 0.22), echo)])


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
