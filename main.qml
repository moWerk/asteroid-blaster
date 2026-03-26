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

    // --- Game Mechanics ---
    property bool calibrating: true
    property int calibrationTimer: 4
    property bool debugMode: false
    property bool gameOver: false
    property int level: 1
    property bool paused: false
    property int score: 0
    property int shield: 3
    property real dimsFactor: Dims.l(100) / 100
    property var activeShots: []
    property var activeAsteroids: []
    property real lastFrameTime: 0
    property real baselineX: 0
    property real smoothedX: 0
    property real smoothingFactor: 0.5
    property real rotationSpeed: 60
    property real playerRotation: 0
    property int lastShieldAward: 0
    property int initialAsteroidsToSpawn: 5
    property int asteroidsSpawned: 0
    property bool afterBurnerActive: false
    property real afterBurnerTimeLeft: 0
    property real afterBurnerCooldown: 0
    property real boostDistance: dimsFactor * 40
    property real centerX: root.width / 2
    property real centerY: root.height / 2
    property real boostProgress: 0

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

    Timer {
        id: gameTimer
        interval: 16
        running: !gameOver && !calibrating && !paused
        repeat: true
        property real lastFps: 60
        property var fpsHistory: []
        property real lastFpsUpdate: 0
        property real lastGraphUpdate: 0

        onTriggered: {
            var currentTime = Date.now()
            var deltaTime = lastFrameTime > 0 ? (currentTime - lastFrameTime) / 1000 : 0.016
            if (deltaTime > 0.033) deltaTime = 0.033
            lastFrameTime = currentTime
            updateGame(deltaTime)

            var rawX = accelerometer.reading.x
            smoothedX = smoothedX + smoothingFactor * (rawX - smoothedX)
            var deltaX = (smoothedX - baselineX) * -2
            playerRotation += deltaX * rotationSpeed * deltaTime
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
        interval: 150
        running: !gameOver && !calibrating && !paused
        repeat: true
        onTriggered: {
            var rad = playerRotation * Math.PI / 180
            var shotX = playerContainer.x + playerHitbox.x + playerHitbox.width / 2 - dimsFactor * 0.5
            var shotY = playerContainer.y + playerHitbox.y + playerHitbox.height / 2 - dimsFactor * 2.5
            var offsetX = Math.sin(rad) * (dimsFactor * 5)
            var offsetY = -Math.cos(rad) * (dimsFactor * 5)
            var shot = autoFireShotComponent.createObject(gameArea, {
                "x": shotX + offsetX,
                "y": shotY + offsetY,
                "directionX": Math.sin(rad),
                "directionY": -Math.cos(rad),
                "rotation": playerRotation
            })
            activeShots.push(shot)
        }
    }

    Timer {
        id: asteroidSpawnTimer
        interval: Math.max(500, 3000 - (level - 1) * 131)
        running: !gameOver && !calibrating && !paused && asteroidsSpawned < initialAsteroidsToSpawn
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            spawnLargeAsteroid()
            asteroidsSpawned++
            if (asteroidsSpawned >= initialAsteroidsToSpawn) {
                stop()
            }
        }
    }

    Component {
        id: explosionParticleComponent
        ShaderEffect {
            id: explosion
            property real asteroidSize: dimsFactor * 18
            property string explosionColor: "default"
            property real sizeMultiplier: {
                if (asteroidSize === dimsFactor * 20) return 1.0
                if (asteroidSize === dimsFactor * 12) return 1.25
                if (asteroidSize === dimsFactor * 6)  return 1.333
                return 1.0
            }
            width: Math.round(asteroidSize * 2.33 * sizeMultiplier)
            height: Math.round(asteroidSize * 2.33 * sizeMultiplier)
            z: 0

            property real time: 0.0
            // vector3d maps directly to GLSL vec3 in ShaderEffect uniform binding
            property vector3d baseColor: explosionColor === "shield"
                ? Qt.vector3d(0.2, 0.6, 1.0)   // #3399FF
                : Qt.vector3d(1.0, 0.667, 0.2)  // #FFAA33

            NumberAnimation on time {
                from: 0.0
                to: 1.0
                duration: 1000
                running: true
                easing.type: Easing.Linear
                onRunningChanged: {
                    if (!running && time >= 1.0) {
                        explosion.destroy()
                    }
                }
            }

            vertexShader: "
                uniform highp mat4 qt_Matrix;
                attribute highp vec4 qt_Vertex;
                attribute highp vec2 qt_MultiTexCoord0;
                varying highp vec2 coord;
                void main() {
                    coord = qt_MultiTexCoord0;
                    gl_Position = qt_Matrix * qt_Vertex;
                }
            "

            fragmentShader: "
                varying highp vec2 coord;
                uniform highp float time;
                uniform highp vec3 baseColor;
                uniform highp float qt_Opacity;

                highp float noise(highp vec2 p) {
                    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
                }

                void main() {
                    highp vec2 uv = coord - vec2(0.5);
                    highp float dist = length(uv);
                    highp float fade = 1.0 - time;
                    highp vec3 color = vec3(0.0);
                    highp float totalAlpha = 0.0;

                    for (int i = 0; i < 16; i++) {
                        highp float angle = float(i) * 0.3927 + noise(vec2(float(i), time)) * 0.4;
                        highp float speed = 0.8 + noise(vec2(float(i) + 1.0, time)) * 0.4;
                        highp float radius = speed * time;
                        highp vec2 particlePos = vec2(cos(angle), sin(angle)) * radius;

                        highp float swirl = time * 3.0 * (noise(vec2(float(i), 0.0)) - 0.5);
                        particlePos += vec2(cos(swirl), sin(swirl)) * 0.1;

                        highp float particleDist = length(uv - particlePos);
                        highp float particleSize = 0.08 * (1.0 - time * 0.3);
                        if (particleDist < particleSize) {
                            highp float intensity = 1.0 - (particleDist / particleSize);
                            color += mix(vec3(1.0, 0.6, 0.2), baseColor, time) * intensity * intensity * fade;
                            totalAlpha += intensity * fade;
                        }
                    }

                    highp float coreDist = dist * (1.0 + time);
                    if (coreDist < 0.3) {
                        highp float coreIntensity = 1.0 - (coreDist / 0.3);
                        color += mix(vec3(1.0, 0.9, 0.6), baseColor, time) * coreIntensity * fade * 0.9;
                        totalAlpha += coreIntensity * fade;
                    }

                    color = clamp(color * 2.0, vec3(0.0), vec3(1.0));
                    gl_FragColor = vec4(color, totalAlpha * qt_Opacity);
                }
            "
        }
    }

    Component {
        id: autoFireShotComponent
        Rectangle {
            width: dimsFactor * 1
            height: dimsFactor * 4
            color: "#00FFFF"
            z: 2
            visible: true
            property real speed: 8
            property real directionX: 0
            property real directionY: -1
            rotation: playerRotation
        }
    }

    Component {
        id: scoreParticleComponent
        Text {
            id: particle
            color: "#00FFFF"
            font {
                pixelSize: dimsFactor * 8
                family: "Teko"
                styleName: "Medium"
            }
            z: 6
            opacity: 1.0

            Behavior on opacity {
                NumberAnimation {
                    duration: 2000
                    easing.type: Easing.InOutQuad
                    onRunningChanged: {
                        if (!running && opacity === 0) {
                            particle.destroy()
                        }
                    }
                }
            }

            Component.onCompleted: {
                opacity = 0
            }
        }
    }

    Component {
        id: asteroidComponent
        Shape {
            id: asteroid
            property real size: dimsFactor * 20
            property real speed: {
                if (asteroidSize === "large") return 0.27
                if (asteroidSize === "mid")   return 0.36
                if (asteroidSize === "small") return 0.54
                return 2
            }
            property real directionX: 0
            property real directionY: 0
            property string asteroidSize: "large"
            property real rotationSpeed: (Math.random() < 0.5 ? -1 : 1) * (10 + Math.random() * 2 - 1)
            width: size
            height: size
            z: 3

            property var asteroidPoints: {
                var basePoints = Math.floor(5 + Math.random() * 3)
                var pointsArray = []
                var centerX = size / 2
                var centerY = size / 2

                for (var i = 0; i < basePoints; i++) {
                    var baseAngle = (i / basePoints) * 2 * Math.PI
                    var angleVariation = Math.random() * 0.2 - 0.1
                    var angle = baseAngle + angleVariation
                    var isSpike = Math.random() < 0.7
                    var minRadius = isSpike ? size * 0.35 : size * 0.25
                    var maxRadius = isSpike ? size * 0.48 : size * 0.32
                    var radius = minRadius + Math.random() * (maxRadius - minRadius)
                    var x = centerX + radius * Math.cos(angle)
                    var y = centerY + radius * Math.sin(angle)
                    pointsArray.push({x: x, y: y})

                    if (Math.random() < 0.3 && i < basePoints - 1) {
                        var midAngle = baseAngle + (1 / basePoints) * Math.PI + (Math.random() * 0.2 - 0.1)
                        var midRadius = size * (0.2 + Math.random() * 0.15)
                        var midX = centerX + midRadius * Math.cos(midAngle)
                        var midY = centerY + midRadius * Math.sin(midAngle)
                        pointsArray.push({x: midX, y: midY})
                    }
                }
                return pointsArray
            }

            rotation: 0
            NumberAnimation on rotation {
                running: !paused && !gameOver && !calibrating
                loops: Animation.Infinite
                from: 0
                to: 360 * (rotationSpeed < 0 ? -1 : 1)
                duration: Math.abs(360 / rotationSpeed) * 800
            }

            ShapePath {
                strokeWidth: dimsFactor * 1
                strokeColor: paused ? "#444444" : "white"
                fillColor: paused ? "transparent" : "#222222"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin

                startX: asteroid.asteroidPoints[0].x
                startY: asteroid.asteroidPoints[0].y

                PathPolyline {
                    path: {
                        var pathPoints = []
                        for (var i = 0; i < asteroid.asteroidPoints.length; i++) {
                            pathPoints.push(Qt.point(asteroid.asteroidPoints[i].x, asteroid.asteroidPoints[i].y))
                        }
                        pathPoints.push(Qt.point(asteroid.asteroidPoints[0].x, asteroid.asteroidPoints[0].y))
                        return pathPoints
                    }
                }
            }

            function split() {
                if (asteroidSize === "large" && activeAsteroids.filter(a => a.asteroidSize === "mid").length < 10) {
                    spawnSplitAsteroids("mid", dimsFactor * 12, 2, x, y, directionX, directionY)
                } else if (asteroidSize === "mid" && activeAsteroids.filter(a => a.asteroidSize === "small").length < 20) {
                    spawnSplitAsteroids("small", dimsFactor * 6, 2, x, y, directionX, directionY)
                }
                destroyAsteroid(this)
            }
        }
    }

    Item {
        id: gameArea
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: "black"
            layer.enabled: true
            clip: true
            z: -1
        }

        Item {
            id: gameContent
            anchors.fill: parent

            Rectangle {
                id: scorePerimeter
                width: dimsFactor * 55
                height: dimsFactor * 55
                radius: dimsFactor * 27.5
                color: "#010A13"
                border.color: "#0860C4"
                border.width: 1
                anchors.centerIn: parent
                z: 0
                visible: !calibrating

                Behavior on border.color {
                    ColorAnimation {
                        duration: 1000
                        easing.type: Easing.OutQuad
                    }
                }
                Behavior on color {
                    ColorAnimation {
                        duration: 1000
                        easing.type: Easing.OutQuad
                    }
                }
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
                id: playerContainer
                x: root.width / 2 - player.width / 2 + dimsFactor * 5
                y: root.height / 2 - player.height / 2 + dimsFactor * 5
                z: 1
                visible: !calibrating

                Image {
                    id: player
                    width: dimsFactor * 10
                    height: dimsFactor * 10
                    source: "file:///usr/share/asteroid-launcher/watchfaces-img/asteroid-logo.svg"
                    anchors.centerIn: parent
                    rotation: playerRotation
                }

                Shape {
                    id: playerHitbox
                    width: dimsFactor * 10
                    height: dimsFactor * 10
                    anchors.centerIn: parent
                    visible: false
                    rotation: playerRotation

                    ShapePath {
                        strokeWidth: -1
                        fillColor: "transparent"
                        startX: dimsFactor * 5; startY: 0
                        PathLine { x: dimsFactor * 10; y: dimsFactor * 5 }
                        PathLine { x: dimsFactor * 5; y: dimsFactor * 10 }
                        PathLine { x: 0; y: dimsFactor * 5 }
                        PathLine { x: dimsFactor * 5; y: 0 }
                    }
                }

                Shape {
                    id: shieldHitbox
                    width: dimsFactor * 14
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
                        PathLine { x: dimsFactor * 7; y: dimsFactor * 14 }
                        PathLine { x: 0; y: dimsFactor * 7 }
                        PathLine { x: dimsFactor * 7; y: 0 }
                    }
                }
            }

            Text {
                id: levelNumber
                text: level
                color: "#F9DC5C"
                font {
                    pixelSize: dimsFactor * 12
                    family: "Teko"
                    styleName: "SemiBold"
                }
                anchors {
                    top: root.top
                    horizontalCenter: parent.horizontalCenter
                }
                z: 4
                visible: !calibrating
            }

            Text {
                id: scoreText
                text: score
                color: "#00FFFF"
                font {
                    pixelSize: dimsFactor * 13
                    family: "Teko"
                    styleName: "Light"
                }
                anchors {
                    bottom: shieldText.top
                    bottomMargin: -dimsFactor * 8
                    horizontalCenter: parent.horizontalCenter
                }
                z: 4
                visible: !gameOver && !calibrating
            }

            Text {
                id: shieldText
                text: shield
                color: shield > 0 ? "#DD1155" : "white"
                font {
                    pixelSize: dimsFactor * 12
                    family: "Teko"
                    styleName: "SemiBold"
                }
                anchors {
                    bottom: parent.bottom
                    bottomMargin: -dimsFactor * 6
                    horizontalCenter: parent.horizontalCenter
                }
                z: 4
                visible: !calibrating
            }

            Item {
                id: calibrationContainer
                anchors.fill: parent
                visible: calibrating

                Text {
                    text: "v1.1\nAsteroid Blaster"
                    color: "#dddddd"
                    lineHeightMode: Text.ProportionalHeight
                    lineHeight: 0.6
                    font {
                        family: "Teko"
                        pixelSize: dimsFactor * 16
                        styleName: "Medium"
                    }
                    anchors {
                        bottom: calibrationText.top
                        bottomMargin: dimsFactor * 10
                        horizontalCenter: parent.horizontalCenter
                    }
                    horizontalAlignment: Text.AlignHCenter
                }

                Column {
                    id: calibrationText
                    anchors {
                        top: parent.verticalCenter
                        horizontalCenter: parent.horizontalCenter
                    }
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

            Rectangle {
                id: dimmingLayer
                anchors.fill: parent
                color: "#000000"
                z: 9
                opacity: (paused && !gameOver && !calibrating) || gameOver ? 0.6 : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.InOutQuad
                    }
                }
            }

            Text {
                id: pauseText
                text: "Paused"
                color: "white"
                font {
                    pixelSize: dimsFactor * 22
                    family: "Teko"
                    
                }
                anchors.centerIn: parent
                opacity: 0
                z: 10
                visible: !gameOver && !calibrating
                Behavior on opacity {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.InOutQuad
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !gameOver && !calibrating
                    onClicked: {
                        paused = !paused
                        pauseText.opacity = paused ? 1.0 : 0.0
                    }
                }
            }

            MouseArea {
                id: afterBurnerTrigger
                anchors {
                    left: parent.left
                    right: parent.right
                    top: pauseText.bottom
                    bottom: parent.bottom
                }
                enabled: !gameOver && !calibrating && !paused && afterBurnerCooldown <= 0
                onPressed: {
                    if (!afterBurnerActive) {
                        afterBurnerActive = true
                        afterBurnerTimeLeft = 2.0
                        feedback.play()
                    }
                }
                onReleased: {
                    if (afterBurnerActive) {
                        afterBurnerActive = false
                        afterBurnerCooldown = 10.0
                    }
                }
            }

            Text {
                id: fpsDisplay
                text: "FPS: 60"
                color: "white"
                opacity: 0.5
                font.pixelSize: dimsFactor * 10
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: fpsGraph.top
                }
                visible: debugMode && !gameOver && !calibrating
            }

            Rectangle {
                id: fpsGraph
                width: dimsFactor * 30
                height: dimsFactor * 10
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
                                if (fps > 60) return "green"
                                else if (fps >= 50) return "orange"
                                else return "red"
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
                z: 10
                font {
                    pixelSize: dimsFactor * 10
                    bold: debugMode
                }
                anchors {
                    bottom: pauseText.top
                    horizontalCenter: parent.horizontalCenter
                    bottomMargin: dimsFactor * 4
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.InOutQuad
                    }
                }
                visible: paused && !gameOver && !calibrating
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        debugMode = !debugMode
                    }
                }
            }
        }

        Item {
            id: gameOverContainer
            anchors.fill: parent
            visible: gameOver
            z: 10

            Text {
                id: gameOverText
                text: "Game Over"
                color: "white"
                font {
                    pixelSize: dimsFactor * 20
                    family: "Teko"
                    styleName: "Medium"
                }
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
                font {
                    pixelSize: dimsFactor * 12
                    family: "Teko"
                }
                anchors {
                    bottom: parent.verticalCenter
                    bottomMargin: dimsFactor * 1
                    horizontalCenter: parent.horizontalCenter
                }
            }

            Text {
                id: highScoreOverText
                text: "Highscore: " + GameStorage.highScore + "\nLevel: " + GameStorage.highLevel
                horizontalAlignment: Text.AlignHCenter
                color: "white"
                lineHeightMode: Text.ProportionalHeight
                lineHeight: 0.6
                font {
                    pixelSize: dimsFactor * 12
                    family: "Teko"
                }
                anchors {
                    top: parent.verticalCenter
                    topMargin: dimsFactor * 1
                    horizontalCenter: parent.horizontalCenter
                }
            }

            Rectangle {
                id: tryAgainButton
                width: dimsFactor * 50
                height: dimsFactor * 20
                radius: dimsFactor * 2
                color: "#222222"
                anchors {
                    top: highScoreOverText.bottom
                    topMargin: dimsFactor * 6
                    horizontalCenter: parent.horizontalCenter
                }

                Text {
                    text: "Try Again"
                    color: "white"
                    font {
                        pixelSize: dimsFactor * 10
                        family: "Teko"
                        styleName: "SemiBold"
                    }
                    anchors.centerIn: parent
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        restartGame()
                    }
                }
            }
        }

        Accelerometer {
            id: accelerometer
            active: true
        }
    }

    function updateGame(deltaTime) {
        // Shot movement and shot-asteroid collision
        for (var si = activeShots.length - 1; si >= 0; si--) {
            var shot = activeShots[si]
            if (shot) {
                shot.x += shot.directionX * shot.speed * deltaTime * 60
                shot.y += shot.directionY * shot.speed * deltaTime * 60
                if (shot.y <= -shot.height || shot.y >= root.height || shot.x <= -shot.width || shot.x >= root.width) {
                    shot.destroy()
                    activeShots.splice(si, 1)
                } else {
                    var shotHit = false
                    for (var ai = activeAsteroids.length - 1; ai >= 0; ai--) {
                        var asteroid = activeAsteroids[ai]
                        if (checkShotAsteroidCollision(shot, asteroid)) {
                            handleShotAsteroidCollision(shot, asteroid)
                            shotHit = true
                            break
                        }
                    }
                    if (shotHit) {
                        shot.destroy()
                        activeShots.splice(si, 1)
                    }
                }
            }
        }

        // Asteroid movement, wrapping and player collision
        for (var ai = activeAsteroids.length - 1; ai >= 0; ai--) {
            var asteroid = activeAsteroids[ai]
            if (asteroid) {
                asteroid.x += asteroid.directionX * asteroid.speed * deltaTime * 60
                asteroid.y += asteroid.directionY * asteroid.speed * deltaTime * 60

                if (asteroid.x > root.width) {
                    asteroid.x = -asteroid.width
                } else if (asteroid.x + asteroid.width < 0) {
                    asteroid.x = root.width
                }
                if (asteroid.y > root.height) {
                    asteroid.y = -asteroid.height
                } else if (asteroid.y + asteroid.height < 0) {
                    asteroid.y = root.height
                }

                var playerCenterX = playerContainer.x + playerHitbox.width / 2
                var playerCenterY = playerContainer.y + playerHitbox.height / 2
                var asteroidCenterX = asteroid.x + asteroid.width / 2
                var asteroidCenterY = asteroid.y + asteroid.height / 2
                var proximityRange = dimsFactor * 20
                var pdx = Math.abs(playerCenterX - asteroidCenterX)
                var pdy = Math.abs(playerCenterY - asteroidCenterY)
                if (pdx < proximityRange && pdy < proximityRange) {
                    if (checkPlayerAsteroidCollision(playerHitbox, asteroid)) {
                        handlePlayerAsteroidCollision(asteroid)
                    }
                }
            }
        }

        // Afterburner logic
        if (afterBurnerActive && afterBurnerTimeLeft > 0) {
            afterBurnerTimeLeft -= deltaTime
            boostProgress = Math.min(boostProgress + deltaTime / 0.5, 1.0)
            var maxBoostSpeed = dimsFactor * 25
            var boostSpeed = maxBoostSpeed * boostProgress

            var playerCenterX = playerContainer.x + playerHitbox.width / 2
            var playerCenterY = playerContainer.y + playerHitbox.height / 2
            var nearestAsteroid = null
            var minDistance = Infinity
            for (var ki = 0; ki < activeAsteroids.length; ki++) {
                var ast = activeAsteroids[ki]
                var astCenterX = ast.x + ast.width / 2
                var astCenterY = ast.y + ast.height / 2
                var adx = astCenterX - playerCenterX
                var ady = astCenterY - playerCenterY
                var dist = Math.sqrt(adx * adx + ady * ady)
                if (dist < minDistance) {
                    minDistance = dist
                    nearestAsteroid = ast
                }
            }

            var evadeX, evadeY
            if (nearestAsteroid) {
                astCenterX = nearestAsteroid.x + nearestAsteroid.width / 2
                astCenterY = nearestAsteroid.y + nearestAsteroid.height / 2
                evadeX = playerCenterX - astCenterX
                evadeY = playerCenterY - astCenterY
                var mag = Math.sqrt(evadeX * evadeX + evadeY * evadeY)
                if (mag > 0) {
                    evadeX /= mag
                    evadeY /= mag
                } else {
                    evadeX = 0
                    evadeY = -1
                }
            } else {
                evadeX = 0
                evadeY = -1
            }

            var newX = playerContainer.x + evadeX * boostSpeed * deltaTime
            var newY = playerContainer.y + evadeY * boostSpeed * deltaTime
            var distX = newX - centerX
            var distY = newY - centerY
            var distance = Math.sqrt(distX * distX + distY * distY)
            if (distance <= boostDistance) {
                playerContainer.x = newX
                playerContainer.y = newY
            }

            if (afterBurnerTimeLeft <= 0) {
                afterBurnerActive = false
                afterBurnerCooldown = 10.0
                boostProgress = 0
            }
        } else if (!afterBurnerActive) {
            var returnSpeed = dimsFactor * 20
            var rdx = centerX - playerContainer.x
            var rdy = centerY - playerContainer.y
            var distance = Math.sqrt(rdx * rdx + rdy * rdy)
            if (distance > dimsFactor * 5) {
                playerContainer.x += (rdx / distance) * returnSpeed * deltaTime
                playerContainer.y += (rdy / distance) * returnSpeed * deltaTime
            } else {
                playerContainer.x = centerX
                playerContainer.y = centerY
            }
            boostProgress = 0
        }

        if (afterBurnerCooldown > 0) {
            afterBurnerCooldown -= deltaTime
            if (afterBurnerCooldown < 0) afterBurnerCooldown = 0
        }

        // Asteroid-asteroid collision pass
        for (var a1i = 0; a1i < activeAsteroids.length; a1i++) {
            var asteroid1 = activeAsteroids[a1i]
            if (!asteroid1) continue
            for (var a2i = a1i + 1; a2i < activeAsteroids.length; a2i++) {
                var asteroid2 = activeAsteroids[a2i]
                if (checkCollision(asteroid1, asteroid2)) {
                    handleAsteroidCollision(asteroid1, asteroid2)
                }
            }
        }
    }

    function spawnLargeAsteroid() {
        var size = dimsFactor * 18
        var spawnSide = Math.floor(Math.random() * 4)
        var spawnX, spawnY, targetX, targetY
        switch (spawnSide) {
            case 0:
                spawnX = Math.random() * root.width
                spawnY = -size
                targetX = Math.random() * root.width
                targetY = root.height + size
                break
            case 1:
                spawnX = root.width + size
                spawnY = Math.random() * root.height
                targetX = -size
                targetY = Math.random() * root.height
                break
            case 2:
                spawnX = Math.random() * root.width
                spawnY = root.height + size
                targetX = Math.random() * root.width
                targetY = -size
                break
            case 3:
                spawnX = -size
                spawnY = Math.random() * root.height
                targetX = root.width + size
                targetY = Math.random() * root.height
                break
        }
        var dx = targetX - spawnX
        var dy = targetY - spawnY
        var mag = Math.sqrt(dx * dx + dy * dy)
        var asteroid = asteroidComponent.createObject(gameArea, {
            "x": spawnX,
            "y": spawnY,
            "size": size,
            "directionX": dx / mag,
            "directionY": dy / mag,
            "asteroidSize": "large"
        })
        activeAsteroids.push(asteroid)
    }

    function spawnSplitAsteroids(sizeType, size, count, x, y, directionX, directionY) {
        var rad = Math.atan2(directionY, directionX)
        for (var i = 0; i < count; i++) {
            var offsetAngle = (i === 0 ? -1 : 1) * 45 * Math.PI / 180
            var newRad = rad + offsetAngle
            var asteroid = asteroidComponent.createObject(gameArea, {
                "x": x,
                "y": y,
                "size": size,
                "directionX": Math.cos(newRad),
                "directionY": Math.sin(newRad),
                "asteroidSize": sizeType
            })
            activeAsteroids.push(asteroid)
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
        if (activeAsteroids.length === 0 && asteroidsSpawned >= initialAsteroidsToSpawn) {
            level++
            initialAsteroidsToSpawn = 4 + level
            asteroidsSpawned = 0
            spawnLargeAsteroid()
            asteroidsSpawned++
            asteroidSpawnTimer.restart()
        }
    }

    function pointInPolygon(x, y, points) {
        var inside = false
        for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
            var xi = points[i].x, yi = points[i].y
            var xj = points[j].x, yj = points[j].y
            var intersect = ((yi > y) !== (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi)
            if (intersect) inside = !inside
        }
        return inside
    }

    function checkShotAsteroidCollision(shot, asteroid) {
        var shotLeft   = shot.x
        var shotRight  = shot.x + shot.width
        var shotTop    = shot.y
        var shotBottom = shot.y + shot.height

        for (var i = 0; i < asteroid.asteroidPoints.length; i++) {
            var pointX = asteroid.x + asteroid.asteroidPoints[i].x
            var pointY = asteroid.y + asteroid.asteroidPoints[i].y
            if (pointX >= shotLeft && pointX <= shotRight &&
                pointY >= shotTop  && pointY <= shotBottom) {
                return true
            }
        }

        var corners = [
            {x: shotLeft,  y: shotTop},
            {x: shotRight, y: shotTop},
            {x: shotRight, y: shotBottom},
            {x: shotLeft,  y: shotBottom}
        ]
        for (var j = 0; j < corners.length; j++) {
            var localX = corners[j].x - asteroid.x
            var localY = corners[j].y - asteroid.y
            if (pointInPolygon(localX, localY, asteroid.asteroidPoints)) {
                return true
            }
        }

        return false
    }

    function handleShotAsteroidCollision(shot, asteroid) {
        var asteroidCenterX = asteroid.x + asteroid.width / 2
        var asteroidCenterY = asteroid.y + asteroid.height / 2
        var perimeterCenterX = root.width / 2
        var perimeterCenterY = root.height / 2
        var distance = Math.sqrt(
            Math.pow(asteroidCenterX - perimeterCenterX, 2) +
            Math.pow(asteroidCenterY - perimeterCenterY, 2)
        )
        var perimeterRadius = dimsFactor * 27.5

        var basePoints
        if (asteroid.asteroidSize === "small")      basePoints = 100
        else if (asteroid.asteroidSize === "mid")   basePoints = 50
        else if (asteroid.asteroidSize === "large") basePoints = 20
        var points = distance < perimeterRadius ? basePoints * 2 : basePoints
        score += points

        var sizeMultiplier = asteroid.asteroidSize === "large" ? 1.0
                           : asteroid.asteroidSize === "mid"   ? 1.25
                           :                                     1.333
        explosionParticleComponent.createObject(gameContent, {
            "x": asteroid.x + asteroid.width / 2 - (asteroid.size * 2.33 * sizeMultiplier / 2),
            "y": asteroid.y + asteroid.height / 2 - (asteroid.size * 2.33 * sizeMultiplier / 2),
            "asteroidSize": asteroid.size,
            "explosionColor": "default"
        })

        scoreParticleComponent.createObject(gameContent, {
            "x": asteroidCenterX - dimsFactor * 4,
            "y": asteroidCenterY - dimsFactor * 4,
            "text": "+" + points,
            "color": distance < perimeterRadius ? "#00FFFF" : "#67AAF9"
        })

        if (distance < perimeterRadius) {
            scorePerimeter.border.color = "#FFFFFF"
            scorePerimeter.color = "#074588"
            perimeterFlashTimer.restart()
        }

        var newThreshold = Math.floor(score / 10000) * 10000
        if (newThreshold > lastShieldAward) {
            shield += 1
            lastShieldAward = newThreshold
        }

        asteroid.split()
    }

    function checkPlayerAsteroidCollision(playerHitbox, asteroid) {
        var activeHitbox = (shield > 0) ? shieldHitbox : playerHitbox
        var playerX = playerContainer.x + activeHitbox.x
        var playerY = playerContainer.y + activeHitbox.y
        var corners = [
            {x: playerX,                        y: playerY},
            {x: playerX + activeHitbox.width,   y: playerY},
            {x: playerX + activeHitbox.width,   y: playerY + activeHitbox.height},
            {x: playerX,                        y: playerY + activeHitbox.height}
        ]

        for (var i = 0; i < corners.length; i++) {
            var localX = corners[i].x - asteroid.x
            var localY = corners[i].y - asteroid.y
            if (pointInPolygon(localX, localY, asteroid.asteroidPoints)) {
                return true
            }
        }

        var playerLeft   = playerX
        var playerRight  = playerX + activeHitbox.width
        var playerTop    = playerY
        var playerBottom = playerY + activeHitbox.height
        for (var j = 0; j < asteroid.asteroidPoints.length; j++) {
            var pointX = asteroid.x + asteroid.asteroidPoints[j].x
            var pointY = asteroid.y + asteroid.asteroidPoints[j].y
            if (pointX >= playerLeft && pointX <= playerRight &&
                pointY >= playerTop  && pointY <= playerBottom) {
                return true
            }
        }

        return false
    }

    function handlePlayerAsteroidCollision(asteroid) {
        if (shield > 0) {
            shield -= 1
            var index = activeAsteroids.indexOf(asteroid)
            if (index !== -1) {
                activeAsteroids.splice(index, 1)
            }
            explosionParticleComponent.createObject(gameContent, {
                "x": asteroid.x + asteroid.width / 2 - (asteroid.size * 2.33 / 2),
                "y": asteroid.y + asteroid.height / 2 - (asteroid.size * 2.33 / 2),
                "asteroidSize": asteroid.size,
                "explosionColor": "shield"
            })
            asteroid.destroy()
            feedback.play()
        } else {
            gameOver = true
            asteroidSpawnTimer.stop()
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

    function checkCollision(asteroid1, asteroid2) {
        var dx = (asteroid1.x + asteroid1.width / 2) - (asteroid2.x + asteroid2.width / 2)
        var dy = (asteroid1.y + asteroid1.height / 2) - (asteroid2.y + asteroid2.height / 2)
        var distance = Math.sqrt(dx * dx + dy * dy)
        var minDistance = (asteroid1.size + asteroid2.size) / 2
        return distance < minDistance
    }

    function handleAsteroidCollision(asteroid1, asteroid2) {
        var nx = (asteroid2.x + asteroid2.width / 2) - (asteroid1.x + asteroid1.width / 2)
        var ny = (asteroid2.y + asteroid2.height / 2) - (asteroid1.y + asteroid1.height / 2)
        var mag = Math.sqrt(nx * nx + ny * ny)
        if (mag === 0) return
        nx /= mag
        ny /= mag

        var v1x = asteroid1.directionX * asteroid1.speed
        var v1y = asteroid1.directionY * asteroid1.speed
        var v2x = asteroid2.directionX * asteroid2.speed
        var v2y = asteroid2.directionY * asteroid2.speed

        var mass1 = asteroid1.size * asteroid1.size
        var mass2 = asteroid2.size * asteroid2.size
        var totalMass = mass1 + mass2

        var dot1 = v1x * nx + v1y * ny
        var dot2 = v2x * nx + v2y * ny

        var newDot1 = (dot1 * (mass1 - mass2) + 2 * mass2 * dot2) / totalMass
        var newDot2 = (dot2 * (mass2 - mass1) + 2 * mass1 * dot1) / totalMass

        var newV1x = v1x - dot1 * nx + newDot1 * nx
        var newV1y = v1y - dot1 * ny + newDot1 * ny
        var newV2x = v2x - dot2 * nx + newDot2 * nx
        var newV2y = v2y - dot2 * ny + newDot2 * ny

        var mag1 = Math.sqrt(newV1x * newV1x + newV1y * newV1y)
        var mag2 = Math.sqrt(newV2x * newV2x + newV2y * newV2y)
        if (mag1 > 0) {
            asteroid1.directionX = newV1x / mag1
            asteroid1.directionY = newV1y / mag1
        }
        if (mag2 > 0) {
            asteroid2.directionX = newV2x / mag2
            asteroid2.directionY = newV2y / mag2
        }

        var overlap = (asteroid1.size + asteroid2.size) / 2 - mag
        if (overlap > 0) {
            var pushX = nx * overlap * 0.5
            var pushY = ny * overlap * 0.5
            asteroid1.x -= pushX * (mass2 / totalMass)
            asteroid1.y -= pushY * (mass2 / totalMass)
            asteroid2.x += pushX * (mass1 / totalMass)
            asteroid2.y += pushY * (mass1 / totalMass)
        }
    }

    function restartGame() {
        score = 0
        shield = 3
        level = 1
        gameOver = false
        paused = false
        calibrating = false
        calibrationTimer = 4
        lastFrameTime = 0
        playerRotation = 0
        lastShieldAward = 0
        initialAsteroidsToSpawn = 5
        asteroidsSpawned = 0
        afterBurnerActive = false
        afterBurnerTimeLeft = 0
        afterBurnerCooldown = 0
        boostProgress = 0
        playerContainer.x = centerX
        playerContainer.y = centerY
        for (var i = 0; i < activeShots.length; i++) {
            if (activeShots[i]) activeShots[i].destroy()
        }
        for (var j = 0; j < activeAsteroids.length; j++) {
            if (activeAsteroids[j]) activeAsteroids[j].destroy()
        }
        activeShots = []
        activeAsteroids = []
        asteroidSpawnTimer.restart()
    }

    Component.onCompleted: {
        DisplayBlanking.preventBlanking = true
    }

    Component.onDestruction: {
        DisplayBlanking.preventBlanking = false
    }
}
