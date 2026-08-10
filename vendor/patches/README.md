# Patches applied to vendored gitg code

Spec NFR-5 requires a record of each modification to a file under
`src/vendor-gitg/`, with the cause. Thus a rebase onto a later gitg is a
mechanical task.

Regenerate any patch with:

    diff -u vendor/upstream/<path> src/vendor-gitg/<path>

Run this after `vendor/fetch-upstream.sh` populates `vendor/upstream/`.

Eleven files have patches. Everything else in `src/vendor-gitg/` is
byte-identical to gitg 44.

Five of the eleven are the diff pane, and all five have the same cause. It is
written out once under `gitg-diff-view-file-renderer-text.patch` and referred
to from the other four.

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

## gitg-diff-view-file-renderer-text.patch

Two changes: the selection comes out, and the word marks go in.

**1. Removes the line selection from gitg's diff renderer: the `DiffSelectable`
interface from the class declaration, the `d_selectable`, `d_lines`,
`d_has_selection` and `d_doffset` fields, the `has_selection` property,
`clear_selection()`, the `selection` property, and the `PatchSet.Patch` that
the hunk loop built for every added and removed line.

**Why.** `PatchSet` is declared in `gitg-stage.vala`. That file is gitg's
staging area and its main write path, and `gitg-repository.patch` already
removed the property that reaches it, so that neither it, nor
`gitg-hook.vala`, nor their gpgme dependency enter the closure. Spec NFR-4
requires that no write path is compiled in. Vendoring the renderer as it
stands would put all of it back for a feature gitrl-z cannot use: a selection
is only worth making if something can stage it, and nothing here can.

Two things stay that a first reading might expect to go. `can_select` remains a
construct property of the renderer, and `handle_selection` remains one of
`Gitg.DiffView`, because both are constructor parameters: removing them would
push the patch into every call site for no gain. Both are false in gitrl-z, as
they are in gitg's own history panel.

The `added` and `removed` counters, the regions array and the source marks all
stay. The stat badge and the line tints read them, and they have nothing to do
with selection.

**Cost.** No line or hunk selection in the pane. gitg's history panel does not
offer it either: it constructs `Gitg.DiffView` with `handle_selection` false,
which is the pane gitrl-z copies. The behaviour lost is one gitg only shows in
its Commit activity, which is out of scope (spec 1.3).

**2. Marks the words that changed inside a changed line** (spec FR-178). gitg
tints the whole line and leaves the reader to find the word. This is the one
behaviour gitrl-z adds to the pane, and the only one it keeps from the
hand-written view the pane replaced.

The addition is four parts:

- `Gitg.WordMarksFunc`, a delegate: two lines in, the differing words out as
  byte offsets.
- `Gitg.WordMarks`, a holder with one static field for that delegate.
  `Gitrlz.DiffWindow` fills it in its static construct. It is a class of its own
  because the renderer is internal to this library, and the application has to
  reach the field from outside it. The delegate takes no type of the
  application's namespace, so the dependency still runs one way only: the
  vendored library knows nothing of `Gitrlz`.
- Two buffer tags, `word-added` and `word-removed`, coloured beside the source
  marks of the line tints, in a stronger shade of the same hue and following the
  theme the same way.
- A pairing pass in `add_hunk`. The first removed line of a change is paired
  with the first added line, the second with the second, and the run ends at the
  next context line. Every instance of the renderer walks every line of the
  hunk whatever its style, so a split half finds the pairs from both sides and
  marks only the lines it inserted; the lines it does not show are held with no
  buffer line. A line with no counterpart, and a pair the marker declines, keep
  their tint and take no marks.

With the field left null the renderer behaves exactly as gitg's: tints and no
marks.

## gitg-diff-view-file-renderer-text-split.patch

The same removal, in the split renderer: the `DiffSelectable` interface, the
`has_selection` property, `clear_selection()` and the `selection` property.

Upstream had already commented out the bodies of all three: the split view
reported no selection and returned an empty `PatchSet`. What goes is therefore
three members that did nothing but name a type from `gitg-stage.vala`.
`can_select` stays, for the cause given above.

## gitg-diff-view-file-renderer-textable.patch

Drops `DiffSelectable` from the interface's base list, one line.

**Why.** The interface is implemented by the two renderers above, and neither
implements `DiffSelectable` any more.

## gitg-diff-view-file.patch

Two changes.

**1. Removes `has_selection()`, `clear_selection()` and `get_selection()`,**
which walked the renderers of one file asking each for its selection.

Their return type or their cast names `DiffSelectable` or `PatchSet`. Nothing
calls them once `gitg-diff-view.patch` lands.

**2. Adds `renderer_name`, and stops the per-file switcher from ever showing.**

gitg puts a `Unif` / `Split` switcher in the header of every file. gitrl-z shows
one commit per window and switches every file at once, from one control in the
title bar (spec FR-176), so the per-file switcher would be a second way to do
the same thing in the same window.

`renderer_name` is the property that stands in for the switcher: it sets the
stack's visible child, and ignores a name the stack does not hold, which is what
leaves an image or a binary section alone. The `expanded` setter loses the two
lines that made the switcher visible.

This leaves `d_stack_switcher` bound to the template but never read, and the
compiler notes the unused field. It stays for the same cause as
`d_languages_box` above: removing it means editing
`ui/gitg-diff-view-file.ui` as well, with no improvement to the code.

## gitg-diff-view.patch

Two changes.

**1. Removes the `has_selection` property, `on_selection_changed()` and the two
calls to it, `get_selection()` and `clear_selection()`.**

The same cause as the renderer. `get_selection()` returns `PatchSet[]`, and the
rest exist to keep that property in step with the renderers.

`handle_selection` stays, as stated above, and is false.

**2. Adds `renderer_name`, the pane-wide counterpart of the property above.**

Setting it sets the property of every file the pane holds, and every file the
pane builds afterwards takes the current value. `Gitrlz.DiffWindow` drives it
from the title bar and remembers it in the `state.diff` schema.
