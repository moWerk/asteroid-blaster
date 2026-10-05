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

#include <sailfishapp.h>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QQuickView>
#include <QScopedPointer>
#include <QTimer>
#include <QtQml>
#include "GameStorage.h"

int main(int argc, char *argv[])
{
    QScopedPointer<QGuiApplication> app(SailfishApp::application(argc, argv));
    app->setOrganizationName(QStringLiteral("net.mowerk"));
    app->setApplicationName(QStringLiteral("harbour-asteroid-blaster"));

    qmlRegisterSingletonType<GameStorage>(
        "org.asteroid.blaster", 1, 0, "GameStorage",
        GameStorage::qmlInstance);

    // The game asks for "Teko" in several weights by name. AsteroidOS has
    // it system wide, here it comes with the app.
    const char *fonts[] = { "Light", "Regular", "Medium", "SemiBold", "Bold" };
    for (const char *style : fonts)
        QFontDatabase::addApplicationFont(SailfishApp::pathTo(
            QStringLiteral("qml/game/fonts/Teko-%1.ttf").arg(QLatin1String(style))).toLocalFile());

    QScopedPointer<QQuickView> view(SailfishApp::createView());
    // Test hook: SFOS_SELFTEST_SENSOR=1 logs the accelerometer once a second,
    // to check that the sensor works inside the sandbox.
    view->rootContext()->setContextProperty(QStringLiteral("selftestSensor"),
                                            qEnvironmentVariableIsSet("SFOS_SELFTEST_SENSOR"));
    view->setSource(SailfishApp::pathToMainQml());
    view->show();

    // Test hook, not used in normal runs: with SFOS_SELFTEST_SHOT=<file>
    // the window is grabbed after SFOS_SELFTEST_DELAY ms (default 6000)
    // and saved, so a build can be checked without looking at the phone.
    const QByteArray shot = qgetenv("SFOS_SELFTEST_SHOT");
    if (!shot.isEmpty()) {
        const int delay = qEnvironmentVariableIsSet("SFOS_SELFTEST_DELAY")
                ? qgetenv("SFOS_SELFTEST_DELAY").toInt() : 6000;
        QQuickView *v = view.data();
        QTimer::singleShot(delay, v, [v, shot]() {
            v->grabWindow().save(QString::fromLocal8Bit(shot));
        });
    }
    return app->exec();
}
