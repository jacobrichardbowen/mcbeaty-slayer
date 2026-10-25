# Mcbeaty Slayer: Tower of Power

A Godot 4 prototype that tries to recreate the feel of Halo 2 multiplayer
and the community gametype **Tower of Power** on **Ascension**. Two teams
fight over one machine gun at the top of the Big Tower. Whoever holds the gun
controls most of the map, so the other team has to storm the tower along the
side paths.

Teams are loosely Russian Civil War: **Whites** in pale greatcoats and peaked
caps, **Reds** in red coats and pointed *budenovka* hats. The turret is a
Maxim M1910 on a wheeled Sokolov mount. All models are crude primitives.

![The Big Tower's Maxim looking over the dish](docs/maxim_view.jpg)

| | |
|---|---|
| ![Overview](docs/overview.jpg) | ![Whites vs Reds](docs/whites_vs_reds.jpg) |

## Playing it

You don't need Godot to play. Each build is one download, and nothing gets
installed:

- **Windows**: `McbeatySlayer.exe`. Double-click it. The whole game is packed
  inside that one file.
- **Mac**: `McbeatySlayer-Mac.zip`. Double-click to unzip, then double-click
  **Mcbeaty Slayer**. It runs on both Apple Silicon and Intel Macs.

The game opens fullscreen on the lobby. Press **Enter** (or click **Deploy**)
to play. F11 switches between fullscreen and a window. Esc pauses and has
**Quit game**.

**The first launch asks for approval once**, because the builds aren't signed
with a paid developer certificate:

- **Windows** shows "Windows protected your PC": click **More info**, then
  **Run anyway**.
- **Mac** says Apple can't verify the app:
  - On macOS 15 (Sequoia) or newer, open **System Settings → Privacy &
    Security**, scroll down, click **Open Anyway** next to *Mcbeaty Slayer*,
    and confirm.
  - On older macOS, Control-click the app, choose **Open**, then **Open**
    again.

After that it opens with a normal double-click.

### Making new builds

With Godot 4.3 and its export templates installed, `tools/build.sh` exports
all three builds (Windows, Mac, Linux) into `build/`.

### Running from the editor

Install **Godot 4.3** (the standard build, not .NET), choose **Import**,
select `project.godot`, and press **F5**. From a terminal, `godot --path .`
runs it, and `godot --path . -- --autostart` skips the lobby.

### Lobby options

- **Whites (you) start**: at the tower (defend the Maxim) or on the far side
  (storm it).
- **Red bots** (1–8) and **White bots** (allies, 0–7).
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
| Crouch (hides you from the motion tracker) | Ctrl or C | L3 |
| Scoreboard | Tab | Back |
| Pause | Esc | Start |

## The gametype

The rules follow the original 2004 recipe as people remember it: team slayer,
shotgun only, no grenades, no vehicles, **no shields**, and one machine gun
turret placed in one of the towers.

- **Shields off**: 100 health, which slowly regenerates after 6 s without
  taking damage. One melee kills.
- **Shotgun**: 12 shells, 15 pellets, shell-by-shell reload that you can cancel
  by firing. One shot kills out to about 6–7 m. The red reticle comes on
  within 10 m.
- **Maxim**: 600 rounds/min, infinite belt, 72° traverse either side, from
  22° up to 55° down. Third-person camera while you're on it, as with Halo 2
  vehicles. The gunner stays exposed from the sides and from the stairwell
  that comes out right behind them.
- Melee lunge, crouch-jumping, fall damage, a 5 s respawn, kill feed, Halo 2
  multi-kill and spree callouts, and a motion tracker (25 m; it shows enemies
  only while they move upright or fire).

Every number is in [`scripts/core/game_config.gd`](scripts/core/game_config.gd)
if you want to tune the feel.

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

## Bots

The bots are deliberately rudimentary. They shoot or punch any enemy they see
up close, then go for the Maxim:

- If nobody holds the gun, they run to it and man it.
- If the enemy holds it, they storm the tower along the west, east or centre
  route.
- If their own team holds it, they guard the tower.

On the gun they sweep its arc, fire in bursts, and hop off when someone flanks
them.

## Tests

Headless checks, run from the project folder (they need the class cache, so
run `godot --headless --path . --import` once first):

```
# Weapons, melee, jump height, fall damage, and the turret's arc and lethality
godot --headless --path . --fixed-fps 120 -s tests/mechanics_test.gd

# A 150 s bot match: navmesh connectivity, a bot mans the Maxim, kills happen
godot --headless --path . --fixed-fps 120 -s tests/smoke_test.gd -- reds=4 whites=0

# Screenshots (needs a display; works under xvfb-run)
godot --path . --rendering-method gl_compatibility --resolution 1280x720 -s tests/screenshots.gd -- /tmp/shots
```

## Code layout

```
scripts/
  main.gd                   lobby <-> match flow
  core/game.gd              one match: world, spawning, scoring, medals
  core/game_config.gd       all tuning numbers + lobby settings
  core/input_setup.gd       keyboard/mouse/gamepad bindings
  level/ascension.gd        the Ascension blockout, spawns, routes, navmesh
  level/level_builder.gd    primitive/mesh/collision helpers
  actors/soldier.gd         Halo-style movement, damage, melee, mounting
  actors/player_controller.gd  input, cameras, shotgun viewmodel
  actors/bot_brain.gd       rudimentary AI
  weapons/shotgun.gd        pellets, falloff, shell reload
  weapons/maxim_turret.gd   the Tower of Power
  ui/hud.gd                 Halo 2-style HUD, tracker, kill feed
  fx/                       particles, tracers and synthesized sounds (no asset files)
```
