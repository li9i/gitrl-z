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

desktop_file_validate = find_program('desktop-file-validate', required: false)
if desktop_file_validate.found()
  test(
    'desktop-file-validate',
    desktop_file_validate,
    args: [desktop_file],
    suite: 'data',
  )
endif

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

glib_compile_schemas = find_program('glib-compile-schemas')

gschemas_compiled = custom_target(
  'gschemas.compiled',
  input: schema_file,
  output: 'gschemas.compiled',
  command: [glib_compile_schemas, '--targetdir', '@OUTDIR@', meson.current_build_dir()],
  build_by_default: true,
)

test(
  'gschema-validate',
  glib_compile_schemas,
  args: ['--strict', '--dry-run', meson.current_build_dir()],
  suite: 'data',
  depends: gschemas_compiled,
)

metainfo_conf = configuration_data()
metainfo_conf.set('APPLICATION_ID', application_id)

metainfo_file = configure_file(
  input: 'io.github.li9i.gitrlz.metainfo.xml.in',
  output: '@0@.metainfo.xml'.format(application_id),
  configuration: metainfo_conf,
  install: true,
  install_dir: join_paths(gitrlz_datadir, 'metainfo'),
)

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

install_man('gitrlz.1')
