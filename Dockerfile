# Build environment for gitrl-z.
#
# Defaults to Ubuntu 24.04 noble, the series that ships gitg 44 (see
# vendor/PROVENANCE). Override with --build-arg UBUNTU=26.04 to build against
# another series; build-deb.sh then produces that series' .deb. The visual
# image (Dockerfile.visual) builds FROM the default.
#
# Source is NOT copied in. It arrives as a bind mount at /src, so the tree
# can be edited on the host and built here (spec NFR-10). That also means
# this image proves Build-Depends completeness: anything the build needs
# that is not listed below will fail here even if it happens to be
# installed on the developer's machine.

ARG UBUNTU=24.04
FROM ubuntu:${UBUNTU}

ENV DEBIAN_FRONTEND=noninteractive

# Build dependencies.
#
# Derived from Debian's gitg 44-1 Build-Depends (kept in
# vendor/gitg_44-1build2.debian.tar.xz), minus everything gitrl-z drops:
#
#   libgtksourceview-4-dev  diff view          out of scope, spec 1.3
#   libgspell-1-dev         spell checking     out of scope (commit messages)
#   libjson-glib-dev        diff view          out of scope
#   libsecret-1-dev         credentials        out of scope (no remotes)
#   libgpgme-dev            signatures         out of scope
#   libpeas-dev             plugin loader      dropped, spec 1.3
#   dh-sequence-gir         GIR generation     nothing external links us
#
# libxml2-utils is a build-time tool (xmllint), not a link dependency —
# Debian lists it as -utils, not -dev.
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
        libhandy-1-dev \
        libxml2-utils \
        meson \
        ninja-build \
        pkg-config \
        valac \
    && rm -rf /var/lib/apt/lists/*

# Test dependencies: git for fixture repositories, Xvfb for UI tests,
# ImageMagick for the visual suite.
#
# adwaita-icon-theme, librsvg2-common and shared-mime-info are needed by the
# UI suite rather than by the build: GTK renders check buttons and other
# widget parts from Adwaita's SVG assets, and without the librsvg pixbuf
# loader it aborts with "Could not load a pixbuf from ... check-symbolic.svg".
# A real desktop has all three already, which is why this only bites here.
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

# Packaging tools.
RUN apt-get update && apt-get install -y --no-install-recommends \
        debhelper \
        devscripts \
        dpkg-dev \
        fakeroot \
        lintian \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
CMD ["/bin/bash"]
