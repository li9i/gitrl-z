# `gitrl-z`

> A tool to help you undo the predicament you found yourself in in `git`

`gitrl-z` shows the reflog the way `gitg` shows history, and previews what a `git reset --hard` would do before you run it. It's pronounced git-ROL-ZED (/ɡɪtˈrəʊlzɛd/), after ctrl-z said aloud: control zed.

The reflog remembers where every branch has been, including commits that a rebase rewrote or a reset abandoned. `gitrl-z` lists it, and when you click an entry it shows your whole history with that entry's branch label moved to where a reset would put it, so you can see where the branch would land without losing sight of what it would leave behind. **Nothing is ever written to the repository.**

![gitrl-z showing a reflog with a rebase run and a reset preview](docs/screenshots/reflog-activity.png)

It is built from `gitg`: written in gitg's own language (Vala), against the same libraries, and the commit graph in the preview is gitg's own renderer.

## Installing

From the PPA (Ubuntu 24.04 noble):

```bash
sudo add-apt-repository ppa:<owner>/gitrl-z
sudo apt-get install gitrl-z
```

The package is `gitrl-z`; the command is `gitrlz`.

Or download the AppImage from the [releases page](https://github.com/li9i/gitrl-z/releases), a single file that needs no install. Make it executable and run it:

```bash
chmod +x gitrl-z-*-x86_64.AppImage
./gitrl-z-*-x86_64.AppImage
```

If your machine has no FUSE, run it unpacked instead, which needs nothing extra:

```bash
./gitrl-z-*-x86_64.AppImage --appimage-extract-and-run
```

## Running

```bash
# cd to a repo ...
gitrlz

# ... or provide the repo as an argument
gitrlz /path/to/repo
```

Run outside a repository, `gitrlz` opens a chooser listing recently used ones.

`F5` reloads. `Ctrl+Q` quits. The window follows the repository as it changes, so a commit or rebase in another terminal shows up without you touching anything.

## Licence

GPL-2.0-or-later, inherited from gitg. See `COPYING`, and `debian/copyright` for the per-file breakdown crediting the gitg authors.
