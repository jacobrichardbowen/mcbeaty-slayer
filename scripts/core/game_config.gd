class_name GameConfig
extends RefCounted
## Every tuning number for the Tower of Power prototype lives here.
## Units are meters, seconds and degrees. The values aim for the feel of
## Halo 2 multiplayer with shields off: fast strafing, floaty jumps, one-hit
## melee, and a shotgun that kills in one blast up close.

# --- Teams -------------------------------------------------------------------
const TEAM_WHITE := 0
const TEAM_RED := 1
const TEAM_NAMES := ["Whites", "Reds"]
const TEAM_COLORS := [Color(0.94, 0.94, 0.9), Color(0.92, 0.2, 0.15)]
const MAX_PER_TEAM := 16
const WHITE_NAMES := ["Kolchak", "Denikin", "Wrangel", "Yudenich", "Kornilov", "Kappel", "Alekseev", "Krasnov",
	"Semyonov", "Markov", "Drozdovsky", "Kutepov", "Shkuro", "Mamontov", "Dutov", "Pepelyayev"]
const RED_NAMES := ["Chapaev", "Budyonny", "Frunze", "Kotovsky", "Voroshilov", "Blyukher", "Shchors", "Tukhachevsky",
	"Yegorov", "Uborevich", "Yakir", "Dybenko", "Primakov", "Mironov", "Kork", "Vatsetis"]

# --- Physics layers ----------------------------------------------------------
const LAYER_WORLD := 1
const LAYER_SOLDIER := 2
const LAYER_PICKUP := 4
const LAYER_MOVING := 8
const LAYER_DEBRIS := 16  # ragdolls: hit the level, never soldiers or shots
const MASK_SHOT := LAYER_WORLD | LAYER_SOLDIER | LAYER_MOVING
const MASK_SIGHT := LAYER_WORLD | LAYER_MOVING

# --- Soldier (no shields: health is all you get) -----------------------------
const MAX_HEALTH := 100.0
const HEALTH_REGEN_DELAY := 6.0
const HEALTH_REGEN_RATE := 25.0
const STAND_HEIGHT := 1.9
const CROUCH_HEIGHT := 1.3
const STAND_EYE := 1.72
const CROUCH_EYE := 1.12
const RADIUS := 0.38
# Partway to Halo 2 (6.86 m/s forward, 6.10 sideways/back, ~2.4 m jump).
const RUN_SPEED := 6.6  # forward
const STRAFE_SPEED := 6.2  # sideways and backwards
const CROUCH_SPEED := 3.0
const GROUND_ACCEL := 70.0
const GROUND_DECEL := 55.0
const AIR_ACCEL := 22.0
const GRAVITY := 17.0
const JUMP_VELOCITY := 7.82  # ~1.8 m jump, ~0.46 s to apex
const FALL_DAMAGE_MIN_SPEED := 19.0  # ~10.6 m drop
const FALL_DAMAGE_LETHAL_SPEED := 29.5  # ~25.6 m drop
const KILL_Y := -40.0
const RESPAWN_TIME := 5.0

# --- Melee: with shields off a Halo 2 melee is a kill --------------------------
const MELEE_DAMAGE := 200.0
const MELEE_RANGE := 1.9
const MELEE_LUNGE_RANGE := 3.6
const MELEE_LUNGE_CONE := 22.0
const MELEE_LUNGE_SPEED := 15.0
const MELEE_COOLDOWN := 0.85

# --- Shotgun: Halo 2's M90 (wiki tag data, see reports/) -----------------------
# 10 pellets of 16.5 against 45 health with shields off, so 3 pellets kill.
# Scaled here to 100 health. Full damage to 5 world units (15.2 m), fading
# linearly to 5/16.5 at the 8 wu (24.4 m) cut-off, nothing beyond.
const SG_MAG := 12
const SG_START_RESERVE := 36
const SG_MAX_RESERVE := 48
const SG_PELLETS := 10
# Cone half-angle, pellets even over the cone's area. Halo 2 says 10 degrees, but
# a Spartan is a broader target than our soldiers; 8 reproduces its one-shot odds
# (sure to ~5 m, ~90% at 6 m, coin flip at 9 m, rare lucky kills at 12-15 m).
const SG_SPREAD := 8.0
const SG_PELLET_DAMAGE := 16.5 / 45.0 * 100.0
const SG_FALLOFF_START := 15.2
const SG_FALLOFF_END := 24.4
const SG_FALLOFF_MIN := 5.0 / 16.5
const SG_RANGE := 24.4
const SG_FIRE_INTERVAL := 1.0  # Halo 2: one shot a second
const SG_RELOAD_START := 0.35
const SG_RELOAD_SHELL := 0.6  # Halo 2: about 0.6 s a shell
const SG_RELOAD_END := 0.38
const SG_AUTOAIM_RANGE := 10.0  # red reticle distance
const SG_CRATE := 12  # shells per ammo crate

# --- Mosin-Nagant (semi-auto for the prototype) -------------------------------
const RF_MAG := 5  # one stripper clip
const RF_START_RESERVE := 25
const RF_MAX_RESERVE := 40
const RF_CRATE := 10
const RF_DAMAGE := 55.0  # two body shots kill
const RF_HEADSHOT_MULT := 2.5  # one headshot kills
const RF_FALLOFF_START := 45.0
const RF_FALLOFF_END := 150.0
const RF_FALLOFF_MIN := 0.7
const RF_RANGE := 200.0
const RF_FIRE_INTERVAL := 0.42
const RF_RELOAD_START := 0.35
const RF_RELOAD_CLIP := 1.3
const RF_RELOAD_END := 0.4
const RF_SPREAD := 0.25  # standing still
const RF_MOVE_SPREAD := 1.0  # added at full run speed
const RF_AIR_SPREAD := 2.5
const RF_BLOOM_PER_SHOT := 0.8
const RF_BLOOM_MAX := 3.0
const RF_BLOOM_RECOVERY := 2.5  # degrees per second
const RF_CROUCH_MULT := 0.6
const RF_ZOOM := 2.0
const RF_ZOOM_SPREAD_MULT := 0.5
const RF_AUTOAIM_RANGE := 45.0
const RF_WHIZ_RADIUS := 3.0  # rounds passing this close to your head whiz by
const HEAD_HEIGHT := 0.32  # top of the body that counts as head

# --- Maxim gun on the Big Tower ----------------------------------------------
# The burst is a recorded loop played pitched down for weight; firing keeps
# time with its shots (7 in 0.5747 s), 585 rounds a minute at this pitch.
const MG_PITCH := 0.8
const MG_FIRE_INTERVAL := 0.5747 / 7.0 / MG_PITCH
const MG_VOLUME := 4.0  # dB, louder than the hand guns
const MG_DAMAGE := 24.0
const MG_SPREAD := 0.7
const MG_RANGE := 160.0
const MG_YAW_LIMIT := 72.0
const MG_PITCH_MIN := -55.0
const MG_PITCH_MAX := 22.0
const MG_TURN_RATE := 200.0
const MG_MOUNT_HOLD := 0.25
const MG_MOUNT_RANGE := 2.2
const MG_AUTOAIM_RANGE := 90.0

# --- Ragdolls: bodies thrown along the killing shot (m/s) ------------------------
const FLING_SHOTGUN_MIN := 4.0  # a 3-pellet kill
const FLING_SHOTGUN_MAX := 11.0  # all 10 pellets point blank
const FLING_RIFLE := 3.5
const FLING_HEADSHOT := 4.5
const FLING_MAXIM := 4.5
const FLING_MELEE := 5.0
const FLING_LIFT := 0.35  # extra upward throw, as a share of the fling
const RAGDOLL_LIFETIME := 10.0
const RAGDOLL_MAX := 12  # oldest bodies vanish first

# --- Sound -------------------------------------------------------------------
const WIND_VOLUME := -13.0  # dB: audible in lulls, well under the gunfire

# --- Match ---------------------------------------------------------------------
const TIME_LIMIT := 15.0 * 60.0
const MULTIKILL_WINDOW := 4.5
const FRIENDLY_FIRE := true

# --- Bots ----------------------------------------------------------------------
const BOT_REACTION := 0.35
const BOT_AIM_ERROR := 5.0
const BOT_TURN_RATE := 300.0
const BOT_VIEW_RANGE := 70.0  # on the Maxim
const BOT_ENGAGE_RANGE := 16.0  # on foot; farther enemies are left alone
const BOT_RALLY_SIZE := 4  # attackers regroup into groups this big before storming
const BOT_RALLY_MAX_WAIT := 12.0
const BOT_TURRET_REACTION := 0.6
const BOT_TURRET_AIM_ERROR := 2.4

# --- Player-adjustable settings (main menu / pause menu) ------------------------
const SENSITIVITY_MIN := 0.02
const SENSITIVITY_MAX := 0.28
const FOV_MIN := 60.0
const FOV_MAX := 110.0
static var mouse_sensitivity := 0.088  # degrees per pixel
static var pad_look_speed := 150.0  # degrees per second at full stick
static var invert_y := false
static var fov := 78.0  # degrees across a 16:9 screen (Halo 2's 70 was across a 4:3 TV)
static var red_bots := 4
static var white_bots := 0
static var bunker_start := -1  # -1: nobody (fight for it), else the team that starts with it
static var player_loadout := "shotgun"
static var score_limit := 50
static var player_name := "Player"  # shown to others online


## Godot's camera angle (vertical) for `fov` across a 16:9 screen. Wider
## screens see more at the sides and narrower ones less, at the same height.
static func vertical_fov() -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(fov) * 0.5) * 9.0 / 16.0))
