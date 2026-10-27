# Tower of Power

A Godot 4 prototype that tries to recreate the feel of Halo 2 multiplayer
and the community gametype **Tower of Power** on **Ascension**. Two teams
fight over one machine gun at the top of the Big Tower. Whoever holds the gun
controls most of the map, so the other team has to storm the tower along the
side paths.

Teams are loosely Russian Civil War, **Whites** against **Reds**. Both teams
use the same custom soldier character, animated with Mixamo clips; the Reds'
white wool is dyed red. The turret is a Maxim M1910 on a wheeled Sokolov
mount. The map and the guns are still crude primitives.

![The Big Tower's Maxim looking over the dish](docs/maxim_view.jpg)

| | |
|---|---|
| ![Overview](docs/overview.jpg) | ![Whites vs Reds](docs/whites_vs_reds.jpg) |

## Playing it

You don't need Godot to play. Download the latest build (`TowerOfPower_v005.exe`) and double-click
it. The whole game is packed inside that one file, and nothing gets installed.

The game opens fullscreen on the lobby. Press **Enter** (or click **Deploy**)
to play. F11 switches between fullscreen and a window. Esc pauses and has
**Quit game**.

**The first launch asks for approval once**, because the build isn't signed
with a paid code-signing certificate. Windows shows "Windows protected your
PC": click **More info**, then **Run anyway**. After that it opens with a
normal double-click.

### Making new builds

With Godot 4.3 and its export templates installed, `tools/build.sh` exports
the Windows build into `build/` as `TowerOfPower_v005.exe`. The number comes
from `config/version` in `project.godot`; bump it for each new build. The Mac
and Linux presets are still there: `tools/build.sh Windows macOS Linux` builds
all three.

### Running from the editor

Install **Godot 4.3** (the standard build, not .NET), choose **Import**,
select `project.godot`, and press **F5**. From a terminal, `godot --path .`
runs it, and `godot --path . -- --autostart` skips the lobby.

### Lobby options

- **Bunker starts with**: nobody (the default: both teams start on neutral
  ground and race for it), your team, or the Reds.
- **Your weapon**: the shotgun or the Mosin-Nagant rifle. You can change it on
  the death screen while you wait to respawn.
- **Red bots** (1–16) and **White bots** (your side, 0–15): up to 16 a side.
- **Score limit**: the 2004 variant used 250. The default here is 50.
- Mouse sensitivity, field of view (Halo 2's is 70° horizontal at 4:3), and
  invert look.

### Controls

| Action | Mouse / keyboard | Gamepad (Halo 2 layout) |
|---|---|---|
| Move / look | WASD / mouse | Left / right stick |
| Fire | Left click | RT |
| Jump | Space | A |
| Melee | F, V or middle click | B |
| Reload | R | X |
| Man / leave the Maxim | Hold E | Hold X |
| Zoom (rifle) | Right click | R3 |
| Pick respawn weapon (while dead) | Q, mouse wheel, 1 or 2 | Y |
| Crouch (hides you from the motion tracker) | Ctrl or C | L3 |
| Scoreboard | Tab | Back |
| Pause | Esc | Start |

## The gametype

The rules follow the original 2004 recipe as people remember it: team slayer,
shotgun only, no grenades, no vehicles, **no shields**, and one machine gun
turret placed in one of the towers.

- **Shields off**: 100 health, which slowly regenerates after 6 s without
  taking damage. One melee kills.
- **Shotgun**: Halo 2's own numbers. 12 shells and 10 pellets, and any 3
  pellets kill. The spread is wide, so a shot is a sure kill to about 5 m,
  90% at 6 m, a coin flip at 9 m, and only the odd lucky kill at 12–15 m.
  Pellets lose damage past 15 m and stop at 24 m. One shot a second, and a
  shell-by-shell reload at 0.6 s a shell that you can cancel by firing. The red reticle comes on within 10 m, and the ring
  on screen shows the real spread.
- **Mosin-Nagant** (prototype): semi-automatic, one round per trigger pull,
  5-round stripper clip, about 0.4 s between shots. Two body shots kill, one
  headshot kills. One tight round instead of a pellet spray: a quarter of a
  degree when standing still, growing when you fire fast, move or jump, and
  halved when zoomed. Right click / R3 zooms 2x like Halo 2's Battle Rifle;
  taking damage knocks you out of zoom.
- **Maxim**: 585 rounds/min, infinite belt, 72° traverse either side, from
  22° up to 55° down. Third-person camera while you're on it, as with Halo 2
  vehicles. The gunner stays exposed from the sides and from the stairwell
  that comes out right behind them.
- **Movement**: partway to Halo 2. You run 6.6 m/s forwards and 6.2 sideways
  or backwards (Halo 2: 6.9 and 6.1), and jump about 1.8 m (Halo 2: 2.4).
- **Deaths**: bodies go limp and are thrown along the killing shot, hardest by
  a point-blank shotgun blast, much as Havok did in Halo 2. The death camera
  follows the body.
- Melee lunge, crouch-jumping, fall damage, a 5 s respawn, kill feed, Halo 2
  multi-kill and spree callouts, and a motion tracker (25 m; it shows enemies
  only while they move upright or fire).

Every number is in [`scripts/core/game_config.gd`](scripts/core/game_config.gd)
if you want to tune the feel.

### The bunker decides where you spawn

A match starts with the bunker **up for grabs**. Whites start on the west side
(Sniper Roost and west island) and Reds on the east (Landing Pad, Command
Center and east island), the same distance from the tower. After that, the
team holding the **gun bunker** (the Big Tower) spawns around it. The other
team spawns on the far side of the map: the south edge of the island, the
Sniper Roost and the Landing Pad. Who holds it, checked every moment:

1. **Whoever is manning the Maxim** holds the bunker, at once.
2. **Gun empty**: if one team outnumbers the holders *inside* the tower (its
   stairwell and deck, with the deck counting double), it takes the bunker
   over 6 seconds. A bigger margin captures faster, up to twice as fast.
3. If the holders match or outnumber them inside, the capture drains away.
4. **Gun empty and tower empty**: the last holder keeps it, so the last team
   to man the gun keeps spawning there.

The bunker spawns sit outside the tower, so holders have to come back in to
defend it. The top of the screen shows who holds the bunker, whether the gun
is manned, and a bar while someone is taking it over.

## The map

The Ascension here is a **hand-built blockout**. I couldn't download the
Halo 2 Vista map files from gruntmods.com: the sandbox this was built in blocks
that site. Instead, the layout follows how the community describes the
original. It has a rocky central island with a dish inset in the ground, and a
rotating antenna that periodically blocks sightlines. Three platforms branch
off it: the Big Tower, the Sniper Roost (the Little Tower with its "fork
prongs"), and the Landing Pad. The Leap of Faith ledge has a teleporter back up.
The Command Center has a walkable roof.

Tower of Power changes the layout in a few places:

- The Maxim sits at the front of the Big Tower deck and covers the island, the
  dish and the centre bridge.
- **West side path**: drops below the island rim and runs under a solid roof
  to the tower's flank, outside the gun's arc. This is the safe route.
- **East side path**: the same, but with two windows the gunner can shoot
  through.
- **Big Tower interior**: a square spiral of four ramps. You come out through
  a hole in the deck just behind the gunner. Murder-hole windows on each
  flight let defenders shoot down at the side paths.

Bots navigate a navmesh baked at startup from the level's collision. Swapping
in real geometry later should be close to drop-in: provide meshes and
colliders, spawn points, routes and the turret transform the way
[`scripts/level/ascension.gd`](scripts/level/ascension.gd) does.

## Sound

Weapons, voices and the wind are recordings, in
[`assets/sounds/`](assets/sounds/). Each play picks one of a sound's takes at
random, never the same take twice running.

| Sound | Plays when |
|---|---|
| Shotgun 1–5 | the shotgun fires |
| Shotgun Reload 01–03 | a shotgun reload finishes; quieter, as the pump after each shot |
| Insert Shell 01–04 | each shell goes into the shotgun |
| Pistol Heavy Shot 1–5 | the Mosin fires |
| Generic 01–03 | the Mosin reloads (one take covers the whole reload) |
| Whiz 01–10 | a Mosin round passes within 3 m of your head without hitting you |
| Grunt-Pain 01–05 | a soldier is hurt (at most every 0.6 s) or killed |
| Machinegun 4 Loop / Loop End | the Maxim fires a burst / stops firing |
| Howling Wind and Snow | all match long, under everything else |

The Maxim plays one seamless loop, pitched down to 0.8 for weight and turned
up above the hand guns. The gun fires in time with the loop's recorded shots
(585 rounds a minute at that pitch). Letting go waits for the next beat, then
plays the last round and its echo. The loop as uploaded dropped to silence for
about 30 ms at each repeat. Here it is rebuilt from its seven middle shots, with
both ends cut just before a shot and crossfaded.

[`tools/prepare_sounds.py`](tools/prepare_sounds.py) made these files from the
uploaded originals (kept on the `godot-scaffold` branch). It converts them to
mono, so they pan in 3D, and trims the dead air before each sound, which takes
up to 55 ms of lag off the gunshots. It also rebuilds the Maxim loop, trims the
end-of-burst file to its final shot, and turns the first 110 s of the wind into
a seamless, gently compressed Ogg loop. It needs `ffmpeg` and Python with
numpy. A master-bus limiter keeps big firefights from clipping. Footsteps,
melee and other small mechanical sounds are still synthesized in code.

The wind is "Howling wind and snow" by Dragon Studio.

## The soldier character

The soldiers are `Soldier_White_A_v005_JBO.fbx`, rigged with Mixamo's
skeleton, in [`assets/characters/soldier/`](assets/characters/soldier/). Godot
imports the FBX files directly. From the Mixamo Shooter Pack the game uses six
clips, in `anims/` there:

| Clip | Used for |
|---|---|
| rifle aiming idle | standing, and the upper body at all times so the gun stays up |
| rifle run | running forwards |
| run backwards | backpedalling |
| strafe left / strafe right | sidestepping (renamed from `strafe (2)` and `strafe`) |
| jump forward | one frame, the top of the leap, held while airborne |

At load the clips are made to run in place, loop cleanly and share one cycle
length and starting foot, so they blend by direction. Playback speeds up to
match how fast the soldier is moving. After the clips play, the spine turns
so the gun (placed between the hands) points exactly where the soldier aims.
The pack has no crouch clips, so crouching lowers the hips and bends the knees
to keep the feet where the clip put them. Mixamo crouch clips would look
better if you want to add them later.

On death, a copy of the character takes the soldier's last pose. Ten capsules
(torso, head, upper arms, forearms, thighs, shins) then move its bones. Knees
and elbows are hinges, so they only bend the natural way.

To update the character, replace the FBX with a new export under the same
name. It has to keep the Mixamo rig, and the Reds' dye looks for a material
whose name starts with `White Wool`.

## Bots

The bots are deliberately rudimentary. They fight enemies within about 16 m
and otherwise work the objective:

- **Gun empty**: the two teammates nearest the seat race to man it.
- **Attacking**: they take the west, east or centre route and regroup in
  fours at the end of it before storming the tower.
- **Holding the bunker**: a third of the team guards the tower; the rest hunt
  on the island.

On the gun they sweep its arc, fire in bursts, and hop off when someone flanks
them. Left to themselves at 8 or 16 a side, the holders usually keep the
bunker once they've dug in. That fits Tower of Power's reputation, but it means
taking the gun yourself is the surest way to flip it.

## Tests

Headless checks, run from the project folder (they need the class cache, so
run `godot --headless --path . --import` once first):

```
# Weapons (shotgun and rifle), ragdolls, melee, jump height, fall damage, the
# turret's arc and lethality, the neutral start, every bunker-control and
# spawn rule, and that the character's gun points where it aims
godot --headless --path . --fixed-fps 60 -s tests/mechanics_test.gd

# A 300 s bot match: navmesh connectivity, a bot mans the Maxim, kills happen,
# and every respawn lands on the side its team is entitled to
godot --headless --path . --fixed-fps 60 -s tests/smoke_test.gd -- reds=16 whites=15

# Screenshots (needs a display; works under xvfb-run)
godot --path . --resolution 1280x720 --fixed-fps 60 -s tests/screenshots.gd -- /tmp/shots
```

## Code layout

```
scripts/
  main.gd                   lobby <-> match flow
  core/game.gd              one match: world, spawning, scoring, medals
  core/bunker_control.gd    who holds the gun bunker (and so where each team spawns)
  core/game_config.gd       all tuning numbers + lobby settings
  core/input_setup.gd       keyboard/mouse/gamepad bindings
  level/ascension.gd        the Ascension blockout, spawns, routes, navmesh
  level/level_builder.gd    primitive/mesh/collision helpers
  actors/soldier.gd         Halo-style movement, damage, melee, mounting
  actors/soldier_model.gd   the animated character: blending, aim, crouch, guns in hand
  actors/soldier_anims.gd   turns the Mixamo clips into in-place, in-step loops
  actors/player_controller.gd  input, cameras, shotgun viewmodel
  actors/bot_brain.gd       rudimentary AI
  weapons/weapon.gd         ammo/reload/cooldown shared by the hand-held guns
  weapons/shotgun.gd        pellets, falloff, shell reload
  weapons/rifle.gd          semi-auto Mosin: bloom, headshots, clip reload, zoom
  weapons/maxim_turret.gd   the Tower of Power
  ui/hud.gd                 Halo 2-style HUD, tracker, kill feed
  fx/ragdoll.gd             limp bodies thrown by the killing shot, on the character's skeleton
  fx/sfx.gd                 recorded and synthesized sounds, random takes, master limiter
  fx/                       particles and tracers
assets/characters/soldier/  the character and the six clips it uses
assets/sounds/              the recorded sounds (see tools/prepare_sounds.py)
```
