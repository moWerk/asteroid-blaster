# Review and architecture hints: Asteroid Blaster for SailfishOS

For anyone reviewing the `sailfishos` branch: where the code comes from, how it is laid out, what is worth reading and what is boilerplate.

## Where the code comes from

The app is the AsteroidOS watch app on `main`. This branch forks from it at `7947938`, and its commits are the SailfishOS port. The reliable view of what the port changed:

    git diff 7947938 sailfishos -- qml src rpm '*.pro' '*.desktop'

Many port edits carry a `SailfishOS:` comment, but not all of them. Each commit message says what changed, why, and what was not checked, and ends with an LLMGD line grading it.

The port was written by an LLM (Claude), directed and tested by the author, who has not read the code. Everything here is a prototype until a reviewer owns it. That is the point of this file.

## Architecture

- `qml/harbour-asteroid-blaster.qml`: the Silica `ApplicationWindow`. It sizes `Dims` from the screen width, then loads the app (`game/main.qml`). When the app goes to the background, the same item is moved into the cover and scaled down, so the home screen tile shows it live. The same shell is used in all eight ports.
- `qml/game/Dims.qml`, `Label.qml`, `HighlightBar.qml`, `Icon.qml`, `PageHeader.qml`, `ValueCycler.qml`, `IntSelector.qml`, `DeviceSpecs.qml` (whichever exist here): small stand-ins for AsteroidOS's `org.asteroid.controls` and `org.asteroid.utils`, so the watch QML runs unchanged where possible. Each is a few dozen lines.
- `qml/game/main.qml` (about 1700 lines) is the game, in sections: balance block (~31), mutable state (~87), timers (~152), components (~404), scene (~543), HUD (~699), calibration (~844), pause (~912), game over (~993), game logic (~1079), UFO (~1188), power-ups (~1255), asteroid spawning (~1354), collision detection (~1441).
- `Ufo.qml`, `ScoreParticle.qml`, `DeathShader.qml`, `ExplosionShader.qml`: self-contained parts. The shaders are GLSL in `ShaderEffect`.
- `qml/game/GameStorage.qml`: QML singleton for high score and level, kept in dconf (`/apps/harbour-asteroid-blaster`). It replaced a C++ QSettings class with the same API.
- Packaging: pure QML, no binary. `Exec=sailfish-qml harbour-asteroid-blaster` (package `libsailfishapp-launcher`), the `.pro` is `TEMPLATE = aux` with plain `INSTALLS`, and the spec is `BuildArch: noarch` with an xz payload (rpm 4.14 on SailfishOS 3.4 can not unpack the zstd of newer SDKs).

## Read these first

1. Collision detection and asteroid spawning (end of `main.qml`): the per-frame cost. On the C2 the game used about 0.85 of a core.
2. The scene and HUD sections in the port diff: the ship and HUD keep the watch proportions in a centred square, while the asteroid field uses the whole tall screen.
3. `GameStorage.qml`: records are never lowered (an assignment below the stored value is undone).

## Skim

Stand-ins, icons, `img/`, packaging.

## Worth questioning

- Balance: left tilted, the ship keeps turning and firing, and reached level 13 without input. That is an open design question (the author wants to reward input), not a bug report.
- Permissions: `Camera`, not `Sensors` (see the README). The camera is never opened.
- Records from before 2.1.0 are not migrated.

## How it was tested

By the author, by playing it on a Jolla C2 (SailfishOS 5.1), the Jolla Tablet (4.6, x86) and a Jolla 1 (3.4, 32-bit ARM), with the same noarch package on all three. Before each handover, the LLM checked builds, package contents and start logs on those devices.

There are no automated tests; the on-device checks are listed in the commit messages.
