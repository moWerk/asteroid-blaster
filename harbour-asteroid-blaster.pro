TARGET = harbour-asteroid-blaster

CONFIG += sailfishapp

SOURCES += src/main.cpp \
    src/GameStorage.cpp

HEADERS += src/GameStorage.h

DISTFILES += qml/harbour-asteroid-blaster.qml \
    qml/game/*.qml \
    qml/game/qmldir \
    rpm/harbour-asteroid-blaster.spec \
    harbour-asteroid-blaster.desktop

SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172
