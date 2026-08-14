# How to release gitrl-z

A release is four things: the version bump on `master`, an annotated tag, the
artefacts on the GitHub releases page, and a source upload to the PPA for each
series.

Everything up to the upload runs from a checkout. The upload needs credentials
that only you have.

## Current state

- `debian/` is complete, and lintian reports no unoverridden problem at
  `--pedantic --info`. There is one recorded override
  (`initial-upload-closes-no-bugs`). Lintian says that you can ignore this
  override for packages that are not for Debian.
- The `.deb` builds in a container that holds only the declared
  `Build-Depends`. A Launchpad buildd makes the same check.
- The install, remove and purge operations are verified in an unmodified
  `ubuntu:24.04`.
- The package is `gitrl-z`. The command is `gitrlz`. The version is `0.7.0-1`,
  built for **noble** (24.04) and **resolute** (26.04).

## Preliminary steps

You must do these steps yourself. They are necessary one time only.

1. **A Launchpad account.** <https://launchpad.net/+login>
2. **A GPG key, registered with Launchpad.** If you do not have one:

   ```bash
   gpg --full-generate-key           # RSA 4096, no expiry or a long one
   gpg --list-secret-keys --keyid-format=long
   gpg --send-keys --keyserver keyserver.ubuntu.com <KEYID>
   ```

   Then add its fingerprint at <https://launchpad.net/~/+editpgpkeys>.
   Confirm the encrypted email that Launchpad sends.
3. **An SSH key registered** at <https://launchpad.net/~/+editsshkeys>.
4. **Sign the Ubuntu Code of Conduct** at
   <https://launchpad.net/codeofconduct>. Launchpad refuses PPA uploads if
   you do not sign it.
5. **The PPA** is `ppa:li9i/gitrl-z`. It builds for noble and for resolute.
   Enable a series in its settings before you upload for that series.

The maintainer address in `debian/control` and `debian/changelog` is
`alexandros filotheou <alexandros.filotheou@gmail.com>`. It agrees with
`git config user.email`.

`debsign` selects a signing key: it compares that line with your GPG UIDs. If
your key does not have this address, `debsign` refuses after it builds the
source package. This looks like a build problem, but it is not one. Examine
your keys with `gpg --list-secret-keys --keyid-format=long`. Then add the
address as a UID (`gpg --edit-key <ID>` then `adduid`), or give `-k <KEYID>`.

## Cut the release

Work on a clean tree.

1. Run the tests. The `ui` suite needs a display:

   ```bash
   xvfb-run -a ./scripts/dev.sh test
   ```

2. Bump `version` in `meson.build`.
3. Add a `<release>` entry at the top of the `<releases>` block in
   `data/io.github.li9i.gitrlz.metainfo.xml.in`. A few short paragraphs, in
   the order that matters to a user. `meson test --suite data` validates it.
4. Add an entry at the top of `debian/changelog`. Keep `noble` as the
   distribution and `-1` as the revision. `docker/build-deb.sh` rewrites both
   per series at build time, so the file in the repository names one series
   only.
5. Commit the three files as `Release X.Y.Z`, tag the commit, push both:

   ```bash
   git tag -a vX.Y.Z          # the annotation is the release prose
   git push origin master
   git push origin vX.Y.Z
   ```

## Build the artefacts

A `.deb` links the libraries of the series it was built on, so each series
needs its own container.

```bash
docker build --build-arg UBUNTU=24.04 -t gitrlz-build:24.04 .
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$PWD:/src" -w /src gitrlz-build:24.04 \
    ./docker/build-deb.sh noble '~ubuntu24.04.1'

docker build --build-arg UBUNTU=26.04 -t gitrlz-build:26.04 .
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$PWD:/src" -w /src gitrlz-build:26.04 \
    ./docker/build-deb.sh resolute '~ubuntu26.04.1'

./scripts/build-appimage.sh
```

Both `.deb` builds write to `_build/deb/` and neither clears it. Empty it
before a release, so that the checks below and the upload cannot pick up an
artefact from an earlier version.

## Check the artefacts

```bash
./tests/packaging/test-lintian.sh \
    _build/deb/gitrl-z_X.Y.Z-1~ubuntu24.04.1_amd64.changes
./tests/packaging/test-install.sh
```

Given no argument, `test-lintian.sh` takes the first `.changes` it finds, which
is the wrong one whenever an older build is still in `_build/deb`. Name the
file you mean.

`binary-nmu-debian-revision-in-source` is expected and is the only tag you
should see. It is the `~ubuntuNN.NN.N` suffix that the PPA versioning needs,
applied to the source package as well as the binary.

## Publish on GitHub

```bash
gh release create vX.Y.Z --title "gitrl-z X.Y.Z" --verify-tag \
    --notes-file <file> --generate-notes \
    gitrl-z-X.Y.Z-x86_64.AppImage \
    _build/deb/gitrl-z_X.Y.Z-1~ubuntu24.04.1_amd64.deb \
    _build/deb/gitrl-z_X.Y.Z-1~ubuntu26.04.1_amd64.deb
```

The tag annotation makes a good notes file:

```bash
git tag -l vX.Y.Z --format='%(contents:body)' > notes.md
```

GitHub writes `~` as `.` in the names of the assets it stores. The download
instructions in `README.md` name no version, so a release does not change them.

## Build and sign the source package

A PPA takes a **source** upload and builds the binary itself. The binary that
you build locally is for tests only. You do not upload it.

```bash
# From a clean tree, in the build container:
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$PWD:/src" -w /src gitrlz-build:24.04 \
    ./docker/build-deb.sh noble '~ubuntu24.04.1'

# Then sign, on the host, where your GPG key lives:
cd _build/deb
debsign -k <KEYID> gitrl-z_X.Y.Z-1~ubuntu24.04.1_amd64.changes
```

`docker/build-deb.sh` builds unsigned (`-us -uc`). The container has no access
to your key, and it must not have access.

If you need a source-only `.changes`, use these commands. Launchpad accepts the
two forms, but source-only is cleaner:

```bash
cd /path/to/clean/tree
dpkg-buildpackage -S -sa
debsign -k <KEYID> ../gitrl-z_X.Y.Z-1~ubuntu24.04.1_source.changes
```

## Upload

```bash
dput ppa:li9i/gitrl-z gitrl-z_X.Y.Z-1~ubuntu24.04.1_source.changes
```

Upload once per series, with the `.changes` that names that series.

`dput` is in the build container, but run this command on the host. It needs
your key and your network identity.

## After the upload

1. Monitor the build at
   <https://launchpad.net/~li9i/+archive/ubuntu/gitrl-z/+packages>.
   A first build starts after some minutes, and it needs some more minutes.
2. **Read the build log, also when the build is successful.** The buildd is a
   cleaner environment than the container. A warning in the log is important.
3. Verify the package on a clean machine:

   ```bash
   sudo add-apt-repository ppa:li9i/gitrl-z
   sudo apt-get update
   sudo apt-get install gitrl-z
   gitrlz --version
   ```

   `tests/packaging/test-install.sh` does the equivalent test with a local
   `.deb`. But you must do this test one time with the real PPA.

## Known problems

- **You cannot upload a rejected upload again with the same version.**
  Launchpad keeps the version, also for a failed build. Increase the revision
  to `-2` and upload again. Do not try to replace it.
- **You upload the `orig.tar.gz` one time only.** Subsequent Debian revisions
  of the same upstream version must *not* include it. If they include it,
  Launchpad rejects the upload because of a file conflict. Use `-sd` in place
  of `-sa` after the first upload.
- **`Distribution` in `debian/changelog` must agree with the PPA series.** If
  an upload names a series that the PPA does not build for, Launchpad discards
  the upload and gives no message. `docker/build-deb.sh` writes that line from
  its first argument, so pass the codename of the series you are building for.
- **The source package carries the working tree.** `docker/build-deb.sh` tars
  the checkout, less `_build`, `.git`, `vendor/upstream` and any `.AppImage`.
  The AppImage is excluded because building it before the packages otherwise
  puts 36 MB of prebuilt binary in the source, which lintian reports as
  `source-is-missing`. Anything else you leave in the tree does travel.
- **The orig tarball is about 2.6 MB.** It holds the vendored gitg subtree and
  the animations in `docs/screenshots`. This is intentional. The package is
  self-contained, and it does not build against a `libgitg`, because Ubuntu
  does not supply `libgitg` as a development package.

## Series

The vendored source agrees with gitg 44 (`vendor/PROVENANCE`). Noble carries
`44-1build2` and resolute carries `44-6build2`, the same upstream version.
**Before you add a series, make sure it supplies gitg 44.** A different gitg
version means that the vendored source does not agree with the gitg installed
on the machine of the user. The full project depends on this agreement.
`Dockerfile.visual` asserts the exact package version, which is noble's, so the
visual suite runs on the noble image.

To add a series, build its image with `--build-arg UBUNTU=<version>`, pass its
codename and a `~ubuntu<version>.1` suffix to `docker/build-deb.sh`, enable it
in the PPA settings, and upload the `.changes` that names it.
