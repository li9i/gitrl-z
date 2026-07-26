# Test suites (spec section 6).
#
#   unit    GLib.Test units over pure logic and the Ggit layer. Always built.
#   ui      Xvfb-driven widget wiring tests. Always built, run under xvfb-run.
#   visual  Geometry comparison against the installed gitg, plus self-baseline
#           goldens. Gated on -Dvisual_tests=true because it needs an X
#           server, ImageMagick and gitg itself, none of which a package
#           builder has.
#
# Vendored gitg code is deliberately NOT unit-tested here: it is upstream code
# tested upstream, and testing it would create work on every rebase for no
# defect-finding benefit (spec 6.1). Its behaviour is pinned by the visual
# suite instead.

test_support_sources = files('support/gitrlz-test-repo.vala')

# gitrlz_dep is included for every suite, not just the UI one: the unit tests
# exercise Gitrlz.Reflog, Gitrlz.Repository and the annotation functions, which
# live in the same library as the widgets.
test_deps = [
  vendor_gitg_dep,
  gitrlz_dep,
  hdy_dep,
]

test_vala_flags = vala_flags + [
  '--pkg', 'gitrlz-config',
  '--pkg', 'gsettings-desktop-schemas',
]

# git is what the fixture factory drives; without it every fixture fails in a
# way that looks like a gitrl-z bug rather than a missing tool.
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
  'synthetic-ref',
]

# The CLI tests spawn the real binary, and the settings tests need the
# compiled schema, so both need pointing at the build tree.
test_env = environment()
test_env.set('GITRLZ_BINARY', gitrlz_exe.full_path())
test_env.set('GSETTINGS_SCHEMA_DIR', join_paths(meson.project_build_root(), 'data'))
# Keep every test off the developer's real dconf database.
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

# UI suite. Links gitrl-z's own library so the tests construct the real
# widgets, and runs under a private X server.
xvfb_wrapper = find_program('ui/run-xvfb.sh')

ui_tests = [
  'window',
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

  # Run through the wrapper rather than directly, so the test gets a display.
  test(
    name,
    xvfb_wrapper,
    suite: 'ui',
    protocol: 'tap',
    args: [exe, '--tap'],
    env: test_env,
    depends: [gschemas_compiled],
    # xvfb-run starts and stops a server per test, which is slower than a
    # unit test but keeps them from interfering with each other.
    timeout: 60,
  )
endforeach

# The parity audit's Vala side: dumps the data layer's view of
# a repository in the same format as tests/parity/dump-python.py, so the two
# implementations can be compared on behaviour rather than on appearance.
# Built always; it is small, and the audit is worthless if it cannot be run.
gitrlz_dump = executable(
  'gitrlz-dump',
  files('parity/gitrlz-dump.vala'),
  include_directories: [top_inc, vendor_gitg_inc],
  dependencies: test_deps,
  vala_args: test_vala_flags,
  install: false,
)

# Visual regression (spec 6.3). Off by default: it needs an X server,
# ImageMagick and the installed gitg to compare against, none of which a
# package builder has. Run it in the image built from Dockerfile.visual, which
# pins gitg 44-1build2 — deliberately NOT the build image, whose value is that
# it holds only the declared Build-Depends.
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
