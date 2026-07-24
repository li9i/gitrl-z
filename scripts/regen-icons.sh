#!/bin/sh
# Regenerate the downscaled application icons from the 128 px original.
#
# The application icon is raster artwork, not an SVG, so hicolor gets one file
# per size rather than a single scalable/ entry. Only the 128 px file is
# authored; the smaller ones are derived and committed, so that building the
# package needs no image tooling. Run this after replacing the original.
#
# Lanczos rather than the default filter: the icon's git glyph is thin, and a
# box or bilinear downscale loses the branch line at 48 px.

set -eu

cd "$(dirname "$0")/.."

src=data/icons/io.github.li9i.gitrlz-128.png
test -f "$src" || { echo "regen-icons: $src not found" >&2; exit 1; }

python3 - "$src" <<'EOF'
import sys
from PIL import Image

src = Image.open(sys.argv[1])
if src.size != (128, 128):
    sys.exit(f"regen-icons: expected a 128x128 original, got {src.size[0]}x{src.size[1]}")

for size in (64, 48):
    out = f"data/icons/io.github.li9i.gitrlz-{size}.png"
    src.resize((size, size), Image.LANCZOS).save(out, optimize=True)
    print(f"wrote {out}")
EOF
