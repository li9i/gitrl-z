# Visual regression

This suite compares the commit graph of gitrl-z with the installed gitg. It
compares the **geometry**, not the pixels (spec 6.3.1).

## A pixel diff would compare nothing meaningful

gitg shows all refs. The preview of gitrl-z shows local branches, with one
tip substituted. The two draw different commit sets by design. But the lane
spacing, the dot radius, the row height and the lane colour are readable from
two different graphs. These are the properties that FR-102 delegates to
vendored code.

A failure also names the property and the two values. A pixel diff would give
a pixel count only, and you must then find what moved.

## How to run it

```bash
docker build -f Dockerfile.visual -t gitrlz-visual .
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$PWD:/src" -w /src gitrlz-visual ./tests/visual/test-parity.sh
```

Or through meson, which keeps it off by default:

```bash
meson setup _build -Dvisual_tests=true
meson test -C _build --suite visual
```

## Result on gitg 44-1build2

| Property | gitg | gitrl-z |
|---|---|---|
| lane spacing | 16 px | 16 px |
| dot radius | 5.0 px | 5.0 px |
| row height | 23 px | 23 px |
| first lane colour | `#c4a000` | `#c4a000` |

The dot *counts* and the lane *counts* are different, as they must be,
because the commit sets are different.

## A warning about the measurement

`measure.py` needed four revisions to become reliable. Two of those revisions
gave numbers that looked correct and were wrong: a "dot radius" of 224 px,
and eight lanes of the selection blue of Adwaita. The cause was a measurement
of the full window, where ref pills, selection highlights and header-bar
chrome all look like lane dots.

Two changes corrected this, and the two are important if you change this
code:

1. **Compare with the palette of gitg, not with a saturated appearance.** The
   palette is a copy from `gitg-color.vala`. It is the definition of a lane
   colour, not an estimate of one.
2. **Require recurrence.** A lane is vertical and appears on several rows. A
   ref pill appears one time only. The pill blue of gitg `#204a87` is itself
   a palette entry, thus the colour alone cannot separate them.

The crop windows in `test-parity.sh` are constants of the fixture and the
window size. They are not constants of the applications. If you change the
fixture or the window size, derive the crop windows again against
`reference/`.

`selfcheck.py` runs on each pass. It fails the suite if a 130% rescale stays
undetected. This check is necessary. The larger risk is not that the
comparison finds a difference. The larger risk is that the comparison stops
being able to find one, and gives no message.

## Files

| File | Role |
|---|---|
| `fixture.sh` | deterministic repository with many lanes |
| `capture.sh` | screenshot in a pinned Xvfb |
| `capture-gitrlz.sh` | the same, but selects a row so that a preview graph exists |
| `measure.py` | reads the geometry from a capture |
| `selfcheck.py` | proves that the comparison can fail |
| `test-parity.sh` | the suite |
| `reference/` | committed captures and the measurements of gitg |
