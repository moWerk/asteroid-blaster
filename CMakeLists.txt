cmake_minimum_required(VERSION 3.6.0)

project(asteroid-blaster
	VERSION 1.0
	DESCRIPTION "The Asteroid Blaster Game for AsteroidOS")

find_package(ECM REQUIRED NO_MODULE)
find_package(AsteroidApp REQUIRED)

set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH} ${ASTEROID_MODULE_PATH})

include(FeatureSummary)
include(GNUInstallDirs)
include(ECMFindQmlModule)
include(AsteroidCMakeSettings)
include(AsteroidTranslations)

add_executable(asteroid-blaster
    main.cpp
    GameStorage.cpp
    resources.qrc)

target_link_libraries(asteroid-blaster PRIVATE
    AsteroidApp)

install(TARGETS asteroid-blaster DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES asteroid-blaster.desktop
        DESTINATION /usr/share/applications/)
install(FILES asteroid-blaster.svg
        DESTINATION /usr/share/icons/asteroid/)
