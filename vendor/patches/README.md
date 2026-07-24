# Patches applied to vendored gitg code

Spec NFR-5 requires every modification to a file under `src/vendor-gitg/`
to be recorded here with a rationale, so that rebasing onto a later gitg
is a mechanical exercise rather than archaeology.

Regenerate any patch with:

    diff -u vendor/upstream/<path> src/vendor-gitg/<path>

after `vendor/fetch-upstream.sh` has populated `vendor/upstream/`.

Six files are patched. Everything else in `src/vendor-gitg/` is byte-identical
to gitg 44.

## gitg-repository.patch

Removes `Gitg.Repository.stage` (and its backing field) and
`init_repository()`.

**Why.** `stage` lazily constructs a `Gitg.Stage`, gitg's staging-area
class and its main write path. `init_repository()` creates a repository on
disk. Both are write paths, and spec NFR-4 requires that no write path is
compiled in at all — not merely left uncalled. Severing here is what lets
`gitg-stage.vala`, `gitg-hook.vala` and their gpgme dependency stay out of
the closure entirely.

Cost: none. gitrl-z never stages and never creates repositories.

## gitg-init.patch

Two changes.

**1. Removes the `Ggit.Remote` -> `Gitg.Remote` factory registration.**

Remote operations are out of scope (spec 1.3), so `gitg-remote.vala` is not
vendored, so the registration cannot compile.

Cost: none. Nothing in gitrl-z looks up a remote.

**2. Guards the CSS provider on a non-null `Gdk.Screen`.**

Upstream passes `Gdk.Screen.get_default()` straight into
`Gtk.StyleContext.add_provider_for_screen()`. With no display that is null,
GTK fails a critical assertion, and `Gitg.init()` — which also registers the
Ggit type factory that everything else depends on — takes the process down
with it.

gitrl-z has to start without a display. `gitrlz --version` and the
not-a-repository error path are both required to work headlessly (spec
FR-104), and the unit suite runs headless too. Found by the M1 smoke test,
which aborted on exactly this.

Cost: none. The type-factory registration is the part that matters without a
screen; CSS only becomes meaningful once there is one to style, and when
there is, the code path is unchanged.

## gitg-ext-application.patch

Removes the abstract `remote_lookup` property from the `GitgExt.Application`
interface.

**Why.** Its type is `GitgExt.RemoteLookup`, declared in
`gitg-ext-remote-lookup.vala`, which is excluded for the same reason as
above. Leaving the property would force every implementor to return a type
that does not exist.

Cost: none.

## gitg-color.patch

Adds `Color.from_index(uint)`.

**Why.** Upstream only hands out colours in sequence, through `next()` and
`next_index()`, which is all the graph needs: it colours lanes in the order
they open. gitrl-z also colours the reflog list's branch chips and its
operation gutter, and those must pick the *same* colour as the graph for a
given branch rather than the next one in a shared sequence (FR-102).

Purely additive — no existing behaviour changes, and `palette` stays private,
because `from_index` wraps the index itself rather than exposing a bound.

## gitg-lanes.patch

Changes the settings schema `Gitg.Lanes` reads from `preferences.history` to
`preferences.reflog`.

**Why.** gitg names that schema for its History activity. gitrl-z has no
history activity — it has a reflog activity — and its schema says so (spec
FR-116). The alternative was adding a `preferences.history` child to our
schema that exists only to satisfy vendored code, which would make the
settings lie about what the application offers.

Both keys (`collapse-inactive-lanes`, `collapse-inactive-lanes-enabled`) are
present in ours with the same names and types, so nothing else changes.

Found at runtime, not at compile time: the application aborted at startup with
"Settings schema 'org.gitrlz.gitrlz.preferences.history' is not installed".

## gitg-repository-list-box.patch

Removes DOAP parsing from the dash view's repository rows.

**Why.** gitg looks for a `.doap` file in the head tree and renders its
short description and language tags on the row. That needs `Ide.Doap`,
which comes from gitg's bundled `contrib/ide/` (~990 lines of C), which
needs `contrib/xml-reader/`, which links **libxml2**. So roughly 1500 lines
of vendored C and an extra link dependency, in service of decorating dash
rows for repositories that ship a `.doap` file — in practice, GNOME
projects almost exclusively.

Weighed against spec NFR-2 (depend on no more than gitg does, and prefer
less), this is the one place where a visible gitg behaviour is deliberately
dropped rather than reproduced.

**Visible cost.** In the repository chooser, a repository containing a
`.doap` file shows no description line and no language tags where gitg
would show them. The branch name, repository name and everything else on
the row are unaffected, as is the entire reflog view. For the repositories
gitrl-z's users will actually list — their own — gitg would show nothing
there either, because ordinary repositories have no `.doap` file.

This leaves `d_languages_box` bound to the template but never populated,
which the compiler notes as an unused field. The field is kept rather than
removed because it is a `[GtkChild]` bound to
`ui/gitg-repository-list-box-row.ui`; removing it would mean editing that
file too, for no gain.
