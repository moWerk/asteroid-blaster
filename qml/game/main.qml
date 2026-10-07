/*
 * Copyright (C) 2026 - Timo Könnecke <github.com/moWerk>
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

import QtQuick 2.6
import QtSensors 5.2
import QtFeedback 5.0
import "."
import Nemo.KeepAlive 1.2
import Nemo.Configuration 1.0

Item {
    id: root
    anchors.fill: parent
    visible: true

    // ── Balance block ─────────────────────────────────────────────────────────
    QtObject {
        id: balance

        // Spawning
        readonly property int   initialSpawnCount:     8
        readonly property int   spawnCountBase:        6      // asteroids per wave = spawnCountBase + level
        readonly property int   spawnIntervalStart:    2000   // ms between spawns at level 1, decreases each level
        readonly property int   spawnIntervalFloor:    300    // minimum ms between spawns, never goes below this
        readonly property int   spawnIntervalStep:     100    // ms reduction per level on the spawn interval
        readonly property int   midAsteroidCap:        20
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
        readonly property int   powerupDuration:       10000
        readonly property real  pierceFourwayFireMult: 1.333

        // Physics
        readonly property real  playerProximityRange:  20
        readonly property real  collisionPushFactor:   0.5

        // Free flight (speeds in asteroid speed units: px per 60 fps frame,
        // before speedScale; a large asteroid moves 0.27)
        readonly property real  ffThrust:              1.5    // gained per second at full tilt
        readonly property real  ffMaxSpeed:            2.0    // also the speed of the widest zoom
        readonly property real  ffDrag:                0.25   // per second while coasting
        readonly property real  ffBrake:               2.5    // per second at full back tilt
        readonly property real  ffTiltDeadzone:        0.5    // m/s² of pitch ignored
        readonly property real  ffTiltFull:            3.0    // m/s² of pitch for full thrust
        readonly property real  ffZoomMin:             0.625  // 1.6x view; the world is 2x, so its seam stays hidden
        readonly property real  ffLeadMax:             0.12   // largest ship offset, share of the screen width
        readonly property int   ffCountMult:           2      // asteroid counts and caps, for 4x the area

        // UFO fights back (free flight; as in the original Asteroids)
        readonly property bool  ufoFiresInIdle:        false
        readonly property int   ufoFireMult:           10     // fires at a tenth of the player's rate
        readonly property real  ufoShotSpeed:          4      // half the player's shot speed: dodgeable
        readonly property real  ufoAimSharp:           2      // degrees of error inside the bonus circle
        readonly property real  ufoAimLoose:           40     // degrees of error a screen width away
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
    // Speeds are tuned in pixels per frame on a watch. Scale them with the
    // shorter screen side so the game plays the same on a larger screen:
    // 1.0 at 480 px, 1.5 on a 720 px wide phone.
    property real speedScale: Dims.l(100) / 480
    property var  activeShots: []
    property var  ufoShots: []
    property var  activeAsteroids: []
    property real lastFrameTime: 0
    property real baselineX: 0
    property real smoothedX: 0
    property real baselineY: 0
    property real smoothedY: 0
    property real playerRotation: 0
    // free flight spreads the asteroids over four times the area
    readonly property int countMult: freeFlight ? balance.ffCountMult : 1
    property int  initialAsteroidsToSpawn: balance.initialSpawnCount * countMult
    property int  asteroidsSpawned: 0

    property real centerX: root.width  / 2
    property real centerY: root.height / 2

    // ── Free flight (SailfishOS) ──────────────────────────────────────────────
    // Idle mode: the ship sits in the centre and only turns. Free flight: the
    // ship has a velocity, and the camera follows it. The ship stays near the
    // centre; asteroids, the UFO and effects move by their own velocity minus
    // the ship's, inside a world twice the screen in each direction that wraps
    // around. The faster the ship, the further the view zooms out.
    // The world box, in the screen-centred coordinates everything lives in.
    // In idle mode it is exactly the screen, so idle play is unchanged.
    property bool freeFlight: GameStorage.mode === "free"
    readonly property real worldLeft: freeFlight ? -root.width  / 2 : 0
    readonly property real worldTop:  freeFlight ? -root.height / 2 : 0
    readonly property real worldW:    freeFlight ? root.width  * 2 : root.width
    readonly property real worldH:    freeFlight ? root.height * 2 : root.height
    property real shipVX: 0           // ship velocity, in asteroid speed units
    property real shipVY: 0
    property real leadX: 0            // ship and bonus circle offset from the centre
    property real leadY: 0
    property real zoom: 1

    // UFO state
    property bool ufoActive: false
    property var  ufoObject: null
    property bool playerDying: false
    readonly property real ufoSize: dimsFactor * 8

    // Power-up state
    property string activePowerup: ""
    property color  glowColor: "#00000000"
    property string powerupLabel: ""
    property string unlockLabel: ""
    property string pendingUnlockType: ""

    // Haptics through QtFeedback's ThemeEffect: Nemo.Ngf is not allowed in
    // the Jolla Store, ThemeEffect with Press* is.
    ThemeEffect {
        id: feedback
        effect: ThemeEffect.Press
    }

    onGameOverChanged: {
        if (gameOver && freeFlight) {
            GameStorage.highScoreFree = score
            GameStorage.highLevelFree = level
        } else if (gameOver) {
            GameStorage.highScore = score
            GameStorage.highLevel = level
        }
    }

    onCalibratingChanged: {
        if (!calibrating) ufoSpawnTimer.restart()
    }

    onLevelChanged: {
        if (!calibrating && level > 1) {
            levelFlashAnim.restart()
            levelColorAnim.restart()
        }
    }

    // ── Timers ────────────────────────────────────────────────────────────────

    Timer {
        id: gameTimer
        interval: 16
        running: !gameOver && !calibrating && !paused && !playerDying
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
            if (selftest.active) deltaX = selftest.turn
            playerRotation += deltaX * balance.tiltRotationSpeed * deltaTime
            playerRotation = (playerRotation + 360) % 360
            if (freeFlight) updateShip(deltaTime)

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
                baselineY = accelerometer.reading.y
                smoothedY = baselineY
                console.log("calibrated x " + baselineX.toFixed(2) + " y " + baselineY.toFixed(2) + " free flight " + freeFlight)
                calibrating = false
                feedback.play()
            }
        }
    }

    Timer {
        id: autoFireTimer
        interval: activePowerup === "rapid" ? balance.rapidFireInterval : activePowerup === "pierce" ? Math.round(balance.fireInterval * balance.pierceFourwayFireMult) : activePowerup === "laser" ? Math.round(balance.fireInterval * balance.laserFireMult) : balance.fireInterval
        running: !gameOver && !calibrating && !paused && !playerDying
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

    // The UFO fires back while it is on screen: aimed at where the ship will
    // be, sharp at close range, loosely in the ship's direction from afar.
    Timer {
        id: ufoFireTimer
        interval: balance.fireInterval * balance.ufoFireMult
        running: ufoActive && (freeFlight || balance.ufoFiresInIdle)
                 && !gameOver && !calibrating && !paused && !playerDying
        repeat: true
        onTriggered: ufoFire()
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
            powerupBarContainer.opacity = 0
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
    
    Timer {
        id: unlockGiftTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (activePowerup === "" && pendingUnlockType !== "") {
                var giftColors = {
                    "wide": "#FF44AA", "rapid": "#AA44FF", "triple": "#33FF66",
                    "pierce": "#DDCC00", "laser": "#00FFAA", "chain": "#2299FF", "nuke": "#FFFFFF"
                }
                activatePowerup(pendingUnlockType, giftColors[pendingUnlockType])
                if (ufoObject) ufoObject.dimmed = true
            }
            pendingUnlockType = ""
        }
    }
    
    Timer {
        id: deathSequenceTimer
        interval: 1000
        repeat: false
        onTriggered: {
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
            clearUfoShots()
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
        id: ufoShotComponent
        Rectangle {
            width:  dimsFactor * 2
            height: width
            radius: width / 2
            color:  "#FF3355"
            property real vx: 0     // world velocity, asteroid speed units
            property real vy: 0
            property real age: 0
        }
    }

    Component {
        id: scoreParticleComponent
        ScoreParticle { }
    }

    Component {
        id: deathShaderComponent
        DeathShader { }
    }
    
    Component {
        id: asteroidComponent
        Item {
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

            // SailfishOS (Qt 5.6) has no QtQuick.Shapes: the outline is drawn
            // once on a Canvas and repainted only when the pause look changes.
            Canvas {
                id: asteroidCanvas
                anchors.fill: parent
                property bool dim: paused
                onDimChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var pts = asteroid.asteroidPoints
                    ctx.lineWidth = dimsFactor * 1
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    ctx.strokeStyle = dim ? "#444444" : "white"
                    ctx.fillStyle = "#222222"
                    ctx.beginPath()
                    ctx.moveTo(pts[0].x, pts[0].y)
                    for (var i = 1; i < pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y)
                    ctx.closePath()
                    if (!dim) ctx.fill()
                    ctx.stroke()
                }
            }

            function split() {
                if (asteroidSize === "large"
                        && activeAsteroids.filter(function(a) { return !a.isUfo && a.asteroidSize === "mid" }).length < balance.midAsteroidCap * countMult) {
                    spawnSplitAsteroids("mid", dimsFactor * 12, 2, x, y, directionX, directionY)
                } else if (asteroidSize === "mid"
                        && activeAsteroids.filter(function(a) { return !a.isUfo && a.asteroidSize === "small" }).length < balance.smallAsteroidCap * countMult) {
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
        Rectangle {
            id: backgroundRect
            anchors.fill: parent
            color: "black"
            
            SequentialAnimation {
                id: levelFlashAnim
                ColorAnimation { target: backgroundRect; property: "color"; to: "#00CCCC"; duration: 200 }
                ColorAnimation { target: backgroundRect; property: "color"; to: "black";   duration: 800 }
            }
        }

        Item {
            id: gameContent
            anchors.fill: parent

            // SailfishOS: the world layers, scaled by the free flight zoom around
            // the screen centre. The scale is visual only: positions, sizes and
            // hit tests stay in world units. The HUD stays outside, unscaled.
            Item {
                id: worldView
                anchors.fill: parent
                scale: zoom
                transformOrigin: Item.Center

                // free flight: faint dust that drifts against the flight at
                // half the speed, so motion shows when no asteroid is near
                Item {
                    id: dustLayer
                    anchors.fill: parent
                    visible: freeFlight && !calibrating
                    Repeater {
                        id: dust
                        model: freeFlight ? 48 : 0
                        Rectangle {
                            width:   dimsFactor * (0.4 + (index % 3) * 0.25)
                            height:  width
                            radius:  width / 2
                            color:   "#7788AA"
                            opacity: 0.25 + (index % 4) * 0.1
                            x: worldLeft + Math.random() * worldW
                            y: worldTop  + Math.random() * worldH
                        }
                    }
                }

                Rectangle {
                    id: scorePerimeter
                    width:  dimsFactor * 55
                    height: dimsFactor * 55
                    radius: dimsFactor * 27.5
                    color: "#010A13"
                    border.color: "#0860C4"
                    border.width: 1
                    // follows the ship's lead offset; the double score is measured
                    // from this circle's centre (handleShotAsteroidCollision)
                    x: root.width  / 2 - width  / 2 + leadX
                    y: root.height / 2 - height / 2 + leadY
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
                    x: root.width  / 2 - player.width  / 2 + dimsFactor * 5 + leadX
                    y: root.height / 2 - player.height / 2 + dimsFactor * 5 + leadY
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
                        source: "img/asteroid-logo.png"
                        anchors.centerIn: parent
                        rotation: playerRotation
                    }

                    // never drawn; only its geometry is used
                    Item {
                        id: playerHitbox
                        width:  dimsFactor * 10
                        height: dimsFactor * 10
                        anchors.centerIn: parent
                        visible: false
                        rotation: playerRotation
                    }

                    Item {
                        id: shieldHitbox
                        width:  dimsFactor * 14
                        height: dimsFactor * 14
                        anchors.centerIn: parent
                        visible: shield > 0
                        opacity: shield >= 4 ? 1.0
                        : shield === 3 ? 0.8
                        : shield === 2 ? 0.6
                        : shield === 1 ? 0.4 : 0.0
                        rotation: playerRotation
                        // diamond outline = square rotated by 45 degrees
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width / Math.SQRT2
                            height: width
                            rotation: 45
                            color: "transparent"
                            border.width: 2
                            border.color: "#DD1155"
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
            }

            // SailfishOS: the HUD is laid out for a square watch screen. On a
            // tall phone it stays in a centred square as wide as the screen;
            // only the asteroid field uses the full height.
            Item {
                id: hudSquare
                width: parent.width
                height: Math.min(parent.width, parent.height)
                anchors.centerIn: parent

                // ── HUD

                Text {
                    id: levelNumber
                    text: level
                    color: "#00FFFF"
                    font { pixelSize: dimsFactor * 12; family: "Teko"; styleName: "SemiBold" }
                    anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                    visible: !calibrating
                
                    SequentialAnimation {
                        id: levelColorAnim
                        ColorAnimation { target: levelNumber; property: "color"; to: "#FFAA00"; duration: 200 }
                        ColorAnimation { target: levelNumber; property: "color"; to: "#00FFFF"; duration: 800 }
                    }
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
                    opacity: 0
                
                    SequentialAnimation {
                        id: barOpacityAnim
                        NumberAnimation { target: powerupBarContainer; property: "opacity"; to: 1.0; duration: 200; easing.type: Easing.InQuad }
                        PauseAnimation  { duration: balance.powerupDuration - 1200 }
                        NumberAnimation { target: powerupBarContainer; property: "opacity"; to: 0.0; duration: 1000; easing.type: Easing.InQuad }
                    }
                
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
                        topMargin: dimsFactor * 4
                        horizontalCenter: parent.horizontalCenter
                    }
                    opacity: 0
                    visible: !calibrating && !gameOver

                    SequentialAnimation {
                        id: unlockAnim
                        NumberAnimation { target: powerupUnlock; property: "opacity"; to: 0.85; duration: 400 }
                        PauseAnimation  { duration: 1600 }
                        NumberAnimation { target: powerupUnlock; property: "opacity"; to: 0.0; duration: 1600; easing.type: Easing.InQuad }
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
                    font { pixelSize: dimsFactor * 13; family: "Teko"; styleName: activePowerup === "frenzy" ? "Medium" : "Light" }
                    anchors {
                        bottom: shieldText.top
                        bottomMargin: -dimsFactor * 8.4
                        horizontalCenter: parent.horizontalCenter
                    }
                    visible: !gameOver && !calibrating
                    Behavior on color { ColorAnimation { duration: 300 } }
                }

                Text {
                    id: shieldText
                    text: shield
                    color: "#DD1155"
                    opacity: shield > 0 ? 1 : 0
                    font { pixelSize: dimsFactor * 12; family: "Teko"; styleName: "SemiBold" }
                    anchors {
                        bottom: parent.bottom
                        bottomMargin: -dimsFactor * 5
                        horizontalCenter: parent.horizontalCenter
                    }
                    visible: !calibrating && !gameOver
                
                    SequentialAnimation on opacity {
                        running: shield <= 0
                        loops:   Animation.Infinite
                        NumberAnimation { to: 0; duration: 300; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1; duration: 300; easing.type: Easing.InOutQuad }
                        onRunningChanged: { if (!running) shieldText.opacity = 1 }
                    }
                }
            }

            // ── Calibration ───────────────────────────────────────────────────
            Item {
                id: calibrationContainer
                anchors.fill: parent
                visible: calibrating

                Text {
                    text: "v2.2\nAsteroid Blaster"
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
                        text: "Hold your phone comfy"
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
                        baselineY = accelerometer.reading.y
                        smoothedY = baselineY
                        console.log("calibrated x " + baselineX.toFixed(2) + " y " + baselineY.toFixed(2) + " free flight " + freeFlight)
                        calibrating = false
                        feedback.play()
                    }
                }

                // SailfishOS: idle (the ship turns, the field comes to it) or
                // free flight (the ship flies, the camera follows)
                Item {
                    anchors { top: calibrationText.bottom; topMargin: dimsFactor * 12; horizontalCenter: parent.horizontalCenter }
                    width: modeColumn0.width
                    height: modeColumn0.height
                    Column {
                        id: modeColumn0
                        spacing: dimsFactor * 0.5
                        Text {
                            text: freeFlight ? "FREE FLIGHT" : "IDLE"
                            color: freeFlight ? "#FFAA00" : "#00FFFF"
                            font { family: "Teko"; pixelSize: dimsFactor * 11; styleName: "SemiBold"; letterSpacing: dimsFactor * 0.3 }
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: "tap to switch mode"
                            color: "#888888"
                            font.pixelSize: dimsFactor * 5
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            visible: freeFlight
                            text: "tilt sideways to turn, away to thrust, back to brake"
                            width: root.width * 0.8
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            color: "#888888"
                            font.pixelSize: dimsFactor * 5
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -dimsFactor * 4
                        onClicked: {
                            GameStorage.mode = freeFlight ? "idle" : "free"
                            calibrationTimer = 3   // a new mode gets a fresh countdown
                        }
                    }
                }
            }

            // ── Dimming overlay ───────────────────────────────────────────────
            Rectangle {
                id: dimmingLayer
                anchors.fill: parent
                color: "#000000"
                opacity: (paused && !gameOver && !calibrating) || gameOver ? 0.8 : 0.0
                Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
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
                color: "#DDFFFFFF"
                font { pixelSize: dimsFactor * 19; family: "Teko"; styleName: "Medium" }
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
                font { pixelSize: dimsFactor * 12; family: "Teko"; letterSpacing: dimsFactor * 0.34 }
                anchors {
                    bottom: parent.verticalCenter
                    bottomMargin: dimsFactor * 1
                    horizontalCenter: parent.horizontalCenter
                }
            }

            Text {
                text: freeFlight
                      ? "Highscore: " + GameStorage.highScoreFree + "\nLevel: " + GameStorage.highLevelFree
                      : "Highscore: " + GameStorage.highScore + "\nLevel: " + GameStorage.highLevel
                horizontalAlignment: Text.AlignHCenter
                color: "#FFAA00"
                lineHeightMode: Text.ProportionalHeight
                lineHeight: 0.6
                font { pixelSize: dimsFactor * 10.4; family: "Teko"; letterSpacing: dimsFactor * 0.34 }
                anchors {
                    top: parent.verticalCenter
                    topMargin: dimsFactor * 0.8
                    horizontalCenter: parent.horizontalCenter
                }
            }

            Rectangle {
                id: tryAgainButton
                width: dimsFactor * 50; height: dimsFactor * 19
                radius: dimsFactor * 2
                color: "#444444"
                anchors {
                    top: parent.verticalCenter
                    topMargin: dimsFactor * 24
                    horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "Try Again"
                    color: "white"
                    font { pixelSize: dimsFactor * 11; family: "Teko"; styleName: "SemiBold" }
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: dimsFactor * 0.6
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { restartGame() }
                }
            }

            // SailfishOS: idle (the ship turns, the field comes to it) or
            // free flight (the ship flies, the camera follows)
            Item {
                anchors { top: tryAgainButton.bottom; topMargin: dimsFactor * 8; horizontalCenter: parent.horizontalCenter }
                width: modeColumn1.width
                height: modeColumn1.height
                Column {
                    id: modeColumn1
                    spacing: dimsFactor * 0.5
                    Text {
                        text: freeFlight ? "FREE FLIGHT" : "IDLE"
                        color: freeFlight ? "#FFAA00" : "#00FFFF"
                        font { family: "Teko"; pixelSize: dimsFactor * 11; styleName: "SemiBold"; letterSpacing: dimsFactor * 0.3 }
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: "tap to switch mode"
                        color: "#888888"
                        font.pixelSize: dimsFactor * 5
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        visible: freeFlight
                        text: "tilt sideways to turn, away to thrust, back to brake"
                        width: root.width * 0.8
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        color: "#888888"
                        font.pixelSize: dimsFactor * 5
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -dimsFactor * 4
                    onClicked: {
                        GameStorage.mode = freeFlight ? "idle" : "free"
                    }
                }
            }
        }

        // Test hook (set from main.cpp): log the sensor once a second
        Timer {
            interval: 1000
            repeat: true
            running: typeof selftestSensor !== "undefined" && selftestSensor
            onTriggered: console.log("selftest accelerometer backend=" + accelerometer.connectedToBackend
                                     + " xyz=" + (accelerometer.reading ? accelerometer.reading.x.toFixed(2) + ","
                                                   + accelerometer.reading.y.toFixed(2) + ","
                                                   + accelerometer.reading.z.toFixed(2) : "none"))
        }

        Accelerometer {
            id: accelerometer
            active: true
        }

        // Test hook: dconf keys under /apps/harbour-asteroid-blaster/selftest
        // (active, thrust 0..1, turn -1..1) steer the ship without tilting,
        // for checks over ssh. Ignored unless active is set.
        ConfigurationGroup {
            id: selftest
            path: "/apps/harbour-asteroid-blaster/selftest"
            property bool active: false
            property real thrust: 0
            property real turn: 0
        }
    }

    // ── Game logic ────────────────────────────────────────────────────────────

    function updateGame(deltaTime) {

        for (var si = activeShots.length - 1; si >= 0; si--) {
            var shot = activeShots[si]
            if (!shot) continue

            shot.x += shot.directionX * shot.speed * speedScale * deltaTime * 60
            shot.y += shot.directionY * shot.speed * speedScale * deltaTime * 60

            if (shot.y <= worldTop  - shot.height || shot.y >= worldTop  + worldH ||
                shot.x <= worldLeft - shot.width  || shot.x >= worldLeft + worldW) {
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

        for (var ui = ufoShots.length - 1; ui >= 0; ui--) {
            var us = ufoShots[ui]
            us.x += (us.vx - shipVX) * speedScale * deltaTime * 60
            us.y += (us.vy - shipVY) * speedScale * deltaTime * 60
            us.age += deltaTime
            if (us.age > 4 || hitsShip(us)) {
                if (us.age <= 4) handleUfoShotHit(us)
                us.destroy()
                ufoShots.splice(ui, 1)
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
                // free flight: the waypoint path drifts with the world
                obj.pathOffX -= shipVX * speedScale * deltaTime * 60
                obj.pathOffY -= shipVY * speedScale * deltaTime * 60
                obj.x        -= shipVX * speedScale * deltaTime * 60
                obj.y        -= shipVY * speedScale * deltaTime * 60
                var wp    = obj.waypoints[obj.currentWaypoint]
                var ucx   = obj.x + obj.width  / 2
                var ucy   = obj.y + obj.height / 2
                var udx   = wp.x + obj.pathOffX - ucx
                var udy   = wp.y + obj.pathOffY - ucy
                var udist = Math.sqrt(udx * udx + udy * udy)
                if (udist < dimsFactor * 4) {
                    obj.currentWaypoint++
                } else {
                    obj.x += (udx / udist) * balance.ufoSpeed * speedScale * deltaTime * 60
                    obj.y += (udy / udist) * balance.ufoSpeed * speedScale * deltaTime * 60
                    obj.directionX = udx / udist
                    obj.directionY = udy / udist
                    obj.speed      = balance.ufoSpeed
                }
                continue
            }

            obj.x += (obj.directionX * obj.speed - shipVX) * speedScale * deltaTime * 60
            obj.y += (obj.directionY * obj.speed - shipVY) * speedScale * deltaTime * 60

            if      (obj.x > worldLeft + worldW)        obj.x = worldLeft - obj.width
            else if (obj.x + obj.width  < worldLeft)    obj.x = worldLeft + worldW
            if      (obj.y > worldTop + worldH)         obj.y = worldTop - obj.height
            else if (obj.y + obj.height < worldTop)     obj.y = worldTop + worldH

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

    // ── Free flight: ship ─────────────────────────────────────────────────────

    // Pitch (the top edge tilted away from the player) thrusts along the
    // nose, pitching back brakes. Inertia and drag as in the original
    // Asteroids. The speed sets the lead offset of ship and bonus circle,
    // and the zoom.
    function updateShip(dt) {
        var rawY = accelerometer.reading.y
        smoothedY = smoothedY + balance.tiltSmoothing * (rawY - smoothedY)
        var pitch  = baselineY - smoothedY
        var span   = balance.ffTiltFull - balance.ffTiltDeadzone
        var thrust = Math.max(0, Math.min(1, (pitch  - balance.ffTiltDeadzone) / span))
        var brake  = Math.max(0, Math.min(1, (-pitch - balance.ffTiltDeadzone) / span))
        if (selftest.active) { thrust = selftest.thrust; brake = 0 }

        var rad = playerRotation * Math.PI / 180
        shipVX += Math.sin(rad) * thrust * balance.ffThrust * dt
        shipVY -= Math.cos(rad) * thrust * balance.ffThrust * dt
        var damp = Math.exp(-(balance.ffDrag + brake * balance.ffBrake) * dt)
        shipVX *= damp
        shipVY *= damp
        var v = Math.sqrt(shipVX * shipVX + shipVY * shipVY)
        if (v > balance.ffMaxSpeed) {
            shipVX *= balance.ffMaxSpeed / v
            shipVY *= balance.ffMaxSpeed / v
            v = balance.ffMaxSpeed
        }

        var leadMax = balance.ffLeadMax * root.width
        var k = Math.min(1, dt * 3)
        leadX += (shipVX / balance.ffMaxSpeed * leadMax - leadX) * k
        leadY += (shipVY / balance.ffMaxSpeed * leadMax - leadY) * k
        var zoomTarget = 1 - (v / balance.ffMaxSpeed) * (1 - balance.ffZoomMin)
        zoom += (zoomTarget - zoom) * Math.min(1, dt * 1.2)

        // explosions and score particles stay where they happened
        var ox = shipVX * speedScale * dt * 60
        var oy = shipVY * speedScale * dt * 60
        var fx = vfxLayer.children
        for (var i = 0; i < fx.length; i++) {
            fx[i].x -= ox
            fx[i].y -= oy
        }
        for (var di = 0; di < dust.count; di++) {
            var d = dust.itemAt(di)
            d.x -= ox * 0.5
            d.y -= oy * 0.5
            if      (d.x > worldLeft + worldW) d.x -= worldW
            else if (d.x < worldLeft)          d.x += worldW
            if      (d.y > worldTop + worldH)  d.y -= worldH
            else if (d.y < worldTop)           d.y += worldH
        }
    }

    // ── UFO ───────────────────────────────────────────────────────────────────

    function spawnUfo() {
        // free flight: the path crosses the whole world, not just the screen
        var w    = worldW
        var h    = worldH
        var ufoW = ufoSize * 1.5415
        var ufoH = ufoSize
        var side = Math.floor(Math.random() * 4)
        var waypoints
        var j1x  = dimsFactor * (Math.random() * 8 - 4)
        var j1y  = dimsFactor * (Math.random() * 8 - 4)
        var j2x  = dimsFactor * (Math.random() * 8 - 4)
        var j2y  = dimsFactor * (Math.random() * 8 - 4)
        
        if (side === 0) {
            waypoints = [
                Qt.point(-ufoW,              h * 0.50),
                Qt.point(w * 0.15 + j1x,   -h * 0.25 + j1y),
                Qt.point(w * 0.50 + j2x,    h + ufoH  + j2y),
                Qt.point(w + ufoW,           h * 0.25)
            ]
        } else if (side === 1) {
            waypoints = [
                Qt.point(w * 0.50,           -ufoH),
                Qt.point(w + ufoW  + j1x,    h * 0.15 + j1y),
                Qt.point(-ufoW     + j2x,    h * 0.50 + j2y),
                Qt.point(w * 0.75,            h + ufoH)
            ]
        } else if (side === 2) {
            waypoints = [
                Qt.point(w + ufoW,            h * 0.50),
                Qt.point(w * 0.85 + j1x,     h + ufoH  + j1y),
                Qt.point(w * 0.50 + j2x,    -h * 0.25 + j2y),
                Qt.point(-ufoW,               h * 0.75)
            ]
        } else {
            waypoints = [
                Qt.point(w * 0.50,            h + ufoH),
                Qt.point(-ufoW     + j1x,     h * 0.85 + j1y),
                Qt.point(w + ufoW  + j2x,     h * 0.50 + j2y),
                Qt.point(w * 0.25,            -ufoH)
            ]
        }

        for (var wi = 0; wi < waypoints.length; wi++)
            waypoints[wi] = Qt.point(waypoints[wi].x + worldLeft, waypoints[wi].y + worldTop)

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

    function ufoFire() {
        if (!ufoObject || playerDying) return
        var ux = ufoObject.x + ufoObject.width  / 2
        var uy = ufoObject.y + ufoObject.height / 2
        // only while it is on screen: no shots from out of view
        if (Math.abs(ux - root.width  / 2) > root.width  / (2 * zoom) ||
            Math.abs(uy - root.height / 2) > root.height / (2 * zoom)) return
        var sx = playerContainer.x
        var sy = playerContainer.y
        var dx = sx - ux, dy = sy - uy
        var dist = Math.sqrt(dx * dx + dy * dy)
        if (dist === 0) return
        // sharp inside the bonus circle, looser the further away
        var near = dimsFactor * balance.perimeterRadius
        var f = Math.max(0, Math.min(1, (dist - near) / Math.max(1, root.width - near)))
        var err = (balance.ufoAimSharp + f * (balance.ufoAimLoose - balance.ufoAimSharp))
                  * (Math.random() * 2 - 1) * Math.PI / 180
        var a = Math.atan2(dy, dx) + err
        // aimed in the ship's frame; the world velocity adds the ship's own,
        // so the shot hits where the ship would be if it keeps its course
        var shot = ufoShotComponent.createObject(shotLayer, {
            "x": ux - dimsFactor, "y": uy - dimsFactor,
            "vx": Math.cos(a) * balance.ufoShotSpeed + shipVX,
            "vy": Math.sin(a) * balance.ufoShotSpeed + shipVY
        })
        ufoShots.push(shot)
        if (selftest.active)
            console.log("selftest ufo fires: distance " + Math.round(dist / dimsFactor)
                        + " dims, aim error " + (err * 180 / Math.PI).toFixed(1) + " deg")
    }

    function hitsShip(us) {
        var ah = (shield > 0) ? shieldHitbox : playerHitbox
        var px = playerContainer.x + ah.x
        var py = playerContainer.y + ah.y
        var cx = us.x + us.width  / 2
        var cy = us.y + us.height / 2
        return cx >= px && cx <= px + ah.width && cy >= py && cy <= py + ah.height
    }

    function handleUfoShotHit(us) {
        if (shield > 0) {
            shield -= 1
            explosionParticleComponent.createObject(vfxLayer, {
                "x": us.x - dimsFactor * 3, "y": us.y - dimsFactor * 3,
                "dimsFactor":     dimsFactor,
                "asteroidSize":   dimsFactor * 4,
                "explosionColor": "shield"
            })
            feedback.play()
        } else {
            killPlayer()
        }
    }

    function clearUfoShots() {
        for (var i = 0; i < ufoShots.length; i++)
            if (ufoShots[i]) ufoShots[i].destroy()
        ufoShots = []
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
        
        deathShaderComponent.createObject(vfxLayer, {
            "x": cx - dimsFactor * 40,
            "y": cy - dimsFactor * 40,
            "width":    dimsFactor * 80,
            "height":   dimsFactor * 80,
            "ringColor": color,
            "autoPlay":  true
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
        powerupBarContainer.opacity = 0
        barOpacityAnim.restart()
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
        if (freeFlight) {
            spawnLargeAsteroidInWorld(size)
            return
        }
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

    // Free flight: asteroids exist before they are seen. A new one appears
    // anywhere in the world outside the current view (plus half its size),
    // preferably ahead of the ship when it is moving, and drifts in from there.
    function spawnLargeAsteroidInWorld(size) {
        var cx = root.width  / 2
        var cy = root.height / 2
        var hw = root.width  / (2 * zoom) + size / 2
        var hh = root.height / (2 * zoom) + size / 2
        var v  = Math.sqrt(shipVX * shipVX + shipVY * shipVY)
        var x = cx, y = cy
        for (var tries = 0; tries < 30; tries++) {
            if (v > 0.3 && Math.random() < 0.7) {
                // just beyond the view's edge along the heading, spread sideways
                var ux = shipVX / v, uy = shipVY / v
                var t  = Math.min(ux !== 0 ? hw / Math.abs(ux) : 1e9,
                                  uy !== 0 ? hh / Math.abs(uy) : 1e9)
                var d    = t + size * (0.5 + Math.random())
                var side = (Math.random() * 2 - 1) * Math.max(hw, hh)
                x = cx + ux * d - uy * side
                y = cy + uy * d + ux * side
            } else {
                x = worldLeft + Math.random() * worldW
                y = worldTop  + Math.random() * worldH
            }
            x = worldLeft + (((x - worldLeft) % worldW) + worldW) % worldW
            y = worldTop  + (((y - worldTop)  % worldH) + worldH) % worldH
            if (Math.abs(x - cx) > hw || Math.abs(y - cy) > hh) break
        }
        // Never inside the view: at full zoom-out the bands beside the view
        // are narrow, but above and below a tall screen there is always room.
        if (Math.abs(x - cx) <= hw && Math.abs(y - cy) <= hh) {
            y = cy + (Math.random() < 0.5 ? -1 : 1) * (hh + size * (0.5 + Math.random()))
            y = worldTop + (((y - worldTop) % worldH) + worldH) % worldH
        }
        var a = Math.random() * 2 * Math.PI
        activeAsteroids.push(asteroidComponent.createObject(asteroidLayer, {
            "x": x - size / 2, "y": y - size / 2,
            "size": size,
            "directionX": Math.cos(a), "directionY": Math.sin(a),
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
            var ut = ""
            if      (level === 2)  { ul = "PIERCE UNLOCKED"; ut = "pierce" }
            else if (level === 3)  { ul = "WIDE UNLOCKED"; ut = "wide" }
            else if (level === 4)  { ul = "TRIPLE UNLOCKED"; ut = "triple" }
            else if (level === 6)  { ul = "RAPID UNLOCKED"; ut = "rapid" }
            else if (level === 8)  { ul = "LASER UNLOCKED"; ut = "laser" }
            else if (level === 10) { ul = "CHAIN BOLT UNLOCKED"; ut = "chain" }
            else if (level === 12) { ul = "NUKE UNLOCKED"; ut = "nuke" }
            if (ul !== "") {
                unlockLabel = ul
                pendingUnlockType = ut
                unlockAnim.restart()
                unlockGiftTimer.restart()
            }
            initialAsteroidsToSpawn = (balance.spawnCountBase + level) * countMult
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
            Math.pow(acx - (scorePerimeter.x + scorePerimeter.width  / 2), 2) +
            Math.pow(acy - (scorePerimeter.y + scorePerimeter.height / 2), 2)
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
            "color": inside ? "#FFAA00" : "#CC7700"
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
            killPlayer()
        }
    }

    function killPlayer() {
        if (playerDying) return
        playerDying = true
        asteroidSpawnTimer.stop()
        ufoSpawnTimer.stop()
        powerupTimer.stop()
        ufoCooldownTimer.stop()
        activePowerup = ""
        glowColor = "#00000000"
        deathShaderComponent.createObject(vfxLayer, {
            "x": playerContainer.x + playerHitbox.x - dimsFactor * 35,
            "y": playerContainer.y + playerHitbox.y - dimsFactor * 35,
            "width":     dimsFactor * 80,
            "height":    dimsFactor * 80,
            "ringColor": "#FF4400",
            "autoPlay":  true
        })
        deathSequenceTimer.start()
        feedback.play()
    }

    function checkCollision(a1, a2) {
        var reach = (a1.size + a2.size) / 2
        var dx = (a1.x + a1.width  / 2) - (a2.x + a2.width  / 2)
        if (dx > reach || dx < -reach) return false
        var dy = (a1.y + a1.height / 2) - (a2.y + a2.height / 2)
        if (dy > reach || dy < -reach) return false
        return dx * dx + dy * dy < reach * reach
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

    // SailfishOS: the app window and the cover pause and resume through
    // this, and read inPreGame to know when there is no round to pause.
    readonly property bool inPreGame: calibrating
    function setPaused(on) {
        if (gameOver || calibrating) return
        paused = on
        pauseText.opacity = on ? 1.0 : 0.0
    }

    function restartGame() {
        score  = 0
        shield = balance.startingShields
        level  = 1
        gameOver    = false
        playerDying = false
        paused      = false
        calibrating = false
        calibrationTimer = 4
        lastFrameTime    = 0
        playerRotation   = 0
        initialAsteroidsToSpawn = balance.initialSpawnCount * countMult
        asteroidsSpawned = 0
        shipVX = 0
        shipVY = 0
        leadX  = 0
        leadY  = 0
        zoom   = 1
        
        unlockGiftTimer.stop()
        pendingUnlockType = ""

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
        clearUfoShots()

        asteroidSpawnTimer.restart()
        ufoSpawnTimer.restart()
    }

    // KeepAlive 1.2 API: instantiated element with a declarative condition.
    // Prevention is scoped to live gameplay only — menus and game-over may
    // blank normally.
    DisplayBlanking {
        preventBlanking: !gameOver && !paused
    }
}
