#!/bin/sh
# Build a portable AppImage of gitrl-z.
#
# Run from the repository root:
#
#   ./scripts/build-appimage.sh
#   -> gitrl-z-<version>-x86_64.AppImage in the repository root
#
# The app is installed into an AppDir, then linuxdeploy and its GTK plugin
# bundle GTK 3, its modules, theme and pixbuf loaders, the compiled GSettings
# schema, and the app's own libraries (libgit2-glib, libgit2, libgee,
# libhandy), so the result runs on a machine that has none of them. No root and
# no online account are needed, to build or to publish (it is one file, meant
# to be attached to a GitHub release).
#
# The AppImage tooling is fetched once into _build/appimage/tools and cached.
# APPIMAGE_EXTRACT_AND_RUN lets those tools run where FUSE is unavailable.

set -eu

root=$(dirname "$(dirname "$(readlink -f "$0")")")
cd "$root"

version=$(grep -oP "version: '\K[0-9.]+" meson.build | head -1)
work=_build/appimage
appdir=$work/AppDir
tools=$work/tools

# 1. Install into an AppDir under /usr, the layout AppImage tools expect.
[ -d "$work/build" ] || meson setup "$work/build" --prefix=/usr -Dprofile=default
ninja -C "$work/build"
rm -rf "$appdir"
DESTDIR="$PWD/$appdir" ninja -C "$work/build" install

# 2. Fetch the tools once (continuous builds, as AppImage upstream ships them).
mkdir -p "$tools"
fetch() { [ -f "$tools/$2" ] || curl -fsSL -o "$tools/$2" "$1"; }
ld=https://github.com/linuxdeploy
fetch "$ld/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage" linuxdeploy-x86_64.AppImage
fetch "https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh" linuxdeploy-plugin-gtk.sh
fetch "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage" appimagetool-x86_64.AppImage
chmod +x "$tools"/*.AppImage "$tools/linuxdeploy-plugin-gtk.sh"
# linuxdeploy looks for `appimagetool` on PATH; give it one.
ln -sf appimagetool-x86_64.AppImage "$tools/appimagetool"

# 3. Bundle everything and emit the AppImage into the repository root.
rm -f "$root"/gitrl-z-*-x86_64.AppImage
APPIMAGE_EXTRACT_AND_RUN=1 DEPLOY_GTK_VERSION=3 VERSION="$version" \
PATH="$PWD/$tools:$PATH" \
	"$tools/linuxdeploy-x86_64.AppImage" \
		--appdir "$appdir" \
		--executable "$appdir/usr/bin/gitrlz" \
		--desktop-file "$appdir/usr/share/applications/io.github.li9i.gitrlz.desktop" \
		--icon-file "$appdir/usr/share/icons/hicolor/128x128/apps/io.github.li9i.gitrlz.png" \
		--plugin gtk \
		--output appimage

echo "--- built ---"
ls -la "$root"/gitrl-z-*-x86_64.AppImage
