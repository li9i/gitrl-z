test_support_sources = files('support/gitrlz-test-repo.vala')

test_deps = [
  vendor_gitg_dep,
  gitrlz_dep,
  hdy_dep,
]

test_vala_flags = vala_flags + [
  '--pkg', 'gitrlz-config',
  '--pkg', 'gsettings-desktop-schemas',
]

git_prog = find_program('git', required: true)

unit_tests = [
  'smoke',
  'cli',
  'settings',
  'annotations',
  'branch-colours',
  'reflog',
  'reflog-filter',
  'repository-state',
  'reset-plan',
  'reset-preview',
  'session-start',
  'synthetic-ref',
  'word-diff',
]

test_env = environment()
test_env.set('GITRLZ_BINARY', gitrlz_exe.full_path())
test_env.set('GSETTINGS_SCHEMA_DIR', join_paths(meson.project_build_root(), 'data'))
test_env.set('GSETTINGS_BACKEND', 'memory')

foreach name : unit_tests
  exe = executable(
    'test-' + name,
    files('unit/test-' + name + '.vala') + test_support_sources + gitrlz_all_resources,
    include_directories: [top_inc, vendor_gitg_inc],
    dependencies: test_deps,
    vala_args: test_vala_flags,
    install: false,
  )

  test(
    name,
    exe,
    suite: 'unit',
    protocol: 'tap',
    args: ['--tap'],
    env: test_env,
    depends: [gitrlz_exe, gschemas_compiled],
  )
endforeach

xvfb_wrapper = find_program('ui/run-xvfb.sh')

ui_tests = [
  'window',
  'diff-pane',
  'reflog-activity',
  'reflog-limits',
]

foreach name : ui_tests
  exe = executable(
    'test-ui-' + name,
    files('ui/test-' + name + '.vala') + test_support_sources + gitrlz_all_resources,
    include_directories: [top_inc, vendor_gitg_inc],
    dependencies: test_deps,
    vala_args: test_vala_flags,
    install: false,
  )

  test(
    name,
    xvfb_wrapper,
    suite: 'ui',
    protocol: 'tap',
    args: [exe, '--tap'],
    env: test_env,
    depends: [gschemas_compiled],
    timeout: 60,
  )
endforeach

gitrlz_dump = executable(
  'gitrlz-dump',
  files('parity/gitrlz-dump.vala'),
  include_directories: [top_inc, vendor_gitg_inc],
  dependencies: test_deps,
  vala_args: test_vala_flags,
  install: false,
)

if get_option('visual_tests')
  visual_parity = find_program('visual/test-parity.sh')

  test(
    'geometry-parity',
    visual_parity,
    suite: 'visual',
    timeout: 300,
    depends: [gitrlz_exe, gschemas_compiled],
    env: test_env,
  )
endif
