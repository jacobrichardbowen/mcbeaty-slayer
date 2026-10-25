class_name Hud
extends CanvasLayer
## Halo 2-flavoured HUD drawn with immediate-mode calls: shell counter (top
## left), health meter where the shield bar would be (top right), motion
## tracker (bottom left), team scores (bottom right), red reticle, kill feed
## and announcer text.

const BLUE := Color(0.55, 0.85, 1.0, 0.92)
const DIM := Color(0.55, 0.85, 1.0, 0.32)
const RED := Color(1.0, 0.2, 0.15, 0.95)
const TRACKER_RANGE := 25.0

var game: Game
var killed_by := ""

var _canvas: Control
var _feed: Array[Dictionary] = []
var _announce := ""
var _announce_t := 0.0
var _end_text := ""
var _clock := 0.0


func _ready() -> void:
	layer = 5
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_canvas.draw.connect(_draw_hud)


func feed(text: String, color := Color.WHITE) -> void:
	_feed.append({"text": text, "color": color, "t": _clock})
	while _feed.size() > 6:
		_feed.pop_front()


func announce(text: String) -> void:
	_announce = text
	_announce_t = 2.6


func show_end(text: String) -> void:
	_end_text = text


func _process(delta: float) -> void:
	_clock += delta
	_announce_t -= delta
	while not _feed.is_empty() and _clock - float(_feed[0]["t"]) > 7.0:
		_feed.pop_front()
	_canvas.queue_redraw()


# --- Drawing --------------------------------------------------------------------------

func _text(pos: Vector2, text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var f := ThemeDB.fallback_font
	_canvas.draw_string_outline(f, pos, text, align, width, size, 5, Color(0, 0, 0, 0.6 * color.a))
	_canvas.draw_string(f, pos, text, align, width, size, color)


func _draw_hud() -> void:
	var p := game.player
	var pc := game.player_ctrl
	if p == null or pc == null:
		return
	var sz := _canvas.size
	if pc.damage_flash > 0.0:
		_canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.75, 0.0, 0.0, 0.3 * pc.damage_flash))
	if p.alive and p.health < 35.0:
		_canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.6, 0.0, 0.0, 0.08 + 0.06 * sin(_clock * 6.0)))
	if p.alive:
		_draw_crosshair(sz, pc)
		_draw_ammo(p)
		_draw_health(sz, p)
		_draw_prompt(sz, p)
	_draw_tracker(sz, p)
	_draw_scores(sz, p)
	_draw_feed(sz)
	_draw_status(sz)
	if _announce_t > 0.0:
		var a := clampf(_announce_t / 0.6, 0.0, 1.0)
		_text(Vector2(0, sz.y * 0.3), _announce, 44, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	if not p.alive and not game.over:
		var line := "Killed by %s" % killed_by if killed_by != "" else "You died"
		_text(Vector2(0, sz.y * 0.62), line, 26, BLUE, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
		var respawn := "Respawn in %d" % ceili(game.respawn_left(p))
		_text(Vector2(0, sz.y * 0.62 + 36), respawn, 20, DIM, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	if Input.is_action_pressed("scoreboard") or game.over:
		_draw_scoreboard(sz, p)
	if _end_text != "":
		_text(Vector2(0, sz.y * 0.22), _end_text, 64, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, sz.x)


func _draw_crosshair(sz: Vector2, pc: PlayerController) -> void:
	var c := sz * 0.5
	var col := RED if pc.red_reticle else BLUE
	if game.player.turret:
		_canvas.draw_arc(c, 9.0, 0.0, TAU, 24, col, 2.0)
		for i in 4:
			var d := Vector2.RIGHT.rotated(i * PI * 0.5)
			_canvas.draw_line(c + d * 14.0, c + d * 24.0, col, 2.0)
	else:
		_canvas.draw_arc(c, 26.0, 0.0, TAU, 48, col, 2.0)
		_canvas.draw_circle(c, 2.0, col)
		for i in 4:
			var d := Vector2.RIGHT.rotated(i * PI * 0.5 + PI * 0.25)
			_canvas.draw_line(c + d * 20.0, c + d * 30.0, col, 2.0)
	if pc.aim_target:
		var tc: Color = GameConfig.TEAM_COLORS[pc.aim_target.team]
		_text(Vector2(0, c.y + 58.0), pc.aim_target.display_name, 18, tc, HORIZONTAL_ALIGNMENT_CENTER, sz.x)


func _draw_ammo(p: Soldier) -> void:
	var x0 := 28.0
	var y0 := 26.0
	if p.turret:
		_text(Vector2(x0, y0 + 20), "MAXIM M1910", 22, BLUE)
		_text(Vector2(x0, y0 + 46), "Belt-fed  /  hold E to dismount", 14, DIM)
		return
	var w := p.weapon
	for i in GameConfig.SG_MAG:
		var r := Rect2(x0 + i * 12.0, y0, 8.0, 22.0)
		if i < w.mag:
			_canvas.draw_rect(r, BLUE)
		else:
			_canvas.draw_rect(r, DIM, false, 1.5)
	_text(Vector2(x0, y0 + 52), str(w.reserve), 24, BLUE)
	_text(Vector2(x0 + 48, y0 + 50), "SHOTGUN", 13, DIM)
	if w.mag == 0 and w.reserve == 0:
		_text(Vector2(x0, y0 + 76), "NO AMMO", 16, RED)
	elif w.is_reloading():
		_text(Vector2(x0, y0 + 76), "RELOADING", 14, DIM)


func _draw_health(sz: Vector2, p: Soldier) -> void:
	var wbar := 260.0
	var x := sz.x - wbar - 28.0
	var y := 28.0
	var frac := clampf(p.health / GameConfig.MAX_HEALTH, 0.0, 1.0)
	var col := BLUE if frac > 0.35 else RED
	var seg := wbar / 10.0
	for i in 10:
		var fill := clampf(frac * 10.0 - i, 0.0, 1.0)
		var r := Rect2(x + i * seg, y, seg - 3.0, 16.0)
		_canvas.draw_rect(r, DIM, false, 1.0)
		if fill > 0.0:
			_canvas.draw_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), col)
	_text(Vector2(x, y + 36), "HEALTH  -  SHIELDS OFF", 13, DIM)


func _draw_prompt(sz: Vector2, p: Soldier) -> void:
	var text := ""
	if p.turret == null and game.turret.can_mount(p):
		text = "Hold E (or X) to man the Maxim"
	if text != "":
		_text(Vector2(0, sz.y * 0.7), text, 20, BLUE, HORIZONTAL_ALIGNMENT_CENTER, sz.x)


func _draw_tracker(sz: Vector2, p: Soldier) -> void:
	var rad := 86.0
	var ctr := Vector2(28.0 + rad, sz.y - 28.0 - rad)
	_canvas.draw_circle(ctr, rad, Color(0.02, 0.08, 0.14, 0.5))
	_canvas.draw_arc(ctr, rad, 0.0, TAU, 64, BLUE, 2.0)
	_canvas.draw_arc(ctr, rad * 0.5, 0.0, TAU, 48, DIM, 1.0)
	_canvas.draw_line(ctr - Vector2(rad, 0), ctr + Vector2(rad, 0), DIM, 1.0)
	_canvas.draw_line(ctr - Vector2(0, rad), ctr + Vector2(0, rad), DIM, 1.0)
	_canvas.draw_colored_polygon(PackedVector2Array([ctr + Vector2(0, -7), ctr + Vector2(5, 5), ctr + Vector2(-5, 5)]), BLUE)
	_text(ctr + Vector2(rad - 26.0, rad + 2.0), "25m", 12, DIM)
	var yaw := p.look_yaw
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	for o in game.soldiers:
		if o == p or not o.alive:
			continue
		var friendly := o.team == p.team
		if not friendly and not o.shows_on_tracker():
			continue
		var rel := o.global_position - p.global_position
		var local := Vector2(rel.dot(right), -rel.dot(fwd))
		if local.length() > TRACKER_RANGE:
			continue
		var col := Color(1.0, 0.85, 0.2) if friendly else Color(1.0, 0.2, 0.15)
		_canvas.draw_circle(ctr + local / TRACKER_RANGE * rad, 6.0 if absf(rel.y) < 3.0 else 4.0, col)


func _draw_scores(sz: Vector2, p: Soldier) -> void:
	var x := sz.x - 268.0
	var y := sz.y - 112.0
	var secs := int(maxf(game.time_left, 0.0))
	_text(Vector2(x, y - 12.0), "%d:%02d" % [secs / 60, secs % 60], 18, DIM)
	_text(Vector2(x + 90.0, y - 12.0), "to %d" % GameConfig.score_limit, 14, DIM)
	var order := [p.team, 1 - p.team]
	for i in 2:
		var t: int = order[i]
		var tc: Color = GameConfig.TEAM_COLORS[t]
		var r := Rect2(x, y + i * 42.0, 240.0, 34.0)
		_canvas.draw_rect(r, Color(tc.r, tc.g, tc.b, 0.18 if i == 0 else 0.1))
		var frac := clampf(float(game.scores[t]) / GameConfig.score_limit, 0.0, 1.0)
		_canvas.draw_rect(Rect2(r.position, Vector2(r.size.x * frac, r.size.y)), Color(tc.r, tc.g, tc.b, 0.35))
		if i == 0:
			_canvas.draw_rect(r, tc, false, 1.5)
		_text(r.position + Vector2(10, 24), GameConfig.TEAM_NAMES[t], 18, tc)
		_text(r.position + Vector2(0, 25), str(game.scores[t]), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 10.0)


func _draw_feed(sz: Vector2) -> void:
	var y := sz.y - 230.0
	for i in range(_feed.size() - 1, -1, -1):
		var e := _feed[i]
		var age := _clock - float(e["t"])
		var col: Color = e["color"]
		col.a = clampf(7.0 - age, 0.0, 1.0)
		_text(Vector2(28, y), e["text"], 17, col)
		y -= 24.0


func _draw_status(sz: Vector2) -> void:
	var b := game.bunker
	var text := "BUNKER: NOBODY"
	var col := DIM
	if b.holder >= 0:
		text = "BUNKER: %s" % GameConfig.TEAM_NAMES[b.holder].to_upper()
		col = GameConfig.TEAM_COLORS[b.holder]
	text += "   ·   MAXIM MANNED" if game.turret.gunner else "   ·   MAXIM EMPTY"
	_text(Vector2(0, 32), text, 16, col, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	if b.challenger >= 0 and b.progress > 0.0:
		var cc: Color = GameConfig.TEAM_COLORS[b.challenger]
		var r := Rect2((sz.x - 240.0) * 0.5, 44.0, 240.0, 8.0)
		_canvas.draw_rect(r, DIM, false, 1.0)
		_canvas.draw_rect(Rect2(r.position, Vector2(r.size.x * b.progress, r.size.y)), cc)
		_text(Vector2(0, 72), "%s TAKING THE BUNKER" % GameConfig.TEAM_NAMES[b.challenger].to_upper(), 13, cc, HORIZONTAL_ALIGNMENT_CENTER, sz.x)


## Two columns, your team on the left; fits 16 a side.
func _draw_scoreboard(sz: Vector2, p: Soldier) -> void:
	var col_w := 330.0
	var gap := 20.0
	var row_h := 22.0
	var h := 70.0 + GameConfig.MAX_PER_TEAM * row_h
	var pos := Vector2((sz.x - col_w * 2.0 - gap) * 0.5, maxf(90.0, (sz.y - h) * 0.5))
	for i in 2:
		var t: int = [p.team, 1 - p.team][i]
		var tc: Color = GameConfig.TEAM_COLORS[t]
		var o := pos + Vector2(i * (col_w + gap), 0)
		_canvas.draw_rect(Rect2(o, Vector2(col_w, h)), Color(0.02, 0.06, 0.1, 0.82))
		_canvas.draw_rect(Rect2(o, Vector2(col_w, h)), Color(tc.r, tc.g, tc.b, 0.6), false, 1.0)
		_text(o + Vector2(14, 28), GameConfig.TEAM_NAMES[t], 20, tc)
		_text(o + Vector2(0, 28), str(game.scores[t]), 20, tc, HORIZONTAL_ALIGNMENT_RIGHT, col_w - 14.0)
		_text(o + Vector2(14, 52), "NAME", 12, DIM)
		_text(o + Vector2(220, 52), "KILLS", 12, DIM)
		_text(o + Vector2(272, 52), "DEATHS", 12, DIM)
		var team_list := game.soldiers.filter(func(s: Soldier) -> bool: return s.team == t)
		team_list.sort_custom(func(a: Soldier, b: Soldier) -> bool: return a.kills > b.kills)
		var y := o.y + 74.0
		for s in team_list:
			var sc := Color.WHITE if s == p else Color(0.82, 0.82, 0.82, 1.0 if s.alive else 0.55)
			_text(Vector2(o.x + 14, y), s.display_name, 15, sc)
			_text(Vector2(o.x + 220, y), str(s.kills), 15, sc)
			_text(Vector2(o.x + 272, y), str(s.deaths), 15, sc)
			y += row_h
