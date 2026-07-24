#!/bin/sh
# Run a UI test under a private X server.
#
# The ui suite constructs real widgets, so it needs a display. Xvfb gives it
# one that does not depend on the developer having a session open, and does
# not put test windows on their screen.
#
# The server arguments are fixed rather than left to xvfb-run's defaults so
# that a test asserting on widget allocation gets the same geometry on every
# machine.

set -eu

# GLib.Test promotes warnings to fatal, and with no accessibility bus running
# the AT-SPI bridge warns at startup ("Error retrieving accessibility bus
# address"), taking every UI test down before it runs. Disabling the bridge is
# the usual answer for headless GTK tests; nothing here tests accessibility.
NO_AT_BRIDGE=1
GTK_A11Y=none
export NO_AT_BRIDGE GTK_A11Y

exec xvfb-run -a \
	--server-args="-screen 0 1200x800x24 -nolisten tcp" \
	"$@"
