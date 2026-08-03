# Patches applied to vendored gitg code

Spec NFR-5 requires a record of each modification to a file under
`src/vendor-gitg/`, with the cause. Thus a rebase onto a later gitg is a
mechanical task.

Regenerate any patch with:

    diff -u vendor/upstream/<path> src/vendor-gitg/<path>

Run this after `vendor/fetch-upstream.sh` populates `vendor/upstream/`.

Six files have patches. Everything else in `src/vendor-gitg/` is
byte-identical to gitg 44.

## gitg-repository.patch

Removes `Gitg.Repository.stage` (and its backing field) and
`init_repository()`.

**Why.** `stage` constructs a `Gitg.Stage` on demand. This class is the
staging area of gitg and its main write path. `init_repository()` creates a
repository on disk. The two are write paths, and spec NFR-4 requires that no
write path is compiled in. It is not sufficient to leave a write path
uncalled. This removal keeps `gitg-stage.vala`, `gitg-hook.vala` and their
gpgme dependency out of the closure.

Cost: none. gitrl-z does not stage and does not create repositories.

## gitg-init.patch

Two changes.

**1. Removes the `Ggit.Remote` -> `Gitg.Remote` factory registration.**

Remote operations are out of scope (spec 1.3). Thus the project does not
vendor `gitg-remote.vala`, and the registration cannot compile.

Cost: none. No part of gitrl-z reads a remote.

**2. Guards the CSS provider on a non-null `Gdk.Screen`.**

Upstream sends `Gdk.Screen.get_default()` directly to
`Gtk.StyleContext.add_provider_for_screen()`. With no display, that value is
null. GTK then fails a critical assertion, and `Gitg.init()` stops the
process. `Gitg.init()` also registers the Ggit type factory that all other
code depends on.

gitrl-z must start with no display. `gitrlz --version` and the
not-a-repository error path must both work with no display (spec FR-104). The
unit suite also runs with no display. The smoke test found this problem: the
test aborted here.

Cost: none. Without a screen, the type-factory registration is the important
part. CSS becomes meaningful only when a screen is available, and then the
code path is unchanged.

## gitg-ext-application.patch

Removes the abstract `remote_lookup` property from the `GitgExt.Application`
interface.

**Why.** Its type is `GitgExt.RemoteLookup`, declared in
`gitg-ext-remote-lookup.vala`, which the project excludes for the same cause
as above. If the property stayed, each implementor would return a type that
does not exist.

Cost: none.

## gitg-color.patch

Adds `Color.from_index(uint)`.

**Why.** Upstream gives colours in sequence only, through `next()` and
`next_index()`. This is sufficient for the graph, which colours lanes in the
order that they open. gitrl-z also colours the branch chips of the reflog
list and its operation gutter. For a given branch, these must select the
*same* colour as the graph, and not the next colour in a shared sequence
(FR-102).

The change is additive. No existing behaviour changes, and `palette` stays
private, because `from_index` wraps the index and does not expose a bound.

## gitg-lanes.patch

Changes the settings schema that `Gitg.Lanes` reads, from
`preferences.history` to `preferences.reflog`.

**Why.** gitg names that schema for its History activity. gitrl-z has no
history activity. It has a reflog activity, and its schema says so (spec
FR-116). The alternative was a `preferences.history` child in our schema that
exists only to satisfy vendored code. Then the settings would not agree with
what the application offers.

The two keys (`collapse-inactive-lanes`, `collapse-inactive-lanes-enabled`)
are present in ours with the same names and types. Thus nothing else changes.

The problem occurred at runtime, not at compile time. The application aborted
at startup with "Settings schema 'org.gitrlz.gitrlz.preferences.history' is
not installed".

## gitg-repository-list-box.patch

Removes DOAP parsing from the repository rows of the dash view.

**Why.** gitg looks for a `.doap` file in the head tree. It then renders the
short description and the language tags of that file on the row. This needs
`Ide.Doap` from the bundled `contrib/ide/` of gitg (approximately 990 lines
of C). `contrib/ide/` needs `contrib/xml-reader/`, which links **libxml2**.
The total is approximately 1500 lines of vendored C and one more link
dependency. The result is decoration on the dash rows of repositories that
contain a `.doap` file, which in practice are almost only GNOME projects.

Spec NFR-2 says to depend on no more than gitg does, and to prefer less.
Against that requirement, this is the one location where the project drops a
visible gitg behaviour and does not reproduce it.

**Visible cost.** In the repository chooser, a repository that contains a
`.doap` file shows no description line and no language tags where gitg shows
them. The branch name, the repository name and all other data on the row do
not change, and the full reflog view does not change. The users of gitrl-z
will list their own repositories, and gitg would show nothing there either,
because ordinary repositories have no `.doap` file.

This leaves `d_languages_box` bound to the template but not populated. The
compiler gives a note for this unused field. The field stays because it is a
`[GtkChild]` bound to `ui/gitg-repository-list-box-row.ui`. To remove the
field, you must also edit that file, with no improvement to the code.
