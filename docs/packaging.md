# Releasing gitrl-z

Plan step 24. Everything up to the upload is done and verified; the upload
itself needs credentials only you have.

## What is already true

- `debian/` is complete and lintian-clean at `--pedantic --info`, with one
  documented override (`initial-upload-closes-no-bugs`, which lintian itself
  says can be ignored for packages not intended for Debian).
- The `.deb` builds in a container holding only the declared `Build-Depends`,
  which is the same check a Launchpad buildd performs.
- Install, remove and purge are verified in a stock `ubuntu:24.04`.
- The package is `gitrl-z`, the command is `gitrlz`, the version is `0.1.0-1`,
  targeting **noble**.

## What you need to do first

These cannot be done by an agent.

1. **A Launchpad account.** <https://launchpad.net/+login>
2. **A GPG key, registered with Launchpad.** If you do not already have one:

   ```bash
   gpg --full-generate-key           # RSA 4096, no expiry or a long one
   gpg --list-secret-keys --keyid-format=long
   gpg --send-keys --keyserver keyserver.ubuntu.com <KEYID>
   ```

   Then add its fingerprint at <https://launchpad.net/~/+editpgpkeys> and
   confirm the encrypted email Launchpad sends.
3. **An SSH key registered** at <https://launchpad.net/~/+editsshkeys>.
4. **Sign the Ubuntu Code of Conduct** at
   <https://launchpad.net/codeofconduct> — Launchpad refuses PPA uploads
   without it.
5. **Create the PPA** at `https://launchpad.net/~<you>/+activate-ppa`. Name it
   `gitrl-z`. Enable **noble** in its settings.

## Filling in the placeholders

Three files carry a `<owner>` placeholder that must become your Launchpad
username:

| File | What to change |
|---|---|
| `README.md` | the `add-apt-repository ppa:<owner>/gitrl-z` line |
| `docs/packaging.md` | this file's `dput` line below |

The maintainer address in `debian/control` and `debian/changelog` is
`alexandros filotheou <alexandros.filotheou@gmail.com>`, confirmed by the
operator and matching `git config user.email`.

`debsign` picks a signing key by matching that line against your GPG UIDs, so
if the key you intend to sign with does not carry this address it will refuse
after the source package is built — which reads as a build problem but is not.
Check with `gpg --list-secret-keys --keyid-format=long`, and either add the
address as a UID (`gpg --edit-key <ID>` then `adduid`) or pass `-k <KEYID>`.

## Building and signing the source package

A PPA takes a **source** upload and builds the binary itself. The binary you
have built locally is for testing; it is not what gets uploaded.

```bash
# From a clean tree, in the build container:
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$PWD:/src" -w /src gitrlz-build ./docker/build-deb.sh

# Then sign, on the host, where your GPG key lives:
cd _build/deb
debsign -k <KEYID> gitrl-z_0.1.0-1_source.changes
```

`docker/build-deb.sh` builds unsigned (`-us -uc`) because the container has no
access to your key, and should not.

If you need a source-only `.changes` (Launchpad accepts either, but
source-only is tidier):

```bash
cd /path/to/clean/tree
dpkg-buildpackage -S -sa
debsign -k <KEYID> ../gitrl-z_0.1.0-1_source.changes
```

## Uploading

```bash
dput ppa:<owner>/gitrl-z gitrl-z_0.1.0-1_source.changes
```

`dput` is already in the build container, but run this on the host: it needs
your key and your network identity.

## After the upload

1. Watch the build at
   `https://launchpad.net/~<owner>/+archive/ubuntu/gitrl-z/+packages`.
   A first build usually starts within a few minutes and takes several more.
2. **Read the build log even if it succeeds.** The buildd is a cleaner
   environment than the container; a warning there is worth knowing about.
3. Verify on a clean machine:

   ```bash
   sudo add-apt-repository ppa:<owner>/gitrl-z
   sudo apt-get update
   sudo apt-get install gitrl-z
   gitrlz --version
   ```

   `tests/packaging/test-install.sh` does the equivalent against a local
   `.deb`; there is no substitute for doing it once against the real PPA.

## Things that will bite you

- **A rejected upload cannot be re-uploaded under the same version.**
  Launchpad remembers the version even for a failed build. Bump to `0.1.0-2`
  and upload again; do not try to replace it.
- **The `orig.tar.gz` is uploaded once.** Subsequent Debian revisions of the
  same upstream version must *not* include it, or Launchpad rejects the upload
  as a file conflict. Use `-sd` rather than `-sa` after the first upload.
- **`Distribution: noble` in `debian/changelog` must match the PPA series.**
  An upload naming a series the PPA does not build for is silently dropped.
- **The vendored gitg subtree is in the orig tarball**, which makes it about
  280 KB. That is intended: the package is self-contained and does not build
  against a `libgitg` that Ubuntu does not ship as a development package.

## Later series

0.1.0 targets noble only, matching the gitg the source was vendored from
(`vendor/PROVENANCE`). To publish for another series, change the
`Distribution` in `debian/changelog`, rebuild and re-upload — **and first
check that series ships gitg 44**. A different gitg means the vendored source
no longer matches what users have installed, which is the entire premise of
the project. `Dockerfile.visual` asserts the version for exactly this reason.
