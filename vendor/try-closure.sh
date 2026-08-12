#!/bin/sh

set -eu

here=$(dirname "$(readlink -f "$0")")
root=$(dirname "$here")
out=${TMPDIR:-/tmp}/gitrlz-closure
rm -rf "$out"
mkdir -p "$out"

cat > "$out/config.h" <<'EOF'
#define APPLICATION_ID "io.github.li9i.gitrlz"
#define PROFILE ""
#define GETTEXT_PACKAGE "gitrlz"
#define PACKAGE_NAME "gitrl-z"
#define PACKAGE_VERSION "0.1.0"
#define PACKAGE_URL ""
#define GITG_DATADIR "/usr/share/gitrl-z"
#define GITG_LOCALEDIR "/usr/share/locale"
#define GITG_LIBDIR "/usr/lib/gitrl-z"
#define VERSION "0.1.0"
#define PLATFORM_NAME "unix"
EOF

valac -C -d "$out" \
	--vapidir "$root/vendor/upstream/vapi" \
	--pkg config \
	--pkg gitg-platform-support \
	--pkg gtk+-3.0 \
	--pkg gio-2.0 \
	--pkg glib-2.0 \
	--pkg gee-0.8 \
	--pkg libgit2-glib-1.0 \
	--pkg libdazzle-1.0 \
	--pkg gsettings-desktop-schemas \
	--target-glib 2.68 \
	--gresources "$root/src/vendor-gitg/libgitg/resources/resources.xml" \
	--gresourcesdir "$root/src/vendor-gitg/libgitg/resources" \
	"$@" \
	$(find "$root/src/vendor-gitg" -name '*.vala' | sort)
