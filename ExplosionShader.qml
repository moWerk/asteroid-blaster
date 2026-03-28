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

import QtQuick 2.15

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

            for (int i = 0; i < 12; i++) {
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
