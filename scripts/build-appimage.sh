#!/bin/sh

set -eu

root=$(dirname "$(dirname "$(readlink -f "$0")")")
cd "$root"

version=$(grep -oP "version: '\K[0-9.]+" meson.build | head -1)
work=_build/appimage
appdir=$work/AppDir
tools=$work/tools

[ -d "$work/build" ] || meson setup "$work/build" --prefix=/usr -Dprofile=default
ninja -C "$work/build"
rm -rf "$appdir"
DESTDIR="$PWD/$appdir" ninja -C "$work/build" install

sourceview_data=/usr/share/gtksourceview-4

if [ -d "$sourceview_data" ]; then
	mkdir -p "$appdir/usr/share"
	cp -r "$sourceview_data" "$appdir/usr/share/"
else
	echo "warning: $sourceview_data is absent; the AppImage will not highlight" >&2
fi

mkdir -p "$tools"
fetch() { [ -f "$tools/$2" ] || curl -fsSL -o "$tools/$2" "$1"; }
ld=https://github.com/linuxdeploy
fetch "$ld/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage" linuxdeploy-x86_64.AppImage
fetch "https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh" linuxdeploy-plugin-gtk.sh
fetch "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage" appimagetool-x86_64.AppImage
chmod +x "$tools"/*.AppImage "$tools/linuxdeploy-plugin-gtk.sh"
ln -sf appimagetool-x86_64.AppImage "$tools/appimagetool"

APPIMAGE_EXTRACT_AND_RUN=1 DEPLOY_GTK_VERSION=3 VERSION="$version" \
PATH="$PWD/$tools:$PATH" \
	"$tools/linuxdeploy-x86_64.AppImage" \
		--appdir "$appdir" \
		--executable "$appdir/usr/bin/gitrlz" \
		--desktop-file "$appdir/usr/share/applications/io.github.li9i.gitrlz.desktop" \
		--icon-file "$appdir/usr/share/icons/hicolor/128x128/apps/io.github.li9i.gitrlz.png" \
		--plugin gtk

schemas=$appdir/usr/share/glib-2.0/schemas
cp "$work/build/data/io.github.li9i.gitrlz.gschema.xml" "$schemas/"
glib-compile-schemas "$schemas"

rm -f "$root"/gitrl-z-*-x86_64.AppImage
APPIMAGE_EXTRACT_AND_RUN=1 VERSION="$version" \
	"$tools/appimagetool-x86_64.AppImage" \
		"$appdir" "$root/gitrl-z-$version-x86_64.AppImage"

echo "--- built ---"
ls -la "$root"/gitrl-z-*-x86_64.AppImage
