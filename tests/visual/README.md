# Visual regression

Compares gitrl-z's commit graph against the installed gitg on **geometry**, not
pixels (spec 6.3.1).

## Why not a pixel diff

gitg shows all refs; gitrl-z's preview shows local branches with one tip
substituted. The two draw different commit sets by design, so a pixel diff
would compare nothing meaningful. Lane spacing, dot radius, row height and
lane colour are readable from two different graphs, and they are precisely
the properties FR-102 delegates to vendored code.

A failure also names the property and both values, where a pixel diff would
report a pixel count and leave you to find what moved.

## Running

```bash
docker build -f Dockerfile.visual -t gitrlz-visual .
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$PWD:/src" -w /src gitrlz-visual ./tests/visual/test-parity.sh
```

Or through meson, which gates it off by default:

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

Dot and lane *counts* differ, as they should: different commit sets.

## A warning about the measurement

`measure.py` took four revisions to become trustworthy, and two of those
reported confident, entirely wrong numbers — a "dot radius" of 224 px, eight
lanes of Adwaita's selection blue. The failure mode was measuring the whole
window, where ref pills, selection highlights and header-bar chrome all look
like lane dots.

Two things fixed it, and both matter if you change this code:

1. **Match against gitg's palette, not against "looks saturated".** The
   palette is copied from `gitg-color.vala`; it is the definition of a lane
   colour rather than a guess at one.
2. **Require recurrence.** A lane is vertical and appears on several rows; a
   ref pill appears once. gitg's pill blue `#204a87` is itself a palette
   entry, so colour alone cannot separate them.

The crop windows in `test-parity.sh` are constants of the fixture and the
window size, not of the applications. Change either and re-derive them against
`reference/`.

`selfcheck.py` runs on every pass and fails the suite if a 130% rescale goes
undetected. That is not ceremony: given the history above, the realistic risk
is not that the comparison finds a difference, it is that it silently stops
being able to.

## Files

| File | Role |
|---|---|
| `fixture.sh` | deterministic lane-rich repository |
| `capture.sh` | screenshot under a pinned Xvfb |
| `capture-gitrlz.sh` | same, but selects a row so a preview graph exists |
| `measure.py` | extract geometry from a capture |
| `selfcheck.py` | prove the comparison can fail |
| `test-parity.sh` | the suite |
| `reference/` | committed captures and gitg's measurements |
