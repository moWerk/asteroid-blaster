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

import QtQuick

// Self-contained explosion shader. Set asteroidSize, explosionColor
// (and customColor for UFO hits) at createObject time. Self-destructs
// when the animation completes.

ShaderEffect {
    id: explosion

    property real   dimsFactor:    1
    property real   asteroidSize:  dimsFactor * 18
    property string explosionColor: "default"
    property real   sizeMultiplier: {
        if (asteroidSize <= dimsFactor * 6)  return 1.333
        if (asteroidSize <= dimsFactor * 12) return 1.25
        return 1.0
    }

    width:  Math.round(asteroidSize * 1.86 * sizeMultiplier)
    height: Math.round(asteroidSize * 1.86 * sizeMultiplier)

    property real      time: 0.0
    property vector3d  customColor: Qt.vector3d(1.0, 0.667, 0.2)
    property vector3d  baseColor: {
        if (explosionColor === "shield") return Qt.vector3d(0.2, 0.6, 1.0)
        if (explosionColor === "nuke")   return Qt.vector3d(1.0, 1.0, 1.0)
        if (explosionColor === "custom") return customColor
        return Qt.vector3d(1.0, 0.667, 0.2)
    }

    NumberAnimation on time {
        from: 0.0; to: 1.0
        duration: 1000
        running: true
        easing.type: Easing.Linear
        onRunningChanged: {
            if (!running && time >= 1.0) explosion.destroy()
        }
    }

    // Qt6: pre-compiled qsb, source in shaders/explosion.frag. The old
    // custom vertex shader was a plain passthrough — the default vertex
    // shader provides the same qt_TexCoord0.
    fragmentShader: "shaders/explosion.frag.qsb"
}
