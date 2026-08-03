# Contributing to `gitrl-z`

## Provenance

`gitrl-z` vendors a subtree of the gitg 44 source under `src/vendor-gitg/`. The commit graph in the preview pane is the `CommitListView` and lane renderer of gitg. It draws the full tree with the label of one branch at the position a reset would give it.

`vendor/PROVENANCE` records what the project vendors. It also gives the evidence that the source is byte-for-byte the source that Ubuntu built `gitg 44-1build2` from. `vendor/patches/` records each deviation and the cause of it.

## Build from source

Ubuntu 24.04 or equivalent is necessary:

```bash
sudo apt-get install build-essential desktop-file-utils \
    gsettings-desktop-schemas-dev libdazzle-1.0-dev libgee-0.8-dev \
    libgirepository1.0-dev libgit2-glib-1.0-dev libglib2.0-dev \
    libgtk-3-dev libhandy-1-dev libxml2-utils meson pkgconf valac

meson setup _build
ninja -C _build
./scripts/dev.sh run
```

`scripts/dev.sh` contains the common tasks (`build`, `test`, `run`, `clean`). If you set `GITRLZ_DOCKER=1`, each task runs in the build container. Use this if you do not want to install the toolchain on the host.

## Tests

```bash
./scripts/dev.sh test              # everything
./scripts/dev.sh test unit         # data layer only, no display needed
```

The `ui` suite drives real widgets in Xvfb. The `visual` suite compares the lane geometry with the installed gitg. It is off by default (`-Dvisual_tests=true`), because it needs an X server and gitg.

## Packaging

```bash
docker build -t gitrlz-build .
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$PWD:/src" -w /src gitrlz-build ./docker/build-deb.sh

./tests/packaging/test-lintian.sh
./tests/packaging/test-install.sh
```

The container installs only the declared `Build-Depends`. Thus a successful build in the container is the proof that the list is complete. A Launchpad buildd makes the same check.

## AppImage

One portable file that runs on most distributions. It needs no installation and no root access:

```bash
./scripts/build-appimage.sh
# -> gitrl-z-0.1.0-x86_64.AppImage
```

`linuxdeploy` and its GTK plug-in put GTK 3 into the file, with the GTK modules and theme, the GSettings schema, and the libraries of the application. Thus the file runs on a machine that has none of them.
