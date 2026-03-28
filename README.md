# Asteroid Blaster

A tilt-controlled asteroid shooter for AsteroidOS smartwatches. Survive escalating waves, hunt a colour-shifting UFO for power-ups, and rack up points inside the bonus perimeter — all on a small smartwatch screen with nothing but a wrist tilt and an autofire cannon.

[![Blaster 2.0 on Youtube](https://img.youtube.com/vi/Yq3bdBSc5J0/0.jpg)](https://www.youtube.com/watch?v=Yq3bdBSc5J0)


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

