# xz, not zstd: rpm on SailfishOS 3.4 can not unpack zstd payloads
%define _binary_payload w6.xzdio

Name:       harbour-asteroid-blaster
Summary:    Blaster, a tilt controlled asteroid shooter
Version:    2.2.1
Release:    1
License:    GPLv3+
URL:        https://github.com/moWerk/asteroid-blaster
Source0:    %{name}-%{version}.tar.bz2
BuildArch:  noarch
Requires:   sailfishsilica-qt5 >= 0.10.9
Requires:   libsailfishapp-launcher
Requires:   nemo-qml-plugin-configuration-qt5
Requires:   qt5-qtdeclarative-import-sensors
Requires:   libkeepalive
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  desktop-file-utils

%description
Blaster is a game where you turn your ship by tilting the device and
shoot the asteroids drifting in from every side. Ported from AsteroidOS.

%if 0%{?_chum}
Title: Blaster
Type: desktop-application
DeveloperName: moWerk
Categories:
 - Game
 - ArcadeGame
 - ActionGame
Custom:
  Repo: https://github.com/moWerk/asteroid-blaster
PackageIcon: https://raw.githubusercontent.com/moWerk/asteroid-blaster/sailfishos/store/icon-172x172.png
AIRating: V
AINote: The SailfishOS port was written by an LLM (Claude), directed and play-tested by the author on real devices; every commit carries an LLMGD disclosure line (see the README). The title art is AI-generated.
Screenshots:
 - https://raw.githubusercontent.com/moWerk/asteroid-blaster/sailfishos/store/screenshot-start-1080x2400.jpg
 - https://raw.githubusercontent.com/moWerk/asteroid-blaster/sailfishos/store/screenshot-action-1080x2400.png
 - https://raw.githubusercontent.com/moWerk/asteroid-blaster/sailfishos/store/screenshot-gameover-1080x2400.jpg
Links:
  Homepage: https://github.com/moWerk/asteroid-blaster/tree/sailfishos
  Bugtracker: https://github.com/moWerk/asteroid-blaster/issues
%endif

%prep
%setup -q -n %{name}-%{version}

%build
%qmake5
%make_build

%install
%qmake5_install
desktop-file-install --delete-original \
    --dir %{buildroot}%{_datadir}/applications \
    %{buildroot}%{_datadir}/applications/*.desktop

%files
%defattr(-,root,root,-)
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png
