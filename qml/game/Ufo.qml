/*
 * Copyright (C) 2026 - Timo Könnecke <github.com/moWerk>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.6

// UFO — power-up delivery vehicle.
//
// Treated as an extra-heavy asteroid in main.qml's activeAsteroids array.
// Participates in all asteroid-asteroid collisions via the existing
// handleAsteroidCollision() path. Does NOT wrap the screen — navigates a
// fixed 4-waypoint cross-screen path set by spawnUfo() in main.qml.
//
// State machine:
//   normal   — color cycling, hittable
//   dimmed   — grey flat,    not hittable (power-up active)
//   cooldown — grey pulsing, not hittable (10 s before next color revealed)
//
// main.qml sets:
//   dimmed = true             on hit
//   cooldown = true           when powerupTimer expires
//   colorIndex = nextColorIndex()
//   cooldown = false
//   dimmed = false            when ufoCooldownTimer expires

Item {
    id: ufo

    // ── External inputs ───────────────────────────────────────────────────────
    property real dimsFactor: 1
    property bool paused:      false
    property bool gameOver:    false
    property bool calibrating: false
    property int  level: 1

    // ── Physics interface (mirrors asteroidComponent) ─────────────────────────
    // size = same as mid asteroid
    property real   size:       dimsFactor * 6
    // mass 8× heavier than size² so asteroid collisions barely deflect the UFO
    property real   mass:       size * size * 8
    readonly property bool isUfo: true

    // directionX/Y and speed are written each tick by the waypoint movement
    // so handleAsteroidCollision() can read velocity components uniformly
    property real   directionX: 1
    property real   directionY: 0
    property real   speed:      0

    // ── Waypoint navigation ───────────────────────────────────────────────────
    // Absolute screen-space centre coordinates set by spawnUfo() in main.qml
    property var    waypoints:       []
    property int    currentWaypoint: 1

    // ── Power-up state ────────────────────────────────────────────────────────
    // dimmed    — true while power-up is active OR during cooldown.
    //             Blocks hit detection in checkShotUfoCollision.
    // cooldown  — true for 10 s after power-up expires.
    //             UFO pulses grey; new colorIndex picked when cooldown ends.
    property bool   dimmed:   false
    property bool   cooldown: false
    property int    colorIndex: 0

    // Reset brightness when cooldown ends so next cooldown starts clean
    onCooldownChanged: {
        if (!cooldown) cooldownBrightness = 0.1
    }

    // Power-up table.  Weights drive random frequency:
    //   normal (wide/rapid/triple/pierce/frenzy/laser/chain) = 10 each
    readonly property var powerupTypes:   ["wide",    "rapid",   "triple",  "pierce",  "frenzy",  "shield",  "nuke",    "laser",   "chain"   ]
    readonly property var powerupColors:  ["#FF44AA", "#AA44FF", "#33FF66", "#DDCC00", "#FFAA00", "#DD1155", "#FFFFFF", "#00FFAA", "#2299FF" ]
    readonly property var powerupWeights: [10,         10,        10,        8,         8,         6,         6,         10,        10       ]

    // ── Geometry ──────────────────────────────────────────────────────────────
    // SVG natural dimensions after junction snapping: 35.082 × 22.758
    // Aspect ratio: 35.082 / 22.758 = 1.5415
    property real sc: size / 22.758

    width:  size * 1.5415
    height: size

    // ── Color cycling ─────────────────────────────────────────────────────────
    // Picks a new weighted-random power-up every 3 s.
    // Paused while dimmed or in cooldown — UFO stays grey for the full duration.
    Timer {
        interval: 3000
        running:  !ufo.dimmed && !ufo.paused && !ufo.gameOver && !ufo.calibrating
        repeat:   true
        onTriggered: ufo.colorIndex = ufo.nextColorIndex()
    }

    function nextColorIndex() {
        // Power-ups unlock progressively by level
        var unlockLevel = [3, 6, 4, 2, 1, 1, 12, 8, 10]
        var total = 0
        for (var i = 0; i < powerupWeights.length; i++) {
            if (ufo.level >= unlockLevel[i]) total += powerupWeights[i]
        }
        if (total === 0) return 0
            var r = Math.random() * total
            var cumulative = 0
            for (var i = 0; i < powerupWeights.length; i++) {
                if (ufo.level < unlockLevel[i]) continue
                    cumulative += powerupWeights[i]
                    if (r < cumulative) return i
            }
            return 0
    }

    Component.onCompleted: {
        colorIndex = nextColorIndex()
    }

    // ── Cooldown pulse ────────────────────────────────────────────────────────
    // Pulses UFO from near-black to white during the 10 s cooldown window.
    // Range is extreme so the pulse is unmissable even at tiny size.
    property real cooldownBrightness: 0.1

    SequentialAnimation on cooldownBrightness {
        running: ufo.cooldown && !ufo.paused && !ufo.gameOver
        loops:   Animation.Infinite
        NumberAnimation { to: 0.9; duration: 600; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.2; duration: 600; easing.type: Easing.InOutSine }
    }

    // Force cooldownBrightness into the dependency graph unconditionally by
    // reading it before the conditional branches. Without this, the QML binding
    // engine may not track it as a dependency when the cooldown branch is not
    // the initially-evaluated path.
    property color strokeColor: {
        var b = cooldownBrightness
        if (!dimmed)  return powerupColors[colorIndex]
        if (cooldown) return Qt.rgba(b, b, b, 1.0)
        return "#444444"
    }

    // ── Visual ────────────────────────────────────────────────────────────────
    // 10 individual ShapePaths — one per original SVG line segment.
    // All coordinates derived from blaster-ufo.svg with junctions snapped:
    //
    //   SaucerL   = ( 0.000, 14.962)    SaucerR   = (35.082, 14.962)
    //   CockpitTL = (10.511,  7.284)    CockpitTR = (25.184,  7.284)
    //   DomeTL    = (14.196,  0.186)    DomeTR    = (20.850,  0.186)
    //   FootL     = (11.125, 22.504)    FootR     = (25.900, 22.504)

    // SailfishOS (Qt 5.6) has no QtQuick.Shapes: the ten line segments of the
    // saucer are drawn on a Canvas, with the same coordinates as before.
    Canvas {
        id: ufoCanvas
        anchors.fill: parent
        property var segments: [
            [0.000, 14.962, 11.125, 22.504],
            [25.900, 22.504, 11.125, 22.504],
            [35.082, 14.962, 25.900, 22.504],
            [0.000, 14.962, 35.082, 14.962],
            [25.184, 7.284, 35.082, 14.962],
            [10.511, 7.284, 25.184, 7.284],
            [0.000, 14.962, 10.511, 7.284],
            [25.184, 7.284, 20.850, 0.186],
            [14.196, 0.186, 20.850, 0.186],
            [10.511, 7.284, 14.196, 0.186]
        ]
        property color stroke: ufo.strokeColor
        onStrokeChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = stroke
            ctx.lineWidth = ufo.dimsFactor * 1
            ctx.lineCap = "round"
            ctx.beginPath()
            for (var i = 0; i < segments.length; i++) {
                var s = segments[i]
                ctx.moveTo(s[0] * ufo.sc, s[1] * ufo.sc)
                ctx.lineTo(s[2] * ufo.sc, s[3] * ufo.sc)
            }
            ctx.stroke()
        }
    }
}
