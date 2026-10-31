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

You don't need Godot to play. Download the latest build (`TowerOfPower_v014.exe`) and double-click
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
the Windows build into `build/` as `TowerOfPower_v014.exe`. The number comes
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
- **Mouse sensitivity**: how far the view turns per step of mouse movement
  (default 0.088; it can also be changed from the pause menu). The same
  number turns a little slower on higher-resolution screens.
- **Field of view**: degrees across a 16:9 screen (default 78°). Halo 2's 70°
  was across an old 4:3 TV; keeping its height of view on a widescreen would
  be 86° across. Wider screens see a little more at the sides.
- **Graphics**: High or Low (see below). Changing it restarts the game.
- **Invert look**.

### Graphics: High and Low

**High** (the default) uses Godot's Forward+ renderer, which needs a graphics
card with Vulkan; any card from roughly the last ten years has it. On top of
what Low shows:

- Light bounces off the snow and walls, and roofs and walls shut out the
  sky, so the tower, the Command Center and the covered paths fall into
  deep, sky-blue shade while open ground is lit. Faint lamps in the tower
  and the Command Center keep someone in a dark corner from vanishing.
- Soft shading where surfaces meet (ambient occlusion), and shadow edges
  that soften away from what casts them.
- A faint haze that catches sunlight and lamplight.

In both, every shot's muzzle flash throws a burst of warm light on its
surroundings for a tenth of a second; it shows best in the shade.

**Low** uses the Compatibility renderer (OpenGL), as every build up to v011
did: flat, even light everywhere, for older or weaker PCs.

The choice is saved for the next start. If a PC can't start High at all,
Windows shows "Your video card drivers seem not to support the required
Vulkan version". Updating the graphics driver usually fixes that. Otherwise,
start the game once from a shortcut whose target ends in
` --rendering-driver opengl3`, then pick Low in the menu, and it starts in Low
from then on.

The first match on a new PC can hitch briefly as each effect is drawn for
the first time; Godot keeps what it prepared, so later matches don't.

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

## Playing online

Up to four people can play together, each on their own PC, with nothing but
the exe. There are no accounts and nothing to set up on your router: one
player hosts, and the others connect straight to the host's PC with a short
code.

**To host:** type your name and click **Host online game**. A second later
the lobby shows a code like `6B01R-GEQZN`. Click **Copy code** and send it to
your friends. Pick sides with **Play for the Whites / Reds**, set the bots
and the score limit, and click **Deploy everyone** once everyone is in.

**To join:** type your name, set your weapon and mouse settings, paste the
host's code into **Friend's code**, and click **Join**. Joining takes about
five seconds. On the same home network, the host's local address (the lobby
shows it, e.g. `192.168.1.20`) works in place of the code.

How friends get through the host's router, without changing anything on it:

1. Each game asks a public STUN server (Google's or Cloudflare's) what
   address it shows up as on the internet. The host's address and port,
   written short, are the code.
2. A joining game leaves its own address for the host on
   [ntfy.sh](https://ntfy.sh), a free public message board, under a topic
   named after the code.
3. The host's game reads it and sends a few packets toward that address.
   That tells the host's router the friend is expected, so it lets their
   connection in. This is called hole punching; video calls and many games
   connect the same way.

Earlier builds asked the host's router to open a port by itself (UPnP). Some
routers lock up when asked, so the game no longer does that.

**If friends can't connect:**

- The first time you play online, Windows Firewall may ask whether Tower of
  Power can use the network. Click **Allow**.
- A few routers, and some mobile and satellite connections, won't let hole
  punching through. The joining player then gets "Couldn't reach the host"
  after about 30 seconds. Try someone else as host, or have the host forward
  UDP port **24565** to their PC in their router's settings.
- If the lobby says it couldn't reach the internet, the host's PC is offline,
  or its network blocks the address check.

How an online match works:

- The host's PC runs the match: the bots, the Maxim, the bunker, health and
  the score. Each player's own PC decides whether their shots hit, so what you
  see when you fire is what counts.
- Bots fill out both teams, up to 16 a side.
- If someone leaves mid-match, a bot takes over their soldier. Nobody can join
  a match in progress; new players join in the lobby between matches. If the
  host leaves, the match ends for everyone.
- Esc opens the menu but doesn't pause the game.
- The host sends each friend about 10–20 KB/s, which any home connection
  handles easily.

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

Whoever holds the bunker flies their flag from a 30 m pole on the tower: the
Whites' white-blue-red tricolour or the Reds' red banner with a gold star. It is
12 m long and lit, so it can be seen from anywhere on the map. When the bunker
changes hands the old flag drops and the new one runs up. The pole has no
collision, so it never gets in the way.

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

### How sound carries

The world shapes what you hear, in the spirit of Peak and Big Walk
([`scripts/fx/acoustics.gd`](scripts/fx/acoustics.gd)):

- **Distance**: sounds fall off naturally (half the pressure per doubling of
  distance). Air takes only a little treble off far sounds. Godot's default
  treble cut, which made everything past about 16 m sound muffled, is off.
- **In the way**: a sound is muffled only when something solid stands between
  you and it. Four lines are tried (to the source, above it and to either
  side), because sound bends round small things like the gun shield. Stone
  walls muffle more than a ledge or a rock does.
- **Behind you**: a little duller, as your head shades it. Stereo is half
  strength, so a sound to one side doesn't vanish from the other ear.
- **The space**: outdoors, the mountains throw back a dull echo about 0.4 s
  later, and far sounds come to you with more echo. Inside the tower's
  stairwell, the Command Center and the roofed side paths, sounds take on a
  tight, boomy room instead, and the wind drops.

## The soldier character

The soldier, his animations, his first-person arms and both guns live in one
Blender file, [`art/TowerOfPower_Soldier.blend`](art/) (made with Blender
5.2; open it in 5.2 or newer). The game loads them from two files exported from it,
`assets/characters/soldier/soldier.glb` and `assets/weapons/guns.glb`.

### Working on the .blend

Open it, change what you like, save, and upload it back to the same place
(`art/TowerOfPower_Soldier.blend` on this branch). Then ask for it to be
brought into the game: `tools/blend/export_blend.py` turns it into the two
game files, and the next build carries your changes.

What's in it, and what the game expects:

| In the .blend | What it is | Keep |
|---|---|---|
| `Soldier_Rig` | Mixamo's skeleton, in metres, facing -Y | the bone names (`mixamorig:...`) |
| `Soldier` | the body, skinned to the rig | the material name `White Wool` (the Reds' dye finds it) |
| `FP_Arms` (hidden collection) | the sleeves and gloves you see in first person | delete it and the export cuts it from the body again |
| actions `idle`, `run`, `back`, `strafe_l`, `strafe_r`, `jump` | the animations | the names |
| `Shotgun_3P`, `Rifle_3P` | the guns in soldiers' hands | the names, and the markers inside |
| `Shotgun_FP`, `Rifle_FP` | the guns in first person | the names, the markers, `Pump` and `Bolt` |

- **Animations**: key them on `Soldier_Rig` as usual. The actions are the
  Mixamo clips the game used before, with exactly the poses it played. The
  game still makes the run, backpedal and strafes loop in place at one shared
  length (0.7 s, starting as the left foot lands), so their own length and
  forward travel don't matter; the idle is held on the upper body at all
  times so the gun stays up; and only one frame of `jump` (0.3 s in) is used,
  held while airborne.
- **Textures and materials**: any Principled BSDF setup that glTF can carry
  (colour, roughness, metallic, normal and other image textures). Images
  come across inside the export.
- **Guns**: each gun is an empty with its parts under it. Where the gun
  empty sits in the scene doesn't matter; its parts and markers relative to
  it do. The markers (small spheres) are `Muzzle` (where shots and the flash
  come from), `Hand_R` (where the right hand grips) and `Hand_L` (the left
  hand: on the pump, or on the rifle's fore-stock). In first person the
  `Pump` slides and the `Bolt` turns after each shot, so their parts must stay
  under them. Blender adds `.001` and the like to repeated names; that's
  fine. The game draws the first-person guns at a quarter of their size in
  the .blend, close to the camera, so they are bigger there than the
  third-person ones.

Exporting needs Blender: either a normal install (`blender -b
art/TowerOfPower_Soldier.blend --python tools/blend/export_blend.py`) or
Blender as a Python module (`pip install bpy==5.2.3` on Python 3.13, then
`python tools/blend/export_blend.py art/TowerOfPower_Soldier.blend`).
`tools/blend/build_blend.py` is how the .blend was first made from the
Mixamo files (still in `Mixamo_Shooter_Pack v02.zip`).

### In the game

At load the clips are made to run in place, loop cleanly and share one cycle
length and starting foot, so they blend by direction. Playback speeds up to
match how fast the soldier is moving. After the clips play, the spine turns
so the gun (placed between the hands) points exactly where the soldier aims.
There are no crouch clips, so crouching lowers the hips and bends the knees
to keep the feet where the clip put them. The same leg bending tames the
run's bounce, sped up as it is: only a third of the hips' up-and-down travel
is kept (14 cm of head bob down to 6). After the clips play, only bone
rotations are ever changed, so nothing can build up and stretch the mesh.

In first person you see `FP_Arms`, posed from the aiming idle so the fingers
curl round the grip. Each frame the right hand is put on the gun's `Hand_R`
and the left arm reaches for `Hand_L`, so the hands follow every pump, kick,
reload and swing.

On death, a copy of the character takes the soldier's last pose. Ten capsules
(torso, head, upper arms, forearms, thighs, shins) then move its bones. Knees
and elbows are hinges, so they only bend the natural way.

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

# Online, two copies over this machine's network: joining, movement, kills,
# damage, the Maxim and the bunker on both sides, a bot taking over a leaver
godot --headless --path . -s tests/net_test.gd -- host &
godot --headless --path . -s tests/net_test.gd -- client

# Online, four copies: three friends fill the lobby and a fifth is turned
# away (the file has the commands)
tests/net_lobby_test.gd

# Online, four copies played by the bot AI fight for a minute; friends join
# with the host's code through tests/fake_internet.py (a stand-in STUN
# server, message board and strict home router, with lag and loss). The
# script checks that all four agree on every soldier and on the score
GODOT=godot tools/net_soak.sh

# Screenshots (needs a display; works under xvfb-run). High needs Vulkan: on
# a machine without a graphics card, Mesa's software driver (the Ubuntu
# package mesa-vulkan-drivers) works, slowly. Add
# --rendering-method gl_compatibility for Low.
godot --path . --resolution 1280x720 --fixed-fps 60 -s tests/screenshots.gd -- /tmp/shots
```

## Code layout

```
scripts/
  main.gd                   menu, lobby and match flow, offline or online
  net/net.gd                online play: hosting, join codes, hole punching, the lobby, messages
  net/stun.gd               asks a STUN server for this PC's address on the internet
  net/net_codec.gd          soldier states packed into a few bytes
  core/game.gd              one match: world, spawning, scoring, medals
  core/bunker_control.gd    who holds the gun bunker (and so where each team spawns)
  core/game_config.gd       all tuning numbers + lobby settings
  core/input_setup.gd       keyboard/mouse/gamepad bindings
  level/ascension.gd        the Ascension blockout, spawns, routes, navmesh
  level/level_builder.gd    primitive/mesh/collision helpers
  level/bunker_flag.gd      the holder's flag over the Big Tower
  actors/soldier.gd         Halo-style movement, damage, melee, mounting
  actors/soldier_model.gd   the animated character: blending, aim, crouch, guns in hand
  actors/soldier_anims.gd   turns the Mixamo clips into in-place, in-step loops
  actors/viewmodel_arms.gd  the character's arms holding the first-person gun
  actors/player_controller.gd  input, cameras, shotgun viewmodel
  actors/bot_brain.gd       rudimentary AI
  weapons/weapon.gd         ammo/reload/cooldown shared by the hand-held guns
  weapons/shotgun.gd        pellets, falloff, shell reload
  weapons/rifle.gd          semi-auto Mosin: bloom, headshots, clip reload, zoom
  weapons/maxim_turret.gd   the Tower of Power
  weapons/gun_models.gd     the guns' looks and markers, from the .blend
  ui/hud.gd                 Halo 2-style HUD, tracker, kill feed
  fx/ragdoll.gd             limp bodies thrown by the killing shot, on the character's skeleton
  fx/acoustics.gd           occlusion, echo and rooms: how the world shapes sound
  fx/sfx.gd                 recorded and synthesized sounds, random takes, master limiter
  fx/                       particles and tracers
assets/characters/soldier/  soldier.glb: the character, arms and clips (exported from the .blend)
assets/weapons/             guns.glb: the four guns (exported from the .blend)
art/                        TowerOfPower_Soldier.blend, the source of both (Godot ignores this folder)
tools/blend/                build_blend.py (made the .blend), export_blend.py (.blend -> game files)
assets/sounds/              the recorded sounds (see tools/prepare_sounds.py)
```
