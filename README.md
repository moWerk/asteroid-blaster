# Asteroid Blaster

A tilt-controlled asteroid shooter for AsteroidOS smartwatches. Survive escalating waves, hunt a colour-shifting UFO for power-ups, and rack up points inside the bonus perimeter — all on a small smartwatch screen with nothing but a wrist tilt and an autofire cannon.

[![Blaster 2.0 on Youtube](https://img.youtube.com/vi/Yq3bdBSc5J0/0.jpg)](https://www.youtube.com/watch?v=Yq3bdBSc5J0)


## SailfishOS

Reviewing the code? Start with [review-and-architecture-hints.md](review-and-architecture-hints.md).

This branch is the SailfishOS version of the game. It is built for
Sailfish OS 5.1 on aarch64 and was played on a Jolla C2. The game is the
2.0 watch version; this section lists what is different.

### On a tall phone screen

- The ship, the blue score ring, the shield diamond and the HUD stay in a
  centred square as wide as the screen. They keep the proportions of the
  watch, so the game plays the same around the ship.
- The asteroid field, the UFO and the shots use the whole screen height.
  Asteroids drift in from above and below the square too.
- Speeds are tuned in pixels per frame on a watch. They scale with the
  screen width, 1.5 times on a 720 px wide phone.

### Only on SailfishOS

- **Playable cover**: swipe the app away and the round keeps running in
  its tile on the home screen. The button on the tile pauses and resumes.
- **Free flight mode** (2.2.0), chosen on the start or game over screen,
  see below.

### Free flight (2.2.0)

On a watch the ship has to stay in the centre: the screen is too small to
fly around. The phone's screen and a zoom lift that limit, so Blaster has
a second mode next to the original one, which is now called **Idle**.

- **Steering, the original Asteroids controls on two tilt axes.** Tilt
  sideways to turn, as in Idle. Tilt the top edge away from you to thrust
  along the nose; tilt it back towards you to brake. The ship keeps its
  momentum and slowly drifts to a stop. Firing stays automatic.
- **The camera follows the ship.** The ship never reaches an edge. It and
  the blue score ring only lead a little towards where it is heading, by
  how fast it goes. The flight shows in the asteroids, which come at you
  faster or fall behind, and in faint dust drifting past.
- **Zoom.** The faster you fly, the further the view zooms out, up to 1.6
  times the screen at full speed, so you see more of what is coming.
- **A world twice the screen** in each direction, wrapping around.
  Asteroids exist in it before you see them and drift into view,
  preferably from ahead. There
  are twice as many as in Idle, over four times the area.
- **The score ring travels with the ship.** Kills inside it still count
  double, measured from where the ring actually is.
- Free flight keeps its own high score and level.

The mode was designed by the author over three proposals: the camera that
follows the ship, the small lead offset and the zoom with speed are his.
All tuning values are in the balance block of `main.qml` (`ff*`) and are
first guesses waiting for his play testing.

What was checked, and what was not:
- On a Jolla C2, through a test hook that steers without tilting: the
  start screen with the selector; flight straight ahead and while turning
  (the zoom reaches its limit, ship and ring lead towards the heading,
  asteroids stream past); the dust. No QML warnings. CPU at level 1:
  idle 88 %, free flight 94 % of one core.
- Not checked: steering by real tilt, including whether "away" really
  thrusts and "back" brakes; the selector by tap; the game over screen;
  later levels; the Jolla 1 and the tablet; how it feels.

### Start and game over screens (2.2.0)

The start screen shows cover art and waits: choose the mode by tapping
it, then ENGAGE starts the calibration countdown. In its last second the
screen fades into the game. The game over screen shows the same art
dimmed to half behind score, highscore, Try Again and the mode.

The cover art, and the store banner cut from a wider version of it
(`store/`), are **AI-generated** with Grok (xAI), from a prompt the
author and the LLM wrote together in the style of the title art of the
Asteroid Blaster video. The author chose the result and directed the
screen layouts.

### Install

Download the RPM from the releases page and install it:

    devel-su pkcon install-local harbour-asteroid-blaster-2.2.0-1.noarch.rpm

One package for every SailfishOS device from 3.4 up (see "Pure QML"
below). The app runs in the sandbox and asks once for the camera, which it
uses only for the accelerometer (see "Why it asks for the camera").
Highscores and the chosen mode are kept in dconf under
`/apps/harbour-asteroid-blaster`.

### Build

With the Sailfish Platform SDK and a 5.1.0.11 aarch64 target:

    mb2 -t SailfishOS-5.1.0.11-aarch64 build

SailfishOS is on Qt 5.6. The port uses versioned imports, Canvas instead
of `QtQuick.Shapes` for the asteroids and the UFO, inline GLSL shaders,
and a small `Dims` stand-in. The Teko font and the AsteroidOS logo ship
with the app.

### Disclosure for the port

The port was written by an LLM overnight, following the asteroid-dodger
port, with the author's rule for the tall screen. He watched it start on
his C2 and played it. He has not read the port's code. It was tested on
one phone.

```
Disclosure: LLMGD-2 · origin O0 (LLM-ported to the author's tall-screen rule; played once by the author on one Jolla C2; code not read; self-graded)
LLMGD: v0.2; assurance=A2; flags=T; origin={O0:.7,O1:.3}; origin_headline=O0; scope=port(code+assets+packaging+docs); graded-by=claude-opus-5-5; retrieval=author-side
```

## The Smartwatch Angle

Classic Asteroids gives you five buttons and a large screen. A smartwatch gives you an accelerometer, autofire, and a round display that clips your corners. That constraint shaped every design decision in this game.

Tilt rotates the ship. There is no thrust, no hyperspace, no manual fire. The ship stays in the centre and the asteroids come to you. The round screen is not a limitation to work around — the bonus perimeter ring sits right at the circle boundary, rewarding the player for hunting kills close to the centre. Small asteroids that reach the edges are harder to see, which is intentional pressure. The play session is designed for a bus stop: two minutes of escalating chaos, a death cinematic, a score, and a retry button.

The vector aesthetic of the original is preserved. Asteroids are procedurally generated polygon outlines. The UFO is ten hand-tuned line segments translated from a custom SVG. Shots are thin rectangles. Everything is drawn with Qt Shapes, no sprites.

## Gameplay

Tilt your watch to rotate the ship. Shots fire automatically. Destroy asteroids to score points — large rocks split into mid-sized pieces, mid pieces split into smalls. Smalls persist across waves and accumulate, so early neglect punishes you later.

The blue perimeter ring in the centre of the screen doubles all points for kills made inside it. Scoring is 20 / 50 / 100 base per size, so a small asteroid destroyed inside the ring is worth 200. A Score Frenzy power-up doubles everything on top of that.

Clear all large and mid asteroids to advance the wave. Smalls stay. Each new wave adds more large rocks and shortens the spawn interval — by level 6 the field is genuinely crowded.

The UFO observer crosses the screen on a zigzag path between waves. It colour-codes the power-up it carries. Shoot it to collect. After a hit the UFO goes dark for the power-up duration, then pulses grey through a 12-second cooldown before a new colour appears. It never stops moving.

Shields absorb asteroid hits. The diamond indicator around the ship dims as shields drop, giving you a peripheral read on how exposed you are without looking away from the action. At one shield the indicator pulses.

## Power-ups

Power-ups are unlocked progressively as you level up. A white notification flashes on screen at each unlock. If you reach the unlock level without an active power-up, you receive the newly unlocked type as a gift two seconds after the notification appears — a brief window to learn the colour before the UFO shows it to you in the field.

| Colour | Name | Effect | Unlocks |
|--------|------|---------|---------|
| Cyan | (base) | Normal single shot | always |
| Pink | WIDE RAZZ | Two side beams at 20 degrees | level 3 |
| Purple | RAPID HYPE | Fire rate doubles | level 6 |
| Green | TRIPLE DANK | Two parallel beams beside main shot | level 4 |
| Yellow | QUAD PIERCE | Four-directional piercing shots, 25% slower fire | level 2 |
| Gold | SCORE FRENZY | All points doubled, perimeter flashes gold | level 1 |
| Red | THICCER SHIELD | +1 shield, instant | level 1 |
| White | NUKE WIPE | Destroys all asteroids on screen instantly | level 12 |
| Neon green | YEET LASER | Single long piercing beam, very fast | level 8 |
| Blue | GIB CHAIN BOLT | Shot forks toward three nearest asteroids on hit, up to 3 generations | level 10 |

## Visual Feedback

The screen flashes cyan and the level number flashes gold on every level advance. The power-up bar below the level indicator shrinks over the duration and fades out in the final second. Score particles rise from each kill — gold inside the perimeter, darker gold outside.

A death cinematic plays on collision when shields are exhausted: an expanding red ring shader fills the screen before the game over overlay appears. UFO hits show the same ring shader tinted in the power-up colour at the point of impact.

## Controls

Tilt your watch to rotate the ship. Tap the screen to pause. Tap again to resume, or tap Try Again on the game over screen. During pause, tap Debug to toggle the FPS counter and graph.

## Changelog

### v2.0 (2026)

Complete rewrite from v1.1.

Core systems:
- Balance block consolidating all gameplay tuning into one place
- QSettings persistence via C++ GameStorage singleton replacing ConfigurationValue
- Paint order refactor — all z: values removed, layer Items handle stacking via declaration order
- ExplosionShader, ScoreParticle, DeathShader, Ufo extracted to separate QML files

UFO and power-up system:
- UFO as extra-heavy asteroid in the physics simulation — participates in all collision handling with no special-casing
- 9 power-up types with weighted random selection, colour-coded, level-gated progression
- UFO colour-cycles on 3-second intervals, pauses during cooldown, reveals new colour after 12-second grey pulse
- Gift mechanic: newly unlocked power-up granted if no power-up is active at level advance
- Power-up duration bar with fade-in and fade-out

Visual and feedback:
- DeathShader expanding ring for player death and UFO hits
- Level advance screen flash and level number gold pulse
- Stepwise shield indicator opacity tied to shield count
- Score particles and perimeter ring gold-themed to match score display
- Shield and score text pulse animations for zero-state warning
- Haptic feedback on hits and power-up collection

Wave design:
- Waves advance when large and mid asteroids are cleared — smalls accumulate across waves
- Small asteroid cap raised to 100 to allow cross-wave hoarding
- Spawn interval and count scale per level

### v1.1 (March 2025)
- Mass-weighted asteroid collisions
- 50% black dimming layer for pause and game over
- Asteroid speeds reduced
- Restored FPS debug graph
- Score particles linger longer

### v1.0
- Core game loop, tilt controls, autofire, shields, afterburner

### Pure QML, one package for every phone (2.1.0)

App developer poetaster pointed out in the forum that these ports need no
compiled code. Since 2.1.0 the app is QML only: the system's `sailfish-qml`
launcher runs it, and one `noarch` package serves aarch64, 32 bit ARM and
x86, SailfishOS 3.4 to 5.1. Install with
`devel-su pkcon install-local harbour-asteroid-blaster-2.1.0-1.noarch.rpm`;
pkcon brings in the launcher (libsailfishapp-launcher) if it is missing.
The package is compressed with xz, because rpm on SailfishOS 3.4 cannot
unpack the zstd that newer SDKs use by default.

The high score and level moved from a QSettings file (C++) to dconf under `/apps/harbour-asteroid-blaster` (Nemo.Configuration, QML), and the fonts are loaded by QML FontLoaders. Records from earlier versions are not carried over.

Checked: installed and started without QML warnings on a Jolla C2 (5.1),
the Jolla Tablet (4.6) and a Jolla 1 (3.4).

```
Disclosure: LLMGD-3 · origin O1 (idea from a forum reply and the author's go; LLM-converted; start-checked by log on three devices; self-graded)
LLMGD: v0.2; assurance=A3; flags=T; origin={O0:.7,O1:.3}; origin_headline=O0; scope=packaging+code; graded-by=claude-opus-5-5; retrieval=author-side
```

### Why it asks for the camera

On first start the app asks to use the **camera**. It never uses it. It
needs the accelerometer, and the Jolla Store does not allow the Sensors
permission that would say so; SailfishOS's Camera permission includes
sensor access, so that is the one a store app can ask for. App developer
poetaster pointed this out in the forum (his spirit level does the same),
and a sandboxed test on a Jolla C2 confirmed that the tilt works with
only Camera. With Sensors, the store's validator rejected the game; with
Camera, nothing else stands in the way.
