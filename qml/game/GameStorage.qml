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

pragma Singleton
import QtQuick 2.6
import Nemo.Configuration 1.0

// SailfishOS: replaces the C++ GameStorage (QSettings, game.ini) so the
// app is pure QML and one noarch package. Same API; the values live in
// dconf under /apps/harbour-asteroid-blaster. Records are never lowered:
// an assignment below the stored record is undone.
QtObject {
    id: store

    property QtObject _cfg: ConfigurationGroup { path: "/apps/harbour-asteroid-blaster" }
    property bool _ready: false

    property int highScore: 0
    property int highLevel: 1
    // free flight keeps its own records; it plays differently
    property int highScoreFree: 0
    property int highLevelFree: 1
    // "idle" (the ship only turns) or "free" (free flight)
    property string mode: "idle"
    onModeChanged: if (_ready) _cfg.setValue("mode", mode)

    function _keepRecord(key, v, setBack) {
        if (!_ready) return
        var stored = Number(_cfg.value(key, key.indexOf("highLevel") === 0 ? 1 : 0))
        if (v > stored) _cfg.setValue(key, v)
        else if (v < stored) setBack(stored)
    }
    onHighScoreChanged: _keepRecord("highScore", highScore, function (s) { highScore = s })
    onHighLevelChanged: _keepRecord("highLevel", highLevel, function (s) { highLevel = s })
    onHighScoreFreeChanged: _keepRecord("highScoreFree", highScoreFree, function (s) { highScoreFree = s })
    onHighLevelFreeChanged: _keepRecord("highLevelFree", highLevelFree, function (s) { highLevelFree = s })

    Component.onCompleted: {
        highScore = Number(_cfg.value("highScore", 0))
        highLevel = Number(_cfg.value("highLevel", 1))
        highScoreFree = Number(_cfg.value("highScoreFree", 0))
        highLevelFree = Number(_cfg.value("highLevelFree", 1))
        mode = String(_cfg.value("mode", "idle"))
        _ready = true
    }
}
