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

#ifndef GAMESTORAGE_H
#define GAMESTORAGE_H

#include <QObject>
#include <QSettings>
#include <QString>
#include <QQmlEngine>

class GameStorage : public QObject
{
    Q_OBJECT

    Q_PROPERTY(int highScore READ highScore WRITE setHighScore NOTIFY highScoreChanged)
    Q_PROPERTY(int highLevel READ highLevel WRITE setHighLevel NOTIFY highLevelChanged)

public:
    explicit GameStorage(QObject *parent = nullptr);
    static GameStorage *instance();
    static QObject *qmlInstance(QQmlEngine *engine, QJSEngine *scriptEngine);

    int highScore() const;
    int highLevel() const;

    void setHighScore(int v);
    void setHighLevel(int v);

    Q_INVOKABLE QString fileName() const;

signals:
    void highScoreChanged();
    void highLevelChanged();

private:
    QSettings m_settings;
};

#endif // GAMESTORAGE_H
