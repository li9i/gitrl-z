ARG UBUNTU=24.04
FROM ubuntu:${UBUNTU}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        appstream \
        build-essential \
        ca-certificates \
        desktop-file-utils \
        gsettings-desktop-schemas-dev \
        libgee-0.8-dev \
        libgirepository1.0-dev \
        libgit2-glib-1.0-dev \
        libglib2.0-dev \
        libgtk-3-dev \
        libgtksourceview-4-dev \
        libhandy-1-dev \
        libxml2-utils \
        meson \
        ninja-build \
        pkg-config \
        valac \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
        adwaita-icon-theme \
        dbus-x11 \
        git \
        imagemagick \
        librsvg2-common \
        shared-mime-info \
        x11-apps \
        xdotool \
        xauth \
        xvfb \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
        debhelper \
        devscripts \
        dpkg-dev \
        fakeroot \
        lintian \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
CMD ["/bin/bash"]
