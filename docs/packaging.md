# How to release gitrl-z

All the steps before the upload are complete and verified. The upload needs
credentials that only you have.

## Current state

- `debian/` is complete, and lintian reports no problem at `--pedantic
  --info`. There is one recorded override (`initial-upload-closes-no-bugs`).
  Lintian says that you can ignore this override for packages that are not
  for Debian.
- The `.deb` builds in a container that holds only the declared
  `Build-Depends`. A Launchpad buildd makes the same check.
- The install, remove and purge operations are verified in an unmodified
  `ubuntu:24.04`.
- The package is `gitrl-z`. The command is `gitrlz`. The version is
  `0.1.0-1`, for **noble**.

## Preliminary steps

You must do these steps yourself.

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
5. **Create the PPA** at `https://launchpad.net/~<you>/+activate-ppa`. Name it
   `gitrl-z`. Enable **noble** in its settings.

## Placeholders

Some files contain a `<owner>` placeholder. Replace it with your Launchpad
username:

| File | What to change |
|---|---|
| `README.md` | the `add-apt-repository ppa:<owner>/gitrl-z` line |
| `docs/packaging.md` | this file's `dput` line below |

The maintainer address in `debian/control` and `debian/changelog` is
`alexandros filotheou <alexandros.filotheou@gmail.com>`. It agrees with
`git config user.email`.

`debsign` selects a signing key: it compares that line with your GPG UIDs. If
your key does not have this address, `debsign` refuses after it builds the
source package. This looks like a build problem, but it is not one. Examine
your keys with `gpg --list-secret-keys --keyid-format=long`. Then add the
address as a UID (`gpg --edit-key <ID>` then `adduid`), or give `-k <KEYID>`.

## Build and sign the source package

A PPA takes a **source** upload and builds the binary. The binary that you
build locally is for tests only. You do not upload it.

```bash
# From a clean tree, in the build container:
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$PWD:/src" -w /src gitrlz-build ./docker/build-deb.sh

# Then sign, on the host, where your GPG key lives:
cd _build/deb
debsign -k <KEYID> gitrl-z_0.1.0-1_source.changes
```

`docker/build-deb.sh` builds unsigned (`-us -uc`). The container has no access
to your key, and it must not have access.

If you need a source-only `.changes`, use these commands. Launchpad accepts
the two forms, but source-only is cleaner:

```bash
cd /path/to/clean/tree
dpkg-buildpackage -S -sa
debsign -k <KEYID> ../gitrl-z_0.1.0-1_source.changes
```

## Upload

```bash
dput ppa:<owner>/gitrl-z gitrl-z_0.1.0-1_source.changes
```

`dput` is in the build container, but run this command on the host. It needs
your key and your network identity.

## After the upload

1. Monitor the build at
   `https://launchpad.net/~<owner>/+archive/ubuntu/gitrl-z/+packages`.
   A first build starts after some minutes, and it needs some more minutes.
2. **Read the build log, also when the build is successful.** The buildd is a
   cleaner environment than the container. A warning in the log is important.
3. Verify the package on a clean machine:

   ```bash
   sudo add-apt-repository ppa:<owner>/gitrl-z
   sudo apt-get update
   sudo apt-get install gitrl-z
   gitrlz --version
   ```

   `tests/packaging/test-install.sh` does the equivalent test with a local
   `.deb`. But you must do this test one time with the real PPA.

## Known problems

- **You cannot upload a rejected upload again with the same version.**
  Launchpad keeps the version, also for a failed build. Increase the version
  to `0.1.0-2` and upload again. Do not try to replace it.
- **You upload the `orig.tar.gz` one time only.** Subsequent Debian revisions
  of the same upstream version must *not* include it. If they include it,
  Launchpad rejects the upload because of a file conflict. Use `-sd` in place
  of `-sa` after the first upload.
- **`Distribution: noble` in `debian/changelog` must agree with the PPA
  series.** If an upload names a series that the PPA does not build for,
  Launchpad discards the upload and gives no message.
- **The orig tarball contains the vendored gitg subtree**, thus its size is
  approximately 280 KB. This is intentional. The package is self-contained,
  and it does not build against a `libgitg`, because Ubuntu does not supply
  `libgitg` as a development package.

## Subsequent series

0.1.0 is for noble only. It agrees with the gitg that the source came from
(`vendor/PROVENANCE`). To publish for a different series, change the
`Distribution` in `debian/changelog`, build again and upload again. **First
make sure that the series supplies gitg 44.** A different gitg version means
that the vendored source does not agree with the gitg installed on the
machine of the user. The full project depends on this agreement.
`Dockerfile.visual` asserts the version because of this.
