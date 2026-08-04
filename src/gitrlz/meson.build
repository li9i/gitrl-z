# gitrl-z's own code. Namespace Gitrlz; vendored gitg code keeps Gitg/GitgExt
# (spec NFR-5).
#
# Everything except main() builds into a static library, for the same reason
# the vendored subtree does: the UI tests construct the real widgets, and they
# can only link a library, not an executable.

gitrlz_lib_sources = files(
  'gitrlz-application.vala',
  'gitrlz-branch-colours.vala',
  'gitrlz-dash-view.vala',
  'gitrlz-cell-renderer-branch.vala',
  'gitrlz-cell-renderer-message.vala',
  'gitrlz-cell-renderer-operations.vala',
  'gitrlz-monitor.vala',
  'gitrlz-preferences-dialog.vala',
  'gitrlz-reflog-activity.vala',
  'gitrlz-reflog-list.vala',
  'gitrlz-reset-plan.vala',
  'gitrlz-reset-preview.vala',
  'gitrlz-reflog-annotations.vala',
  'gitrlz-reflog-filter.vala',
  'gitrlz-reflog.vala',
  'gitrlz-repository.vala',
  'gitrlz-session-start.vala',
  'gitrlz-synthetic-ref.vala',
  'gitrlz-window.vala',
)

gitrlz_resources = gnome.compile_resources(
  'gitrlz-resources',
  'resources/gitrlz.gresource.xml',
  source_dir: join_paths(meson.current_source_dir(), 'resources'),
  c_name: 'gitrlz',
)

gitrlz_deps = [
  vendor_gitg_dep,
  hdy_dep,
]

# Meson adds a linked Vala library's generated .vapi automatically, so naming
# it again with --pkg would make valac warn about a duplicate source. Only the
# extra vapis need declaring.
#
# --gresources lets valac resolve the [GtkTemplate] paths at compile time, so a
# typo in a template path or a missing [GtkChild] is a build error rather than
# a runtime one.
gitrlz_vala_flags = vala_flags + [
  '--pkg', 'gitrlz-config',
  '--pkg', 'gsettings-desktop-schemas',
  '--gresources', join_paths(meson.current_source_dir(), 'resources/gitrlz.gresource.xml'),
  '--gresourcesdir', join_paths(meson.current_source_dir(), 'resources'),
]

# Resources are compiled into the final binaries, not into this library —
# see the note in src/vendor-gitg/meson.build.
libgitrlz = static_library(
  'gitrlz',
  gitrlz_lib_sources,
  include_directories: [top_inc, vendor_gitg_inc],
  dependencies: gitrlz_deps,
  vala_args: gitrlz_vala_flags,
  vala_header: 'gitrlz.h',
  vala_vapi: 'gitrlz.vapi',
  c_args: ['-DGETTEXT_PACKAGE="@0@"'.format(gitrlz_gettext)],
  install: false,
)

gitrlz_dep = declare_dependency(
  link_with: libgitrlz,
  include_directories: [top_inc, vendor_gitg_inc, include_directories('.')],
  dependencies: gitrlz_deps,
)

# Every binary that shows a widget needs both resource bundles compiled in.
gitrlz_all_resources = gitrlz_resources + vendor_gitg_resources

# Named, because the tests spawn the real binary rather than a stand-in
# (see tests/unit/test-cli.vala).
gitrlz_exe = executable(
  gitrlz_binary,
  files('gitrlz-main.vala') + gitrlz_all_resources,
  include_directories: [top_inc, vendor_gitg_inc],
  dependencies: [gitrlz_dep],
  vala_args: vala_flags + ['--pkg', 'gitrlz-config'],
  c_args: ['-DGETTEXT_PACKAGE="@0@"'.format(gitrlz_gettext)],
  install: true,
  install_dir: gitrlz_bindir,
)
