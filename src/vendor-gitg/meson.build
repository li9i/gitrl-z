vendor_gitg_sources = files(
  'libgitg/gitg-assembly-info.vala',
  'libgitg/gitg-async.vala',
  'libgitg/gitg-avatar-cache.vala',
  'libgitg/gitg-branch-base.vala',
  'libgitg/gitg-branch.vala',
  'libgitg/gitg-cell-renderer-lanes.vala',
  'libgitg/gitg-color.vala',
  'libgitg/gitg-commit-list-view.vala',
  'libgitg/gitg-commit-model.vala',
  'libgitg/gitg-commit.vala',
  'libgitg/gitg-date.vala',
  'libgitg/gitg-diff-image-composite.vala',
  'libgitg/gitg-diff-image-difference.vala',
  'libgitg/gitg-diff-image-overlay.vala',
  'libgitg/gitg-diff-image-side-by-side.vala',
  'libgitg/gitg-diff-image-slider.vala',
  'libgitg/gitg-diff-image-surface-cache.vala',
  'libgitg/gitg-diff-stat.vala',
  'libgitg/gitg-diff-view-commit-details.vala',
  'libgitg/gitg-diff-view-file-info.vala',
  'libgitg/gitg-diff-view-file-renderer-binary.vala',
  'libgitg/gitg-diff-view-file-renderer-image.vala',
  'libgitg/gitg-diff-view-file-renderer-text-split.vala',
  'libgitg/gitg-diff-view-file-renderer-text.vala',
  'libgitg/gitg-diff-view-file-renderer-textable.vala',
  'libgitg/gitg-diff-view-file-renderer.vala',
  'libgitg/gitg-diff-view-file.vala',
  'libgitg/gitg-diff-view-lines-renderer.vala',
  'libgitg/gitg-diff-view-options.vala',
  'libgitg/gitg-diff-view.vala',
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
  'libgitg/gitg-textconv.vala',
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

vendor_gitg_sources += files('libgitg/gitg-platform-support.c')

vendor_gitg_sources += files('gitrlz-dazzle-compat.vala')

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
  gtksourceview_dep,
  gdk_dep,
  libgit2_glib_dep,
  gsettings_desktop_schemas_dep,
  libm_dep,
]

vendor_gitg_vala_flags = [
  '--pkg', 'gsettings-desktop-schemas',
  '--gresources', join_paths(meson.current_source_dir(), 'libgitg/resources/resources.xml'),
  '--gresourcesdir', join_paths(meson.current_source_dir(), 'libgitg/resources'),
]

vendor_gitg_inc = include_directories('.')

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

vendor_gitg_vapidir = meson.current_build_dir()
