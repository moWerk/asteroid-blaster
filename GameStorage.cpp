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

#include "GameStorage.h"
#include <QDir>
#include <QStandardPaths>

static GameStorage *s_instance = nullptr;

GameStorage::GameStorage(QObject *parent)
    : QObject(parent)
    // Explicit path avoids HOME ambiguity in the Lipstick session environment.
    // QSettings creates the directory on first sync() if it does not exist.
    , m_settings(
          QStandardPaths::writableLocation(QStandardPaths::HomeLocation)
          + QStringLiteral("/.config/asteroid-blaster/game.ini"),
          QSettings::IniFormat)
{
    QDir().mkpath(
        QStandardPaths::writableLocation(QStandardPaths::HomeLocation)
        + QStringLiteral("/.config/asteroid-blaster"));
    s_instance = this;
}

GameStorage *GameStorage::instance()
{
    if (!s_instance)
        s_instance = new GameStorage();
    return s_instance;
}

QObject *GameStorage::qmlInstance(QQmlEngine *, QJSEngine *)
{
    return instance();
}

// ── Getters ──────────────────────────────────────────────────────────────────

int GameStorage::highScore() const
{
    return m_settings.value(QStringLiteral("highScore"), 0).toInt();
}

int GameStorage::highLevel() const
{
    return m_settings.value(QStringLiteral("highLevel"), 1).toInt();
}

// ── Setters — never lower stored values, sync to disk on every write ─────────

void GameStorage::setHighScore(int v)
{
    if (v <= highScore()) return;
    m_settings.setValue(QStringLiteral("highScore"), v);
    m_settings.sync();
    emit highScoreChanged();
}

void GameStorage::setHighLevel(int v)
{
    if (v <= highLevel()) return;
    m_settings.setValue(QStringLiteral("highLevel"), v);
    m_settings.sync();
    emit highLevelChanged();
}

// ── Utility ───────────────────────────────────────────────────────────────────

QString GameStorage::fileName() const
{
    return m_settings.fileName();
}
