# Desktop integration: GSettings schema, .desktop entry, AppStream metadata,
# icons and the man page (spec FR-116, FR-118).

# Icons.
#
# Installed under the application id so the .desktop entry's Icon= key
# resolves. The symbolic variant is what a dark panel or a notification uses.
#
# The application icon is a raster original, so it goes in the sized hicolor
# directories rather than scalable/. 128 is the artwork as drawn; 64 and 48
# are Lanczos downscales of it, committed rather than generated so the build
# needs no image tooling. Regenerate them if the artwork changes —
# scripts/regen-icons.sh.
foreach size : ['128', '64', '48']
  install_data(
    'icons/io.github.li9i.gitrlz-@0@.png'.format(size),
    install_dir: join_paths(
      gitrlz_datadir, 'icons', 'hicolor', '@0@x@0@'.format(size), 'apps',
    ),
    rename: '@0@.png'.format(application_id),
  )
endforeach

install_data(
  'icons/io.github.li9i.gitrlz-symbolic.svg',
  install_dir: join_paths(gitrlz_datadir, 'icons', 'hicolor', 'symbolic', 'apps'),
  rename: '@0@-symbolic.svg'.format(application_id),
)

# Desktop entry.
desktop_config = configuration_data()
desktop_config.set('icon', application_id)
desktop_config.set('binary', gitrlz_binary)

desktop_in = configure_file(
  input: 'io.github.li9i.gitrlz.desktop.in.in',
  output: 'io.github.li9i.gitrlz.desktop.in',
  configuration: desktop_config,
)

desktop_file = i18n.merge_file(
  type: 'desktop',
  input: desktop_in,
  output: '@0@.desktop'.format(application_id),
  po_dir: po_dir,
  install: true,
  install_dir: join_paths(gitrlz_datadir, 'applications'),
)

# Validating at build time means a malformed entry fails here rather than
# being noticed by lintian, or by a user whose menu has no gitrl-z in it.
desktop_file_validate = find_program('desktop-file-validate', required: false)
if desktop_file_validate.found()
  test(
    'desktop-file-validate',
    desktop_file_validate,
    args: [desktop_file],
    suite: 'data',
  )
endif

# GSettings schema.
schema_conf = configuration_data()
schema_conf.set('GETTEXT_PACKAGE', gitrlz_gettext)
schema_conf.set('APPLICATION_ID', application_id)

schema_path = '/io/github/li9i/gitrlz'
if get_option('profile') == 'development'
  schema_path = '/io/github/li9i/gitrlzDevel'
endif
schema_conf.set('SCHEMA_PATH', schema_path)

schema_file = configure_file(
  input: 'io.github.li9i.gitrlz.gschema.xml.in',
  output: '@0@.gschema.xml'.format(application_id),
  configuration: schema_conf,
  install: true,
  install_dir: join_paths(gitrlz_datadir, 'glib-2.0', 'schemas'),
)

# Compile the schemas into the build tree as well, so an uninstalled run works
# with GSETTINGS_SCHEMA_DIR pointed here (see scripts/dev.sh run). Without
# this, GLib aborts at startup on a missing schema (spec section 5).
#
# gnome.compile_schemas() is not usable here: it compiles schemas found in the
# current *source* directory, and ours is generated into the build directory
# by configure_file above. Hence the explicit target.
glib_compile_schemas = find_program('glib-compile-schemas')

gschemas_compiled = custom_target(
  'gschemas.compiled',
  input: schema_file,
  output: 'gschemas.compiled',
  command: [glib_compile_schemas, '--targetdir', '@OUTDIR@', meson.current_build_dir()],
  build_by_default: true,
)

# --strict turns a malformed schema into a build failure rather than something
# discovered when a user's settings silently fail to load.
test(
  'gschema-validate',
  glib_compile_schemas,
  args: ['--strict', '--dry-run', meson.current_build_dir()],
  suite: 'data',
  depends: gschemas_compiled,
)

# AppStream metadata.
metainfo_conf = configuration_data()
metainfo_conf.set('APPLICATION_ID', application_id)

metainfo_file = configure_file(
  input: 'io.github.li9i.gitrlz.metainfo.xml.in',
  output: '@0@.metainfo.xml'.format(application_id),
  configuration: metainfo_conf,
  install: true,
  install_dir: join_paths(gitrlz_datadir, 'metainfo'),
)

# Either tool will do; noble ships appstreamcli in the `appstream` package and
# appstream-util in `appstream-util`. Validation is skipped rather than fatal
# when neither is present, so the package build does not gain a dependency
# purely to lint its own metadata.
appstreamcli = find_program('appstreamcli', required: false)
appstream_util = find_program('appstream-util', required: false)

if appstreamcli.found()
  test(
    'metainfo-validate',
    appstreamcli,
    args: ['validate', '--no-net', '--pedantic', metainfo_file],
    suite: 'data',
  )
elif appstream_util.found()
  test(
    'metainfo-validate',
    appstream_util,
    args: ['validate-relax', '--nonet', metainfo_file],
    suite: 'data',
  )
else
  message('neither appstreamcli nor appstream-util found; metainfo not validated')
endif

# Man page.
install_man('gitrlz.1')
