# Vendored gitg 44 subtree.
#
# The file list is the compile closure of the subsystems gitrl-z builds. Do
# not add to it casually: every file here is code we carry and must
# re-reconcile whenever we rebase onto a newer gitg.
#
# These build into a *static* library, not a shared one and not straight into
# the binary. Static because nothing outside gitrl-z links them, so a private
# .so would only add an rpath, a soname and an install path to get wrong. A
# library rather than loose sources because the test executables link the same
# code, and recompiling 46 vendored files per test binary would make the suite
# unusably slow.

vendor_gitg_sources = files(
  'libgitg/gitg-assembly-info.vala',
  'libgitg/gitg-async.vala',
  'libgitg/gitg-branch-base.vala',
  'libgitg/gitg-branch.vala',
  'libgitg/gitg-cell-renderer-lanes.vala',
  'libgitg/gitg-color.vala',
  'libgitg/gitg-commit-list-view.vala',
  'libgitg/gitg-commit-model.vala',
  'libgitg/gitg-commit.vala',
  'libgitg/gitg-date.vala',
  'libgitg/gitg-font-manager.vala',
  'libgitg/gitg-init.vala',
  'libgitg/gitg-label-renderer.vala',
  'libgitg/gitg-lane.vala',
  'libgitg/gitg-lanes.vala',
  'libgitg/gitg-progress-bin.vala',
  'libgitg/gitg-ref-base.vala',
  'libgitg/gitg-ref.vala',
  'libgitg/gitg-repository-list-box.vala',
  'libgitg/gitg-repository.vala',
  'libgitg/gitg-resource.vala',
  'libgitg/gitg-theme.vala',
  'libgitg/gitg-utils.vala',
  'libgitg/gitg-when-mapped.vala',

  'libgitg-ext/gitg-ext-action.vala',
  'libgitg-ext/gitg-ext-activity.vala',
  'libgitg-ext/gitg-ext-application.vala',
  'libgitg-ext/gitg-ext-assembly-info.vala',
  'libgitg-ext/gitg-ext-command-line.vala',
  'libgitg-ext/gitg-ext-command-lines.vala',
  'libgitg-ext/gitg-ext-commit-action.vala',
  'libgitg-ext/gitg-ext-history-panel.vala',
  'libgitg-ext/gitg-ext-history.vala',
  'libgitg-ext/gitg-ext-message-bus.vala',
  'libgitg-ext/gitg-ext-message-id.vala',
  'libgitg-ext/gitg-ext-message.vala',
  'libgitg-ext/gitg-ext-notification.vala',
  'libgitg-ext/gitg-ext-notifications.vala',
  'libgitg-ext/gitg-ext-preferences.vala',
  'libgitg-ext/gitg-ext-ref-action-interface.vala',
  'libgitg-ext/gitg-ext-ref-action.vala',
  'libgitg-ext/gitg-ext-searchable.vala',
  'libgitg-ext/gitg-ext-selectable.vala',
  'libgitg-ext/gitg-ext-ui-element.vala',
  'libgitg-ext/gitg-ext-ui.vala',
  'libgitg-ext/gitg-ext-user-query.vala',
)

# C support used by gitg-utils.vala to resolve the user's home directory.
vendor_gitg_sources += files('libgitg/gitg-platform-support.c')

vendor_gitg_resources = gnome.compile_resources(
  'gitrlz-vendor-resources',
  'libgitg/resources/resources.xml',
  source_dir: join_paths(meson.current_source_dir(), 'libgitg/resources'),
  c_name: 'gitrlz_vendor',
)

vendor_gitg_deps = [
  gee_dep,
  gio_dep,
  glib_dep,
  gtk_dep,
  gdk_dep,
  libgit2_glib_dep,
  libdazzle_dep,
  gsettings_desktop_schemas_dep,
  libm_dep,
]

vendor_gitg_vala_flags = [
  '--pkg', 'gsettings-desktop-schemas',
  '--gresources', join_paths(meson.current_source_dir(), 'libgitg/resources/resources.xml'),
  '--gresourcesdir', join_paths(meson.current_source_dir(), 'libgitg/resources'),
]

# The generated C includes <libgitg/gitg-platform-support.h>, so the search
# path is this directory, not libgitg/ inside it.
vendor_gitg_inc = include_directories('.')

# The compiled resources are deliberately NOT part of this library.
#
# glib-compile-resources registers the bundle from a constructor in the
# generated object file, and nothing references that object by symbol, so a
# plain static link discards it and every [GtkTemplate] lookup then fails at
# runtime with "resource does not exist". link_whole would fix that, but
# Meson cannot link_whole one static Vala library into another. Compiling the
# resources into each final binary instead sidesteps both problems: an
# executable's own sources are never discarded.
libvendor_gitg = static_library(
  'gitrlz-vendor-gitg',
  vendor_gitg_sources,
  include_directories: [top_inc, vendor_gitg_inc],
  dependencies: vendor_gitg_deps,
  vala_args: vala_flags + vendor_gitg_vala_flags,
  vala_header: 'gitrlz-vendor-gitg.h',
  vala_vapi: 'gitrlz-vendor-gitg.vapi',
  install: false,
)

vendor_gitg_dep = declare_dependency(
  link_with: libvendor_gitg,
  include_directories: [top_inc, vendor_gitg_inc, include_directories('.')],
  dependencies: vendor_gitg_deps,
)

# Anything linking the vendored library needs valac pointed at the generated
# .vapi, which lands in the library's build directory.
vendor_gitg_vapidir = meson.current_build_dir()
