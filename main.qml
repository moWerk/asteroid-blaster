/*
 * Copyright (C) 2025 - Timo Könnecke <github.com/eLtMosen>
 *
 * All rights reserved.
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

import QtQuick 2.15
import QtSensors 5.11
import Nemo.Ngf 1.0
import QtQuick.Shapes 1.15
import org.asteroid.controls 1.0
import org.asteroid.blaster 1.0
import Nemo.KeepAlive 1.1

Item {
    id: root
    anchors.fill: parent
    visible: true

    // ── Balance block ─────────────────────────────────────────────────────────
    QtObject {
        id: balance

        // Spawning
        readonly property int   initialSpawnCount:     5
        readonly property int   spawnCountBase:        4
        readonly property int   spawnIntervalStart:    3000
        readonly property int   spawnIntervalFloor:    300
        readonly property int   spawnIntervalStep:     131
        readonly property int   midAsteroidCap:        10
        readonly property int   smallAsteroidCap:      100

        // Asteroid movement
        readonly property real  largeSpeed:            0.27
        readonly property real  midSpeed:              0.36
        readonly property real  smallSpeed:            0.54
        readonly property real  rotationSpeedBase:     10
        readonly property real  rotationSpeedVariance: 1

        // UFO
        readonly property real  ufoSpeed:              1
        readonly property int   ufoSpawnDelay:         4000
        readonly property int   ufoCooldownDuration:   12000

        // Player
        readonly property real  tiltSmoothing:         0.5
        readonly property real  tiltRotationSpeed:     60
        readonly property int   startingShields:       3

        // Shooting
        readonly property int   fireInterval:          160
        readonly property int   rapidFireInterval:     60
        readonly property real  shotSpeed:             8
        readonly property real  shotSpawnOffset:       5
        readonly property real  wideShotAngle:         20
        readonly property real  wideShotSpeedMult:     0.65
        readonly property real  tripleShotSpread:      3
        readonly property real  laserFireMult:         1.2

        // Scoring
        readonly property int   pointsLarge:           20
        readonly property int   pointsMid:             50
        readonly property int   pointsSmall:           100
        readonly property real  perimeterBonusMult:    2.0
        readonly property real  perimeterRadius:       27.5

        // Power-ups
        readonly property int   powerupDuration:       12000
        readonly property real  pierceFourwayFireMult: 1.333

        // Physics
        readonly property real  playerProximityRange:  20
        readonly property real  collisionPushFactor:   0.5
    }

    // ── Mutable game state ────────────────────────────────────────────────────
    property bool calibrating: true
    property int  calibrationTimer: 3
    property bool debugMode: false
    property bool gameOver: false
    property int  level: 1
    property bool paused: false
    property int  score: 0
    property int  shield: balance.startingShields

    property real dimsFactor: Dims.l(100) / 100
    property var  activeShots: []
    property var  activeAsteroids: []
    property real lastFrameTime: 0
    property real baselineX: 0
    property real smoothedX: 0
    property real playerRotation: 0
    property int  initialAsteroidsToSpawn: balance.initialSpawnCount
    property int  asteroidsSpawned: 0

    property real centerX: root.width  / 2
    property real centerY: root.height / 2

    // UFO state
    property bool ufoActive: false
    property var  ufoObject: null
    readonly property real ufoSize: dimsFactor * 8

    // Power-up state
    property string activePowerup: ""
    property color  glowColor: "#00000000"
    property string powerupLabel: ""
    property string unlockLabel: ""
    property bool   popupActive: false

    NonGraphicalFeedback {
        id: feedback
        event: "press"
    }

    onGameOverChanged: {
        if (gameOver) {
            GameStorage.highScore = score
            GameStorage.highLevel = level
        }
    }

    onCalibratingChanged: {
        if (!calibrating) ufoSpawnTimer.restart()
    }

    // ── Timers ────────────────────────────────────────────────────────────────

    Timer {
        id: gameTimer
        interval: 16
        running: !gameOver && !calibrating && !paused
        repeat: true
        property real lastFps: 60
        property var  fpsHistory: []
        property real lastFpsUpdate: 0
        property real lastGraphUpdate: 0

        onTriggered: {
            var currentTime = Date.now()
            var deltaTime = lastFrameTime > 0 ? (currentTime - lastFrameTime) / 1000 : 0.016
            if (deltaTime > 0.033) deltaTime = 0.033
            lastFrameTime = currentTime
            updateGame(deltaTime)

            var rawX = accelerometer.reading.x
            smoothedX = smoothedX + balance.tiltSmoothing * (rawX - smoothedX)
            var deltaX = (smoothedX - baselineX) * -2
            playerRotation += deltaX * balance.tiltRotationSpeed * deltaTime
            playerRotation = (playerRotation + 360) % 360

            var currentFps = deltaTime > 0 ? 1 / deltaTime : 60
            lastFps = currentFps
            if (debugMode && currentTime - lastFpsUpdate >= 500) {
                lastFpsUpdate = currentTime
                fpsDisplay.text = "FPS: " + Math.round(currentFps)
            }
            if (debugMode && currentTime - lastGraphUpdate >= 500) {
                lastGraphUpdate = currentTime
                var tempHistory = fpsHistory.slice()
                tempHistory.push(currentFps)
                if (tempHistory.length > 10) tempHistory.shift()
                fpsHistory = tempHistory
            }
        }
    }

    Timer {
        id: calibrationCountdownTimer
        interval: 1000
        running: calibrating
        repeat: true
        onTriggered: {
            calibrationTimer--
            if (calibrationTimer <= 0) {
                baselineX = accelerometer.reading.x
                smoothedX = baselineX
                calibrating = false
                feedback.play()
            }
        }
    }

    Timer {
        id: autoFireTimer
        interval: activePowerup === "rapid" ? balance.rapidFireInterval : activePowerup === "pierce" ? Math.round(balance.fireInterval * balance.pierceFourwayFireMult) : activePowerup === "laser" ? Math.round(balance.fireInterval * balance.laserFireMult) : balance.fireInterval
        running: !gameOver && !calibrating && !paused
        repeat: true
        onTriggered: {
            var rad = playerRotation * Math.PI / 180
            var shotX = playerContainer.x + playerHitbox.x + playerHitbox.width  / 2 - dimsFactor * 0.5
            var shotY = playerContainer.y + playerHitbox.y + playerHitbox.height / 2 - dimsFactor * 2.5
            var ox = shotX + Math.sin(rad) * (dimsFactor * balance.shotSpawnOffset)
            var oy = shotY - Math.cos(rad) * (dimsFactor * balance.shotSpawnOffset)

            var isPierce = activePowerup === "pierce"
            var angles = isPierce ? [rad, rad + Math.PI * 0.5, rad + Math.PI, rad + Math.PI * 1.5]
                                  : [rad]
            for (var ai = 0; ai < angles.length; ai++) {
                var a = angles[ai]
                var sox = shotX + Math.sin(a) * (dimsFactor * balance.shotSpawnOffset)
                var soy = shotY - Math.cos(a) * (dimsFactor * balance.shotSpawnOffset)
                var shot = autoFireShotComponent.createObject(shotLayer, {
                    "x": sox, "y": soy,
                    "directionX":  Math.sin(a),
                    "directionY": -Math.cos(a),
                    "rotation":    playerRotation + ai * 90,
                    "shotColor":   isPierce ? "#DDCC00" : activePowerup === "rapid" ? "#AA44FF" : activePowerup === "triple" ? "#33FF66" : activePowerup === "frenzy" ? "#FFAA00" : activePowerup === "wide" ? "#FF44AA" : activePowerup === "laser" ? "#00FFAA" : activePowerup === "chain" ? "#2299FF" : "#00FFFF",
                    "piercing":    isPierce
                })
                activeShots.push(shot)
            }

            if (activePowerup === "wide") {
                var aL = rad - balance.wideShotAngle * Math.PI / 180
                var aR = rad + balance.wideShotAngle * Math.PI / 180
                var sL = autoFireShotComponent.createObject(shotLayer, {
                    "x": ox, "y": oy,
                    "directionX": Math.sin(aL), "directionY": -Math.cos(aL),
                    "rotation":   playerRotation - balance.wideShotAngle,
                    "shotColor":  "#FF44AA",
                    "speed":      balance.shotSpeed * balance.wideShotSpeedMult
                })
                var sR = autoFireShotComponent.createObject(shotLayer, {
                    "x": ox, "y": oy,
                    "directionX": Math.sin(aR), "directionY": -Math.cos(aR),
                    "rotation":   playerRotation + balance.wideShotAngle,
                    "shotColor":  "#FF44AA",
                    "speed":      balance.shotSpeed * balance.wideShotSpeedMult
                })
                activeShots.push(sL)
                activeShots.push(sR)
            }

            if (activePowerup === "triple") {
                var perpX  = Math.cos(rad)
                var perpY  = Math.sin(rad)
                var spread = dimsFactor * balance.tripleShotSpread
                var sTL = autoFireShotComponent.createObject(shotLayer, {
                    "x": ox - perpX * spread, "y": oy - perpY * spread,
                    "directionX":  Math.sin(rad), "directionY": -Math.cos(rad),
                    "rotation":    playerRotation,
                    "shotColor":   "#33FF66"
                })
                var sTR = autoFireShotComponent.createObject(shotLayer, {
                    "x": ox + perpX * spread, "y": oy + perpY * spread,
                    "directionX":  Math.sin(rad), "directionY": -Math.cos(rad),
                    "rotation":    playerRotation,
                    "shotColor":   "#33FF66"
                })
                activeShots.push(sTL)
                activeShots.push(sTR)
            }

            if (activePowerup === "laser") {
                var removed = activeShots.pop()
                if (removed) removed.destroy()
                var beam = autoFireShotComponent.createObject(shotLayer, {
                    "x": sox - dimsFactor * 1,
                    "y": soy - dimsFactor * 50,
                    "directionX":  Math.sin(rad),
                    "directionY": -Math.cos(rad),
                    "rotation":    playerRotation,
                    "transformOrigin": Item.Bottom,
                    "shotColor":   "#00FFAA",
                    "width":       dimsFactor * 2,
                    "height":      dimsFactor * 50,
                    "speed":       balance.shotSpeed * 5,
                    "piercing":    true
                })
                activeShots.push(beam)
            }

            if (activePowerup === "chain") {
                var cs = activeShots[activeShots.length - 1]
                if (cs) {
                    cs.chaining   = true
                    cs.generation = 0
                    cs.shotColor  = "#2299FF"
                    cs.width      = dimsFactor * 2
                    cs.speed      = balance.shotSpeed * 0.85
                }
            }
        }
    }

    Timer {
        id: asteroidSpawnTimer
        interval: Math.max(balance.spawnIntervalFloor,
                           balance.spawnIntervalStart - (level - 1) * balance.spawnIntervalStep)
        running: !gameOver && !calibrating && !paused && asteroidsSpawned < initialAsteroidsToSpawn
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            spawnLargeAsteroid()
            asteroidsSpawned++
            if (asteroidsSpawned >= initialAsteroidsToSpawn) stop()
        }
    }

    Timer {
        id: ufoSpawnTimer
        interval: balance.ufoSpawnDelay
        repeat: false
        onTriggered: {
            if (!ufoActive && !gameOver) spawnUfo()
        }
    }

    Timer {
        id: powerupTimer
        interval: balance.powerupDuration
        repeat: false
        onTriggered: {
            activePowerup = ""
            glowColor = "#00000000"
            if (ufoObject) {
                ufoObject.cooldown = true
                ufoCooldownTimer.restart()
            }
        }
    }

    Timer {
        id: ufoCooldownTimer
        interval: balance.ufoCooldownDuration
        repeat: false
        onTriggered: {
            if (ufoObject) {
                ufoObject.colorIndex = ufoObject.nextColorIndex()
                ufoObject.cooldown = false
                ufoObject.dimmed = false
            }
        }
    }

    // ── Components ────────────────────────────────────────────────────────────

    Component {
        id: ufoComponent
        Ufo {
            dimsFactor:  root.dimsFactor
            paused:      root.paused
            gameOver:    root.gameOver
            calibrating: root.calibrating
            level:       root.level
        }
    }

    Component {
        id: explosionParticleComponent
        ExplosionShader { }
    }

    Component {
        id: autoFireShotComponent
        Rectangle {
            width:     dimsFactor * 1
            height:    dimsFactor * 4
            color:     shotColor
            visible:   true
            property string shotColor:  "#00FFFF"
            property real   speed:      balance.shotSpeed
            property real   directionX: 0
            property real   directionY: -1
            property bool   piercing:   false
            property bool   chaining:   false
            property int    generation: 0
            rotation: playerRotation
        }
    }

    Component {
        id: scoreParticleComponent
        ScoreParticle { }
    }

    Component {
        id: asteroidComponent
        Shape {
            id: asteroid
            property real size: dimsFactor * 20
            property real speed: {
                if (asteroidSize === "large") return balance.largeSpeed
                if (asteroidSize === "mid")   return balance.midSpeed
                if (asteroidSize === "small") return balance.smallSpeed
                return 2
            }
            property real   mass:         size * size
            property real   directionX:   0
            property real   directionY:   0
            property string asteroidSize: "large"
            readonly property bool isUfo: false
            property real   rotationSpeed: (Math.random() < 0.5 ? -1 : 1)
                * (balance.rotationSpeedBase
                   + Math.random() * balance.rotationSpeedVariance * 2
                   - balance.rotationSpeedVariance)
            width:  size
            height: size

            property var asteroidPoints: {
                var basePoints  = Math.floor(5 + Math.random() * 3)
                var pointsArray = []
                var cx = size / 2
                var cy = size / 2
                for (var i = 0; i < basePoints; i++) {
                    var baseAngle = (i / basePoints) * 2 * Math.PI
                    var angle     = baseAngle + Math.random() * 0.2 - 0.1
                    var isSpike   = Math.random() < 0.7
                    var minR = isSpike ? size * 0.35 : size * 0.25
                    var maxR = isSpike ? size * 0.48 : size * 0.32
                    var r    = minR + Math.random() * (maxR - minR)
                    pointsArray.push({ x: cx + r * Math.cos(angle), y: cy + r * Math.sin(angle) })
                    if (Math.random() < 0.3 && i < basePoints - 1) {
                        var midAngle = baseAngle + (1 / basePoints) * Math.PI + (Math.random() * 0.2 - 0.1)
                        var midR     = size * (0.2 + Math.random() * 0.15)
                        pointsArray.push({ x: cx + midR * Math.cos(midAngle),
                                           y: cy + midR * Math.sin(midAngle) })
                    }
                }
                return pointsArray
            }

            rotation: 0
            NumberAnimation on rotation {
                running: !paused && !gameOver && !calibrating
                loops:   Animation.Infinite
                from: 0
                to:   360 * (rotationSpeed < 0 ? -1 : 1)
                duration: Math.abs(360 / rotationSpeed) * 800
            }

            ShapePath {
                strokeWidth: dimsFactor * 1
                strokeColor: paused ? "#444444" : "white"
                fillColor:   paused ? "transparent" : "#222222"
                capStyle:  ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: asteroid.asteroidPoints[0].x
                startY: asteroid.asteroidPoints[0].y
                PathPolyline {
                    path: {
                        var pts = []
                        for (var i = 0; i < asteroid.asteroidPoints.length; i++)
                            pts.push(Qt.point(asteroid.asteroidPoints[i].x, asteroid.asteroidPoints[i].y))
                        pts.push(Qt.point(asteroid.asteroidPoints[0].x, asteroid.asteroidPoints[0].y))
                        return pts
                    }
                }
            }

            function split() {
                if (asteroidSize === "large"
                        && activeAsteroids.filter(function(a) { return !a.isUfo && a.asteroidSize === "mid" }).length < balance.midAsteroidCap) {
                    spawnSplitAsteroids("mid", dimsFactor * 12, 2, x, y, directionX, directionY)
                } else if (asteroidSize === "mid"
                        && activeAsteroids.filter(function(a) { return !a.isUfo && a.asteroidSize === "small" }).length < balance.smallAsteroidCap) {
                    spawnSplitAsteroids("small", dimsFactor * 6, 2, x, y, directionX, directionY)
                }
                destroyAsteroid(this)
            }
        }
    }

    // ── Scene ─────────────────────────────────────────────────────────────────
    // Paint order via declaration order only — no z: values anywhere.
    // Layer Items (shotLayer, asteroidLayer, vfxLayer) are named insertion
    // points for dynamically created objects. Their declaration position
    // in gameContent determines when they paint relative to static items.
    //
    // Bottom → top within gameContent:
    //   scorePerimeter  — bonus zone circle
    //   shotLayer       — shots
    //   playerContainer — glow (first child) then ship (second child)
    //   asteroidLayer   — asteroids + UFO
    //   vfxLayer        — explosions + score particles
    //   HUD             — level, bar, unlock, popup, score, shield
    //   calibrationContainer
    //   dimmingLayer
    //   pauseText + debug
    //
    // gameOverContainer is a sibling to gameContent declared after it,
    // so it always paints on top without any z: needed.

    Item {
        id: gameArea
        anchors.fill: parent

        // Solid black background — first child of gameArea, paints behind everything.
        // No layer.enabled or clip on a solid fill-parent Rectangle.
        Rectangle {
            anchors.fill: parent
            color: "black"
        }

        Item {
            id: gameContent
            anchors.fill: parent

            Rectangle {
                id: scorePerimeter
                width:  dimsFactor * 55
                height: dimsFactor * 55
                radius: dimsFactor * 27.5
                color: "#010A13"
                border.color: "#0860C4"
                border.width: 1
                anchors.centerIn: parent
                visible: !calibrating
                Behavior on border.color { ColorAnimation { duration: 1000; easing.type: Easing.OutQuad } }
                Behavior on color        { ColorAnimation { duration: 1000; easing.type: Easing.OutQuad } }
            }

            Timer {
                id: perimeterFlashTimer
                interval: 100
                repeat: false
                onTriggered: {
                    scorePerimeter.border.color = "#0860C4"
                    scorePerimeter.color = "#010A13"
                }
            }

            Item {
                id: shotLayer
                anchors.fill: parent
            }

            Item {
                id: playerContainer
                x: root.width  / 2 - player.width  / 2 + dimsFactor * 5
                y: root.height / 2 - player.height / 2 + dimsFactor * 5
                visible: !calibrating

                Rectangle {
                    id: playerGlow
                    width:   dimsFactor * 22
                    height:  dimsFactor * 22
                    radius:  dimsFactor * 11
                    anchors.centerIn: parent
                    color:   glowColor
                    opacity: 0.0
                    visible: activePowerup !== ""

                    SequentialAnimation on opacity {
                        running: activePowerup !== ""
                        loops:   Animation.Infinite
                        NumberAnimation { to: 0.55; duration: 500; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 0.0;  duration: 500; easing.type: Easing.InOutQuad }
                    }
                }

                Image {
                    id: player
                    width:  dimsFactor * 10
                    height: dimsFactor * 10
                    source: "file:///usr/share/asteroid-launcher/watchfaces-img/asteroid-logo.svg"
                    anchors.centerIn: parent
                    rotation: playerRotation
                }

                Shape {
                    id: playerHitbox
                    width:  dimsFactor * 10
                    height: dimsFactor * 10
                    anchors.centerIn: parent
                    visible: false
                    rotation: playerRotation
                    ShapePath {
                        strokeWidth: -1
                        fillColor: "transparent"
                        startX: dimsFactor * 5; startY: 0
                        PathLine { x: dimsFactor * 10; y: dimsFactor * 5 }
                        PathLine { x: dimsFactor * 5;  y: dimsFactor * 10 }
                        PathLine { x: 0;               y: dimsFactor * 5 }
                        PathLine { x: dimsFactor * 5;  y: 0 }
                    }
                }

                Shape {
                    id: shieldHitbox
                    width:  dimsFactor * 14
                    height: dimsFactor * 14
                    anchors.centerIn: parent
                    visible: shield > 0
                    rotation: playerRotation
                    ShapePath {
                        strokeWidth: 2
                        strokeColor: "#DD1155"
                        fillColor: "transparent"
                        startX: dimsFactor * 7; startY: 0
                        PathLine { x: dimsFactor * 14; y: dimsFactor * 7 }
                        PathLine { x: dimsFactor * 7;  y: dimsFactor * 14 }
                        PathLine { x: 0;               y: dimsFactor * 7 }
                        PathLine { x: dimsFactor * 7;  y: 0 }
                    }
                }
            }

            Item {
                id: asteroidLayer
                anchors.fill: parent
            }

            Item {
                id: vfxLayer
                anchors.fill: parent
            }

            // ── HUD ───────────────────────────────────────────────────────────

            Text {
                id: levelNumber
                text: level
                color: "#00FFFF"
                font { pixelSize: dimsFactor * 12; family: "Teko"; styleName: "SemiBold" }
                anchors { top: root.top; horizontalCenter: parent.horizontalCenter }
                visible: !calibrating
            }

            Item {
                id: powerupBarContainer
                width: dimsFactor * 40
                height: dimsFactor * 3
                anchors {
                    top: levelNumber.bottom
                    topMargin: -dimsFactor * 1.4
                    horizontalCenter: parent.horizontalCenter
                }
                visible: !calibrating && !gameOver && activePowerup !== "" && activePowerup !== "shield"

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.15)
                }

                Rectangle {
                    id: powerupBarFill
                    width: powerupBarContainer.width
                    height: parent.height
                    radius: height / 2
                    color: glowColor
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                NumberAnimation {
                    id: powerupBarAnim
                    target: powerupBarFill
                    property: "width"
                    from: powerupBarContainer.width
                    to: 0
                    duration: balance.powerupDuration
                    easing.type: Easing.Linear
                }
            }

            Text {
                id: powerupUnlock
                text: unlockLabel
                color: "white"
                font { pixelSize: dimsFactor * 11; family: "Teko"; styleName: "Bold"; letterSpacing: dimsFactor * 0.3 }
                anchors {
                    top: powerupBarContainer.bottom
                    topMargin: dimsFactor * 5
                    horizontalCenter: parent.horizontalCenter
                }
                opacity: 0
                visible: !calibrating && !gameOver

                SequentialAnimation {
                    id: unlockAnim
                    NumberAnimation { target: powerupUnlock; property: "opacity"; to: 0.9; duration: 200 }
                    PauseAnimation  { duration: 2400 }
                    NumberAnimation { target: powerupUnlock; property: "opacity"; to: 0.0; duration: 800; easing.type: Easing.InQuad }
                }
            }

            Text {
                id: powerupPopup
                text: powerupLabel
                color: glowColor
                font { pixelSize: dimsFactor * 14; family: "Teko"; styleName: "Bold"; letterSpacing: dimsFactor * 0.3 }
                anchors {
                    bottom: scoreText.top
                    bottomMargin: -dimsFactor * 5
                    horizontalCenter: parent.horizontalCenter
                }
                opacity: 0
                visible: !calibrating && !gameOver

                SequentialAnimation {
                    id: popupAnim
                    NumberAnimation { target: powerupPopup; property: "opacity"; to: 0.8; duration: 100 }
                    NumberAnimation { target: powerupPopup; property: "opacity"; to: 0.4; duration: 50 }
                    NumberAnimation { target: powerupPopup; property: "opacity"; to: 0.9; duration: 50 }
                    NumberAnimation { target: powerupPopup; property: "opacity"; to: 1.0; duration: 50 }
                    NumberAnimation { target: powerupPopup; property: "opacity"; to: 0.9; duration: 50 }
                    PauseAnimation  { duration: 2200 }
                    NumberAnimation { target: powerupPopup; property: "opacity"; to: 0.0; duration: 400; easing.type: Easing.InQuad }
                }
            }

            Text {
                id: scoreText
                text: score
                color: "#FFAA00"
                font { pixelSize: dimsFactor * 13; family: "Teko"; styleName: activePowerup === "frenzy" ? "Bold" : "Light" }
                anchors {
                    bottom: shieldText.top
                    bottomMargin: -dimsFactor * 8
                    horizontalCenter: parent.horizontalCenter
                }
                visible: !gameOver && !calibrating
                Behavior on color { ColorAnimation { duration: 300 } }
            }

            Text {
                id: shieldText
                text: shield
                color: shield > 0 ? "#DD1155" : "white"
                font { pixelSize: dimsFactor * 12; family: "Teko"; styleName: "SemiBold" }
                anchors {
                    bottom: parent.bottom
                    bottomMargin: -dimsFactor * 5
                    horizontalCenter: parent.horizontalCenter
                }
                visible: !calibrating
            }

            // ── Calibration ───────────────────────────────────────────────────
            Item {
                id: calibrationContainer
                anchors.fill: parent
                visible: calibrating

                Text {
                    text: "v2.0\nAsteroid Blaster"
                    color: "#dddddd"
                    lineHeightMode: Text.ProportionalHeight
                    lineHeight: 0.6
                    font { family: "Teko"; pixelSize: dimsFactor * 16; styleName: "Medium" }
                    anchors {
                        bottom: calibrationText.top
                        bottomMargin: dimsFactor * 10
                        horizontalCenter: parent.horizontalCenter
                    }
                    horizontalAlignment: Text.AlignHCenter
                }

                Column {
                    id: calibrationText
                    anchors { top: parent.verticalCenter; horizontalCenter: parent.horizontalCenter }
                    spacing: dimsFactor * 1
                    Text {
                        text: "Calibrating"
                        color: "white"
                        font.pixelSize: dimsFactor * 9
                        horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: "Hold your watch comfy"
                        color: "white"
                        font.pixelSize: dimsFactor * 6
                        horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: calibrationTimer + "s"
                        color: "white"
                        font.pixelSize: dimsFactor * 9
                        horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: calibrating
                    onClicked: {
                        baselineX = accelerometer.reading.x
                        smoothedX = baselineX
                        calibrating = false
                        feedback.play()
                    }
                }
            }

            // ── Dimming overlay ───────────────────────────────────────────────
            Rectangle {
                id: dimmingLayer
                anchors.fill: parent
                color: "#000000"
                opacity: (paused && !gameOver && !calibrating) || gameOver ? 0.6 : 0.0
                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
            }

            // ── Pause + debug ─────────────────────────────────────────────────
            Text {
                id: pauseText
                text: "Paused"
                color: "white"
                font { pixelSize: dimsFactor * 22; family: "Teko" }
                anchors.centerIn: parent
                opacity: 0
                visible: !gameOver && !calibrating
                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
                MouseArea {
                    anchors.fill: parent
                    enabled: !gameOver && !calibrating
                    onClicked: {
                        paused = !paused
                        pauseText.opacity = paused ? 1.0 : 0.0
                    }
                }
            }

            Text {
                id: fpsDisplay
                text: "FPS: 60"
                color: "white"
                opacity: 0.5
                font.pixelSize: dimsFactor * 10
                anchors { horizontalCenter: parent.horizontalCenter; bottom: fpsGraph.top }
                visible: debugMode && !gameOver && !calibrating
            }

            Rectangle {
                id: fpsGraph
                width: dimsFactor * 30; height: dimsFactor * 10
                color: "#00000000"
                opacity: 0.5
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: debugToggle.top
                    topMargin: dimsFactor * 3
                }
                visible: debugMode && !gameOver && !calibrating
                Row {
                    anchors.fill: parent
                    spacing: 0
                    Repeater {
                        model: 10
                        Rectangle {
                            width: fpsGraph.width / 10
                            height: {
                                var fps = index < gameTimer.fpsHistory.length ? gameTimer.fpsHistory[index] : 0
                                return Math.min(dimsFactor * 10, Math.max(0, (fps / 60) * dimsFactor * 10))
                            }
                            color: {
                                var fps = index < gameTimer.fpsHistory.length ? gameTimer.fpsHistory[index] : 0
                                return fps > 60 ? "green" : fps >= 50 ? "orange" : "red"
                            }
                        }
                    }
                }
            }

            Text {
                id: debugToggle
                text: "Debug"
                color: "white"
                opacity: debugMode ? 1 : 0.5
                font { pixelSize: dimsFactor * 10; bold: debugMode }
                anchors {
                    bottom: pauseText.top
                    horizontalCenter: parent.horizontalCenter
                    bottomMargin: dimsFactor * 4
                }
                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
                visible: paused && !gameOver && !calibrating
                MouseArea {
                    anchors.fill: parent
                    onClicked: { debugMode = !debugMode }
                }
            }
        }

        // ── Game over — sibling to gameContent, always paints on top ──────────
        Item {
            id: gameOverContainer
            anchors.fill: parent
            visible: gameOver

            Text {
                text: "Game Over"
                color: "white"
                font { pixelSize: dimsFactor * 20; family: "Teko"; styleName: "Medium" }
                anchors {
                    bottom: scoreOverText.top
                    bottomMargin: -dimsFactor * 8
                    horizontalCenter: parent.horizontalCenter
                }
            }

            Text {
                id: scoreOverText
                text: "Score: " + score + "\nLevel: " + level
                horizontalAlignment: Text.AlignHCenter
                color: "white"
                lineHeightMode: Text.ProportionalHeight
                lineHeight: 0.6
                font { pixelSize: dimsFactor * 12; family: "Teko" }
                anchors {
                    bottom: parent.verticalCenter
                    bottomMargin: dimsFactor * 1
                    horizontalCenter: parent.horizontalCenter
                }
            }

            Text {
                text: "Highscore: " + GameStorage.highScore + "\nLevel: " + GameStorage.highLevel
                horizontalAlignment: Text.AlignHCenter
                color: "white"
                lineHeightMode: Text.ProportionalHeight
                lineHeight: 0.6
                font { pixelSize: dimsFactor * 12; family: "Teko" }
                anchors {
                    top: parent.verticalCenter
                    topMargin: dimsFactor * 1
                    horizontalCenter: parent.horizontalCenter
                }
            }

            Rectangle {
                width: dimsFactor * 50; height: dimsFactor * 20
                radius: dimsFactor * 2
                color: "#222222"
                anchors {
                    top: parent.verticalCenter
                    topMargin: dimsFactor * 20
                    horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "Try Again"
                    color: "white"
                    font { pixelSize: dimsFactor * 10; family: "Teko"; styleName: "SemiBold" }
                    anchors.centerIn: parent
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { restartGame() }
                }
            }
        }

        Accelerometer {
            id: accelerometer
            active: true
        }
    }

    // ── Game logic ────────────────────────────────────────────────────────────

    function updateGame(deltaTime) {

        for (var si = activeShots.length - 1; si >= 0; si--) {
            var shot = activeShots[si]
            if (!shot) continue

            shot.x += shot.directionX * shot.speed * deltaTime * 60
            shot.y += shot.directionY * shot.speed * deltaTime * 60

            if (shot.y <= -shot.height || shot.y >= root.height ||
                shot.x <= -shot.width  || shot.x >= root.width) {
                shot.destroy()
                activeShots.splice(si, 1)
                continue
            }

            var shotHit = false
            for (var ai = activeAsteroids.length - 1; ai >= 0; ai--) {
                var target = activeAsteroids[ai]
                if (!target) continue

                if (target.isUfo) {
                    if (!target.dimmed && checkShotUfoCollision(shot, target)) {
                        handleUfoHit(target)
                        shotHit = true
                        break
                    }
                    continue
                }

                if (checkShotAsteroidCollision(shot, target)) {
                    handleShotAsteroidCollision(shot, target)
                    if (!shot.piercing) {
                        shotHit = true
                        break
                    }
                }
            }

            if (shotHit) {
                shot.destroy()
                activeShots.splice(si, 1)
            }
        }

        for (var ai = activeAsteroids.length - 1; ai >= 0; ai--) {
            var obj = activeAsteroids[ai]
            if (!obj) continue

            if (obj.isUfo) {
                if (obj.currentWaypoint >= obj.waypoints.length) {
                    if (obj.dimmed) {
                        obj.currentWaypoint = 1
                    } else {
                        destroyUfo()
                        break
                    }
                }
                var wp    = obj.waypoints[obj.currentWaypoint]
                var ucx   = obj.x + obj.width  / 2
                var ucy   = obj.y + obj.height / 2
                var udx   = wp.x - ucx
                var udy   = wp.y - ucy
                var udist = Math.sqrt(udx * udx + udy * udy)
                if (udist < dimsFactor * 4) {
                    obj.currentWaypoint++
                } else {
                    obj.x += (udx / udist) * balance.ufoSpeed * deltaTime * 60
                    obj.y += (udy / udist) * balance.ufoSpeed * deltaTime * 60
                    obj.directionX = udx / udist
                    obj.directionY = udy / udist
                    obj.speed      = balance.ufoSpeed
                }
                continue
            }

            obj.x += obj.directionX * obj.speed * deltaTime * 60
            obj.y += obj.directionY * obj.speed * deltaTime * 60

            if      (obj.x > root.width)        obj.x = -obj.width
            else if (obj.x + obj.width  < 0)    obj.x =  root.width
            if      (obj.y > root.height)        obj.y = -obj.height
            else if (obj.y + obj.height < 0)     obj.y =  root.height

            var playerCenterX   = playerContainer.x + playerHitbox.width  / 2
            var playerCenterY   = playerContainer.y + playerHitbox.height / 2
            var asteroidCenterX = obj.x + obj.width  / 2
            var asteroidCenterY = obj.y + obj.height / 2
            var proximityRange  = dimsFactor * balance.playerProximityRange
            if (Math.abs(playerCenterX - asteroidCenterX) < proximityRange &&
                Math.abs(playerCenterY - asteroidCenterY) < proximityRange) {
                if (checkPlayerAsteroidCollision(playerHitbox, obj)) {
                    handlePlayerAsteroidCollision(obj)
                }
            }
        }

        for (var a1i = 0; a1i < activeAsteroids.length; a1i++) {
            var a1 = activeAsteroids[a1i]
            if (!a1) continue
            for (var a2i = a1i + 1; a2i < activeAsteroids.length; a2i++) {
                var a2 = activeAsteroids[a2i]
                if (checkCollision(a1, a2)) handleAsteroidCollision(a1, a2)
            }
        }
    }

    // ── UFO ───────────────────────────────────────────────────────────────────

    function spawnUfo() {
        var w    = root.width
        var h    = root.height
        var ufoW = ufoSize * 1.5415
        var ufoH = ufoSize
        var side = Math.floor(Math.random() * 4)
        var waypoints

        if (side === 0) {
            waypoints = [
                Qt.point(-ufoW,    h * 0.50),
                Qt.point(w * 0.25, -h * 0.25),
                Qt.point(w * 0.50,  h + ufoH),
                Qt.point(w + ufoW,  h * 0.25)
            ]
        } else if (side === 1) {
            waypoints = [
                Qt.point(w * 0.50, -ufoH),
                Qt.point(w + ufoW,  h * 0.25),
                Qt.point(-ufoW,     h * 0.50),
                Qt.point(w * 0.75,  h + ufoH)
            ]
        } else if (side === 2) {
            waypoints = [
                Qt.point(w + ufoW,  h * 0.50),
                Qt.point(w * 0.75,  h + ufoH),
                Qt.point(w * 0.50, -h * 0.25),
                Qt.point(-ufoW,     h * 0.75)
            ]
        } else {
            waypoints = [
                Qt.point(w * 0.50,  h + ufoH),
                Qt.point(-ufoW,     h * 0.75),
                Qt.point(w + ufoW,  h * 0.50),
                Qt.point(w * 0.25, -ufoH)
            ]
        }

        var obj = ufoComponent.createObject(asteroidLayer, {
            "x":               waypoints[0].x - ufoW / 2,
            "y":               waypoints[0].y - ufoH / 2,
            "waypoints":       waypoints,
            "currentWaypoint": 1
        })
        activeAsteroids.push(obj)
        ufoObject = obj
        ufoActive = true
    }

    function destroyUfo() {
        ufoCooldownTimer.stop()
        if (ufoObject) {
            var idx = activeAsteroids.indexOf(ufoObject)
            if (idx !== -1) activeAsteroids.splice(idx, 1)
            ufoObject.destroy()
            ufoObject = null
        }
        ufoActive = false
        if (!gameOver) ufoSpawnTimer.restart()
    }

    // ── Power-ups ─────────────────────────────────────────────────────────────

    function handleUfoHit(ufoRef) {
        var type  = ufoRef.powerupTypes[ufoRef.colorIndex]
        var color = ufoRef.powerupColors[ufoRef.colorIndex]

        ufoRef.dimmed = true

        var cx  = ufoRef.x + ufoRef.width  / 2
        var cy  = ufoRef.y + ufoRef.height / 2
        var sm  = 1.333
        explosionParticleComponent.createObject(vfxLayer, {
            "x": cx - ufoSize * 1.86 * sm / 2,
            "y": cy - ufoSize * 1.86 * sm / 2,
            "dimsFactor":     dimsFactor,
            "asteroidSize":   ufoSize,
            "explosionColor": "custom",
            "customColor": Qt.vector3d(
                parseInt(color.slice(1, 3), 16) / 255,
                parseInt(color.slice(3, 5), 16) / 255,
                parseInt(color.slice(5, 7), 16) / 255
            )
        })

        activatePowerup(type, color)
        feedback.play()
    }

    function activatePowerup(type, color) {
        var labels = {
            "wide":   "WIDE RAZZ",
            "rapid":  "RAPID HYPE",
            "triple": "TRIPLE DANK",
            "pierce": "QUAD PIERCE",
            "frenzy": "SCORE FRENZY",
            "shield": "THICCER SHIELD",
            "nuke":   "NUKE WIPE",
            "laser":  "YEET LASER",
            "chain":  "GIB CHAIN BOLT"
        }
        powerupLabel = labels[type] || type.toUpperCase()
        popupAnim.restart()

        if (type === "nuke") {
            glowColor = color
            nukeField()
            powerupTimer.interval = 500
            powerupTimer.restart()
            return
        }
        if (type === "shield") {
            shield += 1
            glowColor = color
            powerupTimer.interval = 500
            powerupTimer.restart()
            return
        }
        activePowerup = type
        glowColor = color
        powerupBarFill.width = powerupBarContainer.width
        powerupBarAnim.duration = balance.powerupDuration
        powerupBarAnim.restart()
        powerupTimer.interval = balance.powerupDuration
        powerupTimer.restart()
    }

    function nukeField() {
        for (var i = activeAsteroids.length - 1; i >= 0; i--) {
            var a = activeAsteroids[i]
            if (!a || a.isUfo) continue
            var sm = a.asteroidSize === "large" ? 1.0 : a.asteroidSize === "mid" ? 1.25 : 1.333
            explosionParticleComponent.createObject(vfxLayer, {
                "x": a.x + a.width  / 2 - a.size * 1.86 * sm / 2,
                "y": a.y + a.height / 2 - a.size * 1.86 * sm / 2,
                "dimsFactor":     dimsFactor,
                "asteroidSize":   a.size,
                "explosionColor": "nuke"
            })
            activeAsteroids.splice(i, 1)
            a.destroy()
        }
        scorePerimeter.border.color = "#FFFFFF"
        scorePerimeter.color = "#1A1A2E"
        perimeterFlashTimer.restart()
        feedback.play()
        checkLevelComplete()
    }

    // ── Asteroid spawning ─────────────────────────────────────────────────────

    function spawnLargeAsteroid() {
        var size = dimsFactor * 18
        var side = Math.floor(Math.random() * 4)
        var spawnX, spawnY, targetX, targetY
        switch (side) {
            case 0:
                spawnX  = Math.random() * root.width;  spawnY  = -size
                targetX = Math.random() * root.width;  targetY = root.height + size
                break
            case 1:
                spawnX  = root.width + size;           spawnY  = Math.random() * root.height
                targetX = -size;                       targetY = Math.random() * root.height
                break
            case 2:
                spawnX  = Math.random() * root.width;  spawnY  = root.height + size
                targetX = Math.random() * root.width;  targetY = -size
                break
            case 3:
                spawnX  = -size;                       spawnY  = Math.random() * root.height
                targetX = root.width + size;           targetY = Math.random() * root.height
                break
        }
        var dx  = targetX - spawnX
        var dy  = targetY - spawnY
        var mag = Math.sqrt(dx * dx + dy * dy)
        activeAsteroids.push(asteroidComponent.createObject(asteroidLayer, {
            "x": spawnX, "y": spawnY,
            "size": size,
            "directionX": dx / mag, "directionY": dy / mag,
            "asteroidSize": "large"
        }))
    }

    function spawnSplitAsteroids(sizeType, size, count, x, y, directionX, directionY) {
        var rad = Math.atan2(directionY, directionX)
        for (var i = 0; i < count; i++) {
            var newRad = rad + (i === 0 ? -1 : 1) * 45 * Math.PI / 180
            activeAsteroids.push(asteroidComponent.createObject(asteroidLayer, {
                "x": x, "y": y,
                "size": size,
                "directionX": Math.cos(newRad), "directionY": Math.sin(newRad),
                "asteroidSize": sizeType
            }))
        }
    }

    function destroyAsteroid(asteroid) {
        var index = activeAsteroids.indexOf(asteroid)
        if (index !== -1) {
            activeAsteroids.splice(index, 1)
            asteroid.destroy()
            checkLevelComplete()
        }
    }

    function checkLevelComplete() {
        var waveCount = 0
        for (var i = 0; i < activeAsteroids.length; i++) {
            if (!activeAsteroids[i].isUfo && activeAsteroids[i].asteroidSize !== "small") waveCount++
        }
        if (waveCount === 0 && asteroidsSpawned >= initialAsteroidsToSpawn) {
            level++
            var ul = ""
            if      (level === 2)  ul = "PIERCE UNLOCKED"
            else if (level === 3)  ul = "WIDE UNLOCKED"
            else if (level === 4)  ul = "TRIPLE UNLOCKED"
            else if (level === 6)  ul = "RAPID UNLOCKED"
            else if (level === 8)  ul = "LASER UNLOCKED"
            else if (level === 10) ul = "CHAIN BOLT UNLOCKED"
            else if (level === 12) ul = "NUKE UNLOCKED"
            if (ul !== "") { unlockLabel = ul; unlockAnim.restart() }
            initialAsteroidsToSpawn = balance.spawnCountBase + level
            asteroidsSpawned = 0
            spawnLargeAsteroid()
            asteroidsSpawned++
            asteroidSpawnTimer.restart()
        }
    }

    // ── Collision detection ───────────────────────────────────────────────────

    function pointInPolygon(x, y, points) {
        var inside = false
        for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
            var xi = points[i].x, yi = points[i].y
            var xj = points[j].x, yj = points[j].y
            if (((yi > y) !== (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi))
                inside = !inside
        }
        return inside
    }

    function checkShotUfoCollision(shot, ufoRef) {
        var rx  = ufoRef.width  / 2
        var ry  = ufoRef.height / 2
        var cx  = ufoRef.x + rx
        var cy  = ufoRef.y + ry
        var scx = shot.x + shot.width  / 2
        var scy = shot.y + shot.height / 2
        var ndx = (scx - cx) / rx
        var ndy = (scy - cy) / ry
        return (ndx * ndx + ndy * ndy) <= 1.0
    }

    function checkShotAsteroidCollision(shot, asteroid) {
        var sl = shot.x,           sr = shot.x + shot.width
        var st = shot.y,           sb = shot.y + shot.height
        for (var i = 0; i < asteroid.asteroidPoints.length; i++) {
            var px = asteroid.x + asteroid.asteroidPoints[i].x
            var py = asteroid.y + asteroid.asteroidPoints[i].y
            if (px >= sl && px <= sr && py >= st && py <= sb) return true
        }
        var corners = [
            { x: sl, y: st }, { x: sr, y: st },
            { x: sr, y: sb }, { x: sl, y: sb }
        ]
        for (var j = 0; j < corners.length; j++) {
            if (pointInPolygon(corners[j].x - asteroid.x, corners[j].y - asteroid.y, asteroid.asteroidPoints))
                return true
        }
        return false
    }

    function handleShotAsteroidCollision(shot, asteroid) {
        var acx  = asteroid.x + asteroid.width  / 2
        var acy  = asteroid.y + asteroid.height / 2
        var dist = Math.sqrt(
            Math.pow(acx - root.width  / 2, 2) +
            Math.pow(acy - root.height / 2, 2)
        )
        var inside = dist < dimsFactor * balance.perimeterRadius
        var base   = asteroid.asteroidSize === "small" ? balance.pointsSmall
                   : asteroid.asteroidSize === "mid"   ? balance.pointsMid
                   :                                     balance.pointsLarge
        var frenzy = activePowerup === "frenzy" ? balance.perimeterBonusMult : 1.0
        var points = inside
            ? Math.round(base * balance.perimeterBonusMult * frenzy)
            : Math.round(base * frenzy)
        score += points

        var sm = asteroid.asteroidSize === "large" ? 1.0 : asteroid.asteroidSize === "mid" ? 1.25 : 1.333
        explosionParticleComponent.createObject(vfxLayer, {
            "x": acx - asteroid.size * 1.86 * sm / 2,
            "y": acy - asteroid.size * 1.86 * sm / 2,
            "dimsFactor":     dimsFactor,
            "asteroidSize":   asteroid.size,
            "explosionColor": "default"
        })
        scoreParticleComponent.createObject(vfxLayer, {
            "x": acx - dimsFactor * 4,
            "y": acy - dimsFactor * 4,
            "dimsFactor": dimsFactor,
            "text": "+" + points,
            "color": inside
                ? (activePowerup === "frenzy" ? "#FFAA00" : "#00FFFF")
                : "#67AAF9"
        })

        if (inside) {
            scorePerimeter.border.color = activePowerup === "frenzy" ? "#FFAA00" : "#FFFFFF"
            scorePerimeter.color = "#074588"
            perimeterFlashTimer.restart()
        }

        asteroid.split()

        if (shot.chaining && shot.generation < 3) {
            var cx2 = asteroid.x + asteroid.width  / 2
            var cy2 = asteroid.y + asteroid.height / 2
            var targets = []
            for (var ci = 0; ci < activeAsteroids.length; ci++) {
                var ca = activeAsteroids[ci]
                if (!ca || ca.isUfo) continue
                var cdx = (ca.x + ca.width  / 2) - cx2
                var cdy = (ca.y + ca.height / 2) - cy2
                targets.push({ asteroid: ca, dist: Math.sqrt(cdx * cdx + cdy * cdy) })
            }
            targets.sort(function(a, b) { return a.dist - b.dist })
            var forkCount = Math.min(3, targets.length)
            for (var fi = 0; fi < forkCount; fi++) {
                var ta  = targets[fi].asteroid
                var tdx = (ta.x + ta.width  / 2) - cx2
                var tdy = (ta.y + ta.height / 2) - cy2
                var tmg = Math.sqrt(tdx * tdx + tdy * tdy)
                if (tmg === 0) continue
                var fs = autoFireShotComponent.createObject(shotLayer, {
                    "x": cx2, "y": cy2,
                    "directionX": tdx / tmg,
                    "directionY": tdy / tmg,
                    "rotation":   Math.atan2(tdx, -tdy) * 180 / Math.PI,
                    "shotColor":  "#2299FF",
                    "width":      dimsFactor * 2,
                    "speed":      balance.shotSpeed * 0.85,
                    "chaining":   true,
                    "generation": shot.generation + 1
                })
                activeShots.push(fs)
            }
        }
    }

    function checkPlayerAsteroidCollision(playerHitbox, asteroid) {
        var ah = (shield > 0) ? shieldHitbox : playerHitbox
        var px = playerContainer.x + ah.x
        var py = playerContainer.y + ah.y
        var corners = [
            { x: px,            y: py            },
            { x: px + ah.width, y: py            },
            { x: px + ah.width, y: py + ah.height },
            { x: px,            y: py + ah.height }
        ]
        for (var i = 0; i < corners.length; i++) {
            if (pointInPolygon(corners[i].x - asteroid.x, corners[i].y - asteroid.y, asteroid.asteroidPoints))
                return true
        }
        var pl = px, pr = px + ah.width, pt = py, pb = py + ah.height
        for (var j = 0; j < asteroid.asteroidPoints.length; j++) {
            var apx = asteroid.x + asteroid.asteroidPoints[j].x
            var apy = asteroid.y + asteroid.asteroidPoints[j].y
            if (apx >= pl && apx <= pr && apy >= pt && apy <= pb) return true
        }
        return false
    }

    function handlePlayerAsteroidCollision(asteroid) {
        if (shield > 0) {
            shield -= 1
            var index = activeAsteroids.indexOf(asteroid)
            if (index !== -1) activeAsteroids.splice(index, 1)
            var sm = asteroid.asteroidSize === "large" ? 1.0
                   : asteroid.asteroidSize === "mid"   ? 1.25 : 1.333
            explosionParticleComponent.createObject(vfxLayer, {
                "x": asteroid.x + asteroid.width  / 2 - asteroid.size * 1.86 * sm / 2,
                "y": asteroid.y + asteroid.height / 2 - asteroid.size * 1.86 * sm / 2,
                "dimsFactor":     dimsFactor,
                "asteroidSize":   asteroid.size,
                "explosionColor": "shield"
            })
            asteroid.destroy()
            feedback.play()
        } else {
            gameOver = true
            asteroidSpawnTimer.stop()
            ufoSpawnTimer.stop()
            powerupTimer.stop()
            ufoCooldownTimer.stop()
            activePowerup = ""
            glowColor = "#00000000"
            destroyUfo()
            for (var i = 0; i < activeAsteroids.length; i++) {
                if (activeAsteroids[i]) activeAsteroids[i].destroy()
            }
            for (var j = 0; j < activeShots.length; j++) {
                if (activeShots[j]) activeShots[j].destroy()
            }
            activeAsteroids = []
            activeShots = []
            feedback.play()
        }
    }

    function checkCollision(a1, a2) {
        var dx = (a1.x + a1.width  / 2) - (a2.x + a2.width  / 2)
        var dy = (a1.y + a1.height / 2) - (a2.y + a2.height / 2)
        return Math.sqrt(dx * dx + dy * dy) < (a1.size + a2.size) / 2
    }

    function handleAsteroidCollision(a1, a2) {
        var nx = (a2.x + a2.width  / 2) - (a1.x + a1.width  / 2)
        var ny = (a2.y + a2.height / 2) - (a1.y + a1.height / 2)
        var mag = Math.sqrt(nx * nx + ny * ny)
        if (mag === 0) return
        nx /= mag; ny /= mag

        var v1x = a1.directionX * a1.speed,  v1y = a1.directionY * a1.speed
        var v2x = a2.directionX * a2.speed,  v2y = a2.directionY * a2.speed
        var m1  = a1.mass,  m2 = a2.mass,  tm = m1 + m2

        var d1  = v1x * nx + v1y * ny
        var d2  = v2x * nx + v2y * ny
        var nd1 = (d1 * (m1 - m2) + 2 * m2 * d2) / tm
        var nd2 = (d2 * (m2 - m1) + 2 * m1 * d1) / tm

        var nv1x = v1x - d1 * nx + nd1 * nx,  nv1y = v1y - d1 * ny + nd1 * ny
        var nv2x = v2x - d2 * nx + nd2 * nx,  nv2y = v2y - d2 * ny + nd2 * ny

        var mag1 = Math.sqrt(nv1x * nv1x + nv1y * nv1y)
        var mag2 = Math.sqrt(nv2x * nv2x + nv2y * nv2y)
        if (mag1 > 0) { a1.directionX = nv1x / mag1; a1.directionY = nv1y / mag1 }
        if (mag2 > 0) { a2.directionX = nv2x / mag2; a2.directionY = nv2y / mag2 }

        var overlap = (a1.size + a2.size) / 2 - mag
        if (overlap > 0) {
            var push = overlap * balance.collisionPushFactor
            a1.x -= nx * push * (m2 / tm);  a1.y -= ny * push * (m2 / tm)
            a2.x += nx * push * (m1 / tm);  a2.y += ny * push * (m1 / tm)
        }
    }

    function restartGame() {
        score  = 0
        shield = balance.startingShields
        level  = 1
        gameOver    = false
        paused      = false
        calibrating = false
        calibrationTimer = 4
        lastFrameTime    = 0
        playerRotation   = 0
        initialAsteroidsToSpawn = balance.initialSpawnCount
        asteroidsSpawned = 0
        playerContainer.x = centerX
        playerContainer.y = centerY

        powerupTimer.stop()
        activePowerup = ""
        glowColor = "#00000000"
        powerupLabel = ""

        destroyUfo()

        for (var i = 0; i < activeShots.length; i++) {
            if (activeShots[i]) activeShots[i].destroy()
        }
        for (var j = 0; j < activeAsteroids.length; j++) {
            if (activeAsteroids[j]) activeAsteroids[j].destroy()
        }
        activeShots = []
        activeAsteroids = []

        asteroidSpawnTimer.restart()
        ufoSpawnTimer.restart()
    }

    Component.onCompleted:   { DisplayBlanking.preventBlanking = true  }
    Component.onDestruction: { DisplayBlanking.preventBlanking = false }
}
