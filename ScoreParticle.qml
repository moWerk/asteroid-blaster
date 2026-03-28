/*
 * Copyright (C) 2025 - Timo Könnecke <github.com/eLtMosen>
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

// Self-contained score popup. Set text and color at createObject time.
// Fades out and self-destructs.

Text {
    id: particle

    property real dimsFactor: 1

    color: "#00FFFF"
    font { pixelSize: dimsFactor * 8; family: "Teko"; styleName: "Medium" }
    opacity: 1.0

    Behavior on opacity {
        NumberAnimation {
            duration: 2000
            easing.type: Easing.InOutQuad
            onRunningChanged: {
                if (!running && opacity === 0) particle.destroy()
            }
        }
    }

    Component.onCompleted: { opacity = 0 }
}
