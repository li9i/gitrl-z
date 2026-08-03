# The build container

## Purpose

The container is **not** the development environment. Spec NFR-10 says that
development and operation occur natively on the host. The host is already the
target platform, Ubuntu 24.04 noble with gitg 44. A native run also gets the
real GTK theme, with no X11 socket configuration.

The container proves that `Build-Depends` is complete. It installs a declared
list and nothing else. Thus the build fails here if it needs software that is
not on that list. This occurs also when that software is on the machine of
the developer. `pbuilder` and `sbuild` do the same for Debian maintainers.
This is why the
package build runs in the container and not on the host.

The container is also useful if the host has no Vala toolchain and an
installation needs a password.

## How to use it

    docker build -t gitrlz-build .

    # Any dev.sh command, in the container instead of natively:
    GITRLZ_DOCKER=1 ./scripts/dev.sh build
    GITRLZ_DOCKER=1 ./scripts/dev.sh test

    # Interactive shell (always containerised):
    ./scripts/dev.sh shell

Docker bind-mounts the source tree at `/src`, and copies nothing into the
image. Edit on the host, build in the container.

`scripts/dev.sh` runs the container as the user who calls it
(`--user $(id -u)`). Thus root does not own the build products in the
bind-mounted tree. If you run `docker run` manually without that flag,
`./scripts/dev.sh clean` becomes necessary.

## How to run the GUI from the container

The container has Xvfb. Thus you can run the application and make a
screenshot with no display:

    docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
        -v "$PWD:/src" -w /src gitrlz-build \
        xvfb-run -a --server-args="-screen 0 1200x800x24" ./_build/src/gitrlz/gitrlz

This is how the screenshot was made. A window that Xvfb renders uses the
theme of the container, **not** the theme of the host. Thus a visual
comparison with the installed gitg must occur on the host, and the visual
suite is off by default (spec 6.3).

## Dependency list

The `Dockerfile` installs an intentionally smaller set. It is the gitg
`Build-Depends` of Debian, less the dependencies of the subsystems that
gitrl-z excludes (gtksourceview-4, gspell, json-glib, libsecret, gpgme,
libpeas, and the libxml2 chain). The `Dockerfile` gives a note for each
removed dependency.

A successful build in the container shows that these removals are correct.
