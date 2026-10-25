class_name BunkerControl
extends RefCounted
## Decides which team holds the gun bunker (the Big Tower).
## The holder spawns at the bunker; the other team spawns on the far side.
##
## Rules, checked every tick:
##   1. Manning the Maxim takes the bunker for your team at once.
##   2. With the gun empty, a team that outnumbers the holders inside the
##      bunker (the Big Tower: its stairwell and deck; the deck counts double)
##      captures it over CAPTURE_TIME, faster the bigger its margin. Bunker
##      spawns are outside the tower, so the holders have to come back in.
##   3. If the holders match or outnumber them, capture progress drains.
##   4. With the gun empty and the bunker empty, the last holder keeps it, so
##      the most recent team to man the gun keeps spawning there.

signal holder_changed(team: int, reason: String)

const CAPTURE_TIME := 6.0
const MAX_RATE := 2.0  # cap on how much faster a crowd captures
# Inside the tower walls below the deck, or anywhere on the deck.
const INSIDE_MIN := Vector3(-6.4, -1.0, -50.4)
const INSIDE_MAX := Vector3(6.4, 12.0, -37.6)
const DECK_MIN := Vector3(-8.0, 12.0, -52.0)
const DECK_MAX := Vector3(8.0, 18.0, -34.0)

var holder := -1
var challenger := -1
var progress := 0.0  # 0..1 toward the challenger taking the bunker
var presence: Array[float] = [0.0, 0.0]
var last_gunner_team := -1


func _init(start_team: int) -> void:
	holder = start_team


## How much a soldier at pos counts toward holding the bunker.
static func weight(pos: Vector3) -> float:
	if _inside(pos, DECK_MIN, DECK_MAX):
		return 2.0
	return 1.0 if _inside(pos, INSIDE_MIN, INSIDE_MAX) else 0.0


static func _inside(p: Vector3, lo: Vector3, hi: Vector3) -> bool:
	return p.x >= lo.x and p.x <= hi.x and p.y >= lo.y and p.y <= hi.y and p.z >= lo.z and p.z <= hi.z


func update(delta: float, soldiers: Array[Soldier], gunner: Soldier) -> void:
	presence = [0.0, 0.0]
	for s in soldiers:
		if s.alive:
			presence[s.team] += weight(s.global_position)

	if gunner:
		last_gunner_team = gunner.team
		challenger = -1
		progress = 0.0
		_set_holder(gunner.team, "manned the Maxim")
		return

	if holder < 0:
		# Nobody has held it yet: the team with more soldiers inside claims it.
		var lead := 0 if presence[0] > presence[1] else (1 if presence[1] > presence[0] else -1)
		_advance(lead, presence[lead] - presence[1 - lead] if lead >= 0 else 0.0, delta)
		return

	var other := 1 - holder
	var margin := presence[other] - presence[holder]
	if margin <= 0.0:
		# Defended, held off, or empty: any capture in progress drains away.
		progress = maxf(0.0, progress - delta / CAPTURE_TIME * (2.0 if presence[holder] > 0.0 else 1.0))
		if progress <= 0.0:
			challenger = -1
		return
	_advance(other, margin, delta)


func _advance(team: int, strength: float, delta: float) -> void:
	if team < 0 or strength <= 0.0:
		progress = maxf(0.0, progress - delta / CAPTURE_TIME)
		return
	if challenger != team:
		challenger = team
		progress = 0.0
	progress += delta * minf(1.0 + 0.25 * (strength - 1.0), MAX_RATE) / CAPTURE_TIME
	if progress >= 1.0:
		challenger = -1
		progress = 0.0
		_set_holder(team, "took the bunker")


func _set_holder(team: int, reason: String) -> void:
	if team == holder:
		return
	holder = team
	holder_changed.emit(team, reason)
