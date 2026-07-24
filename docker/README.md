# The build container

## Why it exists

The container is **not** the intended development environment. Spec NFR-10
says development and running happen natively on the host, because the host is
already the target platform — Ubuntu 24.04 noble with gitg 44 — and running
natively gets the real GTK theme with no X11 socket plumbing.

What the container is for is proving that `Build-Depends` is complete. It
installs a declared list and nothing else, so anything the build needs that
is not on that list fails here even if it happens to be sitting on the
developer's machine. That is the same job `pbuilder` and `sbuild` do for
Debian maintainers, and it is why the package build runs in
here rather than on the host.

It is also useful when the host lacks the Vala toolchain and installing it
would need a password.

## Using it

    docker build -t gitrlz-build .

    # Any dev.sh command, in the container instead of natively:
    GITRLZ_DOCKER=1 ./scripts/dev.sh build
    GITRLZ_DOCKER=1 ./scripts/dev.sh test

    # Interactive shell (always containerised):
    ./scripts/dev.sh shell

The source tree is bind-mounted at `/src`; nothing is copied into the image.
Edit on the host, build in the container.

`scripts/dev.sh` runs the container as the invoking user (`--user $(id -u)`)
so build products in the bind-mounted tree are not left owned by root. If you
run `docker run` by hand without that flag, expect to need
`./scripts/dev.sh clean` afterwards.

## Running the GUI from the container

The container has Xvfb, so the application can be run and screenshotted
headlessly:

    docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
        -v "$PWD:/src" -w /src gitrlz-build \
        xvfb-run -a --server-args="-screen 0 1200x800x24" ./_build/src/gitrlz/gitrlz

That is how the M1 gate screenshot was taken. Note that a window rendered
under Xvfb uses whatever theme the container has, **not** the host's — which
is precisely why visual comparison against the installed gitg belongs on the
host, and why the visual suite is gated off by default (spec 6.3).

## Dependency list

The `Dockerfile` installs a deliberately reduced set: Debian's gitg
`Build-Depends` minus everything gitrl-z's excluded subsystems drag in
(gtksourceview-4, gspell, json-glib, libsecret, gpgme, libpeas, and the
libxml2 chain). Each omission is annotated in the `Dockerfile`.

The build succeeding in here is the evidence for that pruning.
