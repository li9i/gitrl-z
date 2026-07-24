# Publishing gitrl-z on Flathub

The manifest here is `io.github.li9i.gitrlz.yaml`. This is the path from that
manifest to a published app. It needs `flatpak` and the GNOME SDK, which this
project's build container does not carry, so it runs on a desktop that has
flatpak installed, not in the container.

The commands below use `org.flatpak.Builder`, the pinned builder Flathub
expects submissions to pass. The process does change over time; if a command
here drifts, flathub.org/docs is the authority.

## 1. Install the tools and runtime

```
flatpak remote-add --if-not-exists --user flathub \
  https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub \
  org.gnome.Platform//50 org.gnome.Sdk//50 org.flatpak.Builder
```

## 2. Build, install and run

Built from the pinned `v0.1.0` tag, exactly as Flathub will build it:

```
flatpak run org.flatpak.Builder --force-clean --user --install \
  --install-deps-from=flathub --repo=repo \
  build-dir flatpak/io.github.li9i.gitrlz.yaml
flatpak run io.github.li9i.gitrlz
```

Open a repository from the chooser and confirm the reflog and the reset
preview work.

To test a change before it is tagged, swap the manifest's `type: git` source
for the commented `type: dir` one, which builds from this checkout.

## 3. Lint

Flathub gates on the linter. Both must pass:

```
flatpak run --command=flatpak-builder-lint org.flatpak.Builder \
  manifest flatpak/io.github.li9i.gitrlz.yaml
flatpak run --command=flatpak-builder-lint org.flatpak.Builder repo repo
```

`repo` is the directory written by the `--repo=repo` build in step 2.

## 4. Submit

The submission is a pull request to Flathub, from your own GitHub account:

1. Fork `github.com/flathub/flathub`.
2. On the fork, create a branch named exactly `io.github.li9i.gitrlz`.
3. Add `io.github.li9i.gitrlz.yaml` at the repository root, the same manifest
   as here, with the `type: git` source pinning the tag and its commit
   (`git rev-list -n 1 v0.1.0` gives the commit; the manifest here already
   carries it).
4. Open a pull request against the `new-pr` branch of `flathub/flathub`.

A bot builds the pull request and maintainers review it. On merge, Flathub
creates the `flathub/io.github.li9i.gitrlz` repository with you as a
maintainer, and every push there publishes an update.

## Notes for the reviewer

- The only outward permission is `--filesystem=host:ro`. There is no network,
  ssh or secrets access. gitrl-z reads repositories and never writes to them,
  so the read-only host mount is the whole of its reach; saying this in the
  pull request saves a round of questions.
- The `type: git` source pins both the tag and its commit, as the linter
  requires.
- The metainfo's screenshot is fetched from the repository's `master` branch
  at build time, so it must stay at that path.
