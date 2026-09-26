project(
  'gitrl-z', ['c', 'vala'],
  version: '0.8.0',
  license: 'GPL-2.0-or-later',
  default_options: 'buildtype=debugoptimized',
  meson_version: '>= 0.59.0',
)

application_id = 'io.github.li9i.gitrlz'
gitrlz_name = meson.project_name()
gitrlz_binary = 'gitrlz'
gitrlz_version = meson.project_version()
gitrlz_gettext = gitrlz_binary

if get_option('profile') == 'development'
  application_id = 'io.github.li9i.gitrlzDevel'
endif

gitrlz_prefix = get_option('prefix')
gitrlz_bindir = join_paths(gitrlz_prefix, get_option('bindir'))
gitrlz_datadir = join_paths(gitrlz_prefix, get_option('datadir'))
gitrlz_libdir = join_paths(gitrlz_prefix, get_option('libdir'))
gitrlz_localedir = join_paths(gitrlz_prefix, get_option('localedir'))

gitrlz_pkgdatadir = join_paths(gitrlz_datadir, gitrlz_name)
gitrlz_pkglibdir = join_paths(gitrlz_libdir, gitrlz_name)

cc = meson.get_compiler('c')
valac = meson.get_compiler('vala')

gnome = import('gnome')
i18n = import('i18n')

source_root = meson.current_source_dir()
build_root = meson.current_build_dir()

vapi_dir = join_paths(source_root, 'vapi')
po_dir = join_paths(source_root, 'po')

top_inc = include_directories('.')

glib_req_version = '>= 2.68'

gee_dep = dependency('gee-0.8')
gio_dep = dependency('gio-2.0', version: glib_req_version)
glib_dep = dependency('glib-2.0', version: glib_req_version)
gtk_dep = dependency('gtk+-3.0', version: '>= 3.22.0')
gtksourceview_dep = dependency('gtksourceview-4', version: '>= 4.0')
gdk_dep = dependency('gdk-3.0')
hdy_dep = dependency('libhandy-1', version: '>= 1.5.0')
libgit2_glib_dep = dependency('libgit2-glib-1.0', version: '>= 1.1.0')
gsettings_desktop_schemas_dep = dependency('gsettings-desktop-schemas')
libm_dep = cc.find_library('m', required: false)

config_h = configuration_data()
config_h.set_quoted('APPLICATION_ID', application_id)
config_h.set_quoted('PROFILE', get_option('profile'))
config_h.set_quoted('GETTEXT_PACKAGE', gitrlz_gettext)
config_h.set_quoted('PACKAGE_NAME', gitrlz_name)
config_h.set_quoted('PACKAGE_VERSION', gitrlz_version)
config_h.set_quoted('PACKAGE_URL', 'https://github.com/li9i/gitrl-z')
config_h.set_quoted('VERSION', gitrlz_version)
config_h.set_quoted('PLATFORM_NAME', 'unix')
config_h.set_quoted('GITG_DATADIR', gitrlz_pkgdatadir)
config_h.set_quoted('GITG_LOCALEDIR', gitrlz_localedir)
config_h.set_quoted('GITG_LIBDIR', gitrlz_pkglibdir)

configure_file(
  output: 'config.h',
  configuration: config_h,
)

add_project_arguments('-include', 'config.h', language: 'c')

warn_flags = [
  '-Wno-switch',
  '-Wno-unused-parameter',
  '-Wno-incompatible-pointer-types',
  '-Wno-discarded-qualifiers',
  '-Wno-unused-but-set-variable',
  '-Wno-deprecated-declarations',
]
add_project_arguments(cc.get_supported_arguments(warn_flags), language: 'c')

vala_flags = [
  '--target-glib', '2.68',
  '--vapidir', vapi_dir,
  '--pkg', 'config',
  '--pkg', 'gitg-platform-support',
]

subdir('src')
subdir('data')
subdir('po')
subdir('tests')

gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)

summary({
  'prefix': gitrlz_prefix,
  'binary': gitrlz_binary,
  'application id': application_id,
  'profile': get_option('profile'),
  'visual tests': get_option('visual_tests'),
}, section: 'Configuration')
