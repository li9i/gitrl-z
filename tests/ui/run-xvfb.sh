#!/bin/sh

set -eu

NO_AT_BRIDGE=1
GTK_A11Y=none
export NO_AT_BRIDGE GTK_A11Y

exec xvfb-run -a \
	--server-args="-screen 0 1200x800x24 -nolisten tcp" \
	"$@"
