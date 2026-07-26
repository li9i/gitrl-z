# Contributing to `gitrl-z`

## Provenance

`gitrl-z` vendors a subtree of gitg 44's source under `src/vendor-gitg/`. The commit graph in the preview pane is not a lookalike: it is gitg's own `CommitListView` and lane renderer, drawing the whole tree with one branch's label moved to where a reset would put it.

`vendor/PROVENANCE` records exactly what was vendored, and the evidence that it is byte-for-byte the source Ubuntu's `gitg 44-1build2` was built from. `vendor/patches/` records every deviation, with a rationale for each.

## Building from source

Needs Ubuntu 24.04 or equivalent:

```bash
sudo apt-get install build-essential desktop-file-utils \
    gsettings-desktop-schemas-dev libdazzle-1.0-dev libgee-0.8-dev \
    libgirepository1.0-dev libgit2-glib-1.0-dev libglib2.0-dev \
    libgtk-3-dev libhandy-1-dev libxml2-utils meson pkgconf valac

meson setup _build
ninja -C _build
./scripts/dev.sh run
```

`scripts/dev.sh` wraps the common tasks (`build`, `test`, `run`, `clean`). Setting `GITRLZ_DOCKER=1` runs any of them inside the build container instead, which is useful if you would rather not install the toolchain.

## Tests

```bash
./scripts/dev.sh test              # everything
./scripts/dev.sh test unit         # data layer only, no display needed
```

The `ui` suite drives real widgets under Xvfb. The `visual` suite compares lane geometry against the installed gitg and is off by default (`-Dvisual_tests=true`), since it needs an X server and gitg itself.

## Packaging

```bash
docker build -t gitrlz-build .
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$PWD:/src" -w /src gitrlz-build ./docker/build-deb.sh

./tests/packaging/test-lintian.sh
./tests/packaging/test-install.sh
```

The container installs only the declared `Build-Depends`, so building there is what proves that list complete, the same check a Launchpad buildd performs.

## AppImage

A portable single file that runs on most distributions with no install and no root:

```bash
./scripts/build-appimage.sh
# -> gitrl-z-0.1.0-x86_64.AppImage
```

`linuxdeploy` and its GTK plugin bundle GTK 3, its modules and theme, the GSettings schema, and the app's own libraries into the file, so it runs on a machine that has none of them.
