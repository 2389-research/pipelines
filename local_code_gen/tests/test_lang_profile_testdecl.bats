#!/usr/bin/env bats
# ABOUTME: Bats tests for the extracted cross-module-mandate helpers in
# ABOUTME: lang_profile.sh: test_decl_present (per-language test-declaration
# ABOUTME: detector) and mandate_test_names (sprint mandate extractor). These
# ABOUTME: are the hardened detectors from PR #130, moved out of the Audit node.
#
# Signatures under test (per issue #132):
#   test_decl_present <esc_name> <lang>   — runs from the project tree (cwd),
#       computing its own --include flags via lang_test_grep_includes "$lang".
#       <esc_name> is ALREADY ERE-escaped by the caller (mirrors the Audit
#       node's esc_tname). Returns 0 if the name is declared as a genuine test.
#   mandate_test_names <sprint_file>      — one name per "## Cross-Module Test
#       Mandate" bullet, sorted-unique.

setup() {
  LIB="${BATS_TEST_DIRNAME}/../lib/lang_profile.sh"
  TMPDIR="$(mktemp -d -t lang_profile_testdecl.XXXXXX)"
  export TMPDIR
  # shellcheck disable=SC1090
  . "${LIB}"
}

teardown() {
  rm -rf "${TMPDIR}"
}

# esc: mirror the Audit node's esc_tname ERE-metacharacter escaping so tests
# call test_decl_present exactly as the production call site does.
esc() {
  printf '%s' "$1" | sed 's/[][(){}.^$*+?|\\]/\\&/g'
}

# ─── test_decl_present POSITIVE (one genuine test per language) ────────────────

@test "test_decl_present: python def test_" {
  proj="${TMPDIR}/py"; mkdir -p "${proj}"
  printf 'def test_widget():\n    assert True\n' > "${proj}/test_thing.py"
  ( cd "${proj}" && test_decl_present "$(esc test_widget)" python )
}

@test "test_decl_present: go func with *testing.T receiver" {
  proj="${TMPDIR}/go"; mkdir -p "${proj}"
  printf 'package p\nimport "testing"\nfunc TestWidget(t *testing.T) {}\n' \
    > "${proj}/widget_test.go"
  ( cd "${proj}" && test_decl_present "$(esc TestWidget)" go )
}

@test "test_decl_present: node it('name')" {
  proj="${TMPDIR}/node"; mkdir -p "${proj}"
  printf "it('renders widget', () => {});\n" > "${proj}/widget.test.js"
  ( cd "${proj}" && test_decl_present "$(esc 'renders widget')" node )
}

@test "test_decl_present: node string-literal name WITH SPACES" {
  proj="${TMPDIR}/nodespace"; mkdir -p "${proj}"
  printf "test(\"adds two numbers together\", () => {});\n" \
    > "${proj}/math.test.ts"
  ( cd "${proj}" && test_decl_present "$(esc 'adds two numbers together')" node )
}

@test "test_decl_present: node name with ERE metacharacter (1+2)" {
  proj="${TMPDIR}/nodemeta"; mkdir -p "${proj}"
  printf "it('1+2', () => {});\n" > "${proj}/calc.test.js"
  ( cd "${proj}" && test_decl_present "$(esc '1+2')" node )
}

@test "test_decl_present: rust #[test]" {
  proj="${TMPDIR}/rust"; mkdir -p "${proj}/tests"
  printf '#[test]\nfn check_widget() {\n    assert!(true);\n}\n' \
    > "${proj}/tests/widget.rs"
  ( cd "${proj}" && test_decl_present "$(esc check_widget)" rust )
}

@test "test_decl_present: ruby it 'name'" {
  proj="${TMPDIR}/ruby"; mkdir -p "${proj}"
  printf "it 'returns a widget' do\nend\n" > "${proj}/widget_spec.rb"
  ( cd "${proj}" && test_decl_present "$(esc 'returns a widget')" ruby )
}

@test "test_decl_present: java-maven @Test method" {
  proj="${TMPDIR}/jmaven"; mkdir -p "${proj}"
  printf '  @Test\n  void widgetWorks() {\n  }\n' > "${proj}/WidgetTest.java"
  ( cd "${proj}" && test_decl_present "$(esc widgetWorks)" java-maven )
}

@test "test_decl_present: java-gradle @ParameterizedTest method" {
  proj="${TMPDIR}/jgradle"; mkdir -p "${proj}"
  printf '  @ParameterizedTest\n  void widgetWorks() {\n  }\n' \
    > "${proj}/WidgetTest.java"
  ( cd "${proj}" && test_decl_present "$(esc widgetWorks)" java-gradle )
}

# ─── test_decl_present BYPASS-REJECTION (same name, but NOT a real test) ───────

@test "test_decl_present: rejects go func without *testing.T" {
  proj="${TMPDIR}/gobad"; mkdir -p "${proj}"
  printf 'package p\nfunc TestWidget() {}\n' > "${proj}/widget.go"
  run sh -c "cd '${proj}' && . '${LIB}' && test_decl_present TestWidget go"
  [ "$status" -ne 0 ]
}

@test "test_decl_present: rejects rust fn not under #[test]" {
  proj="${TMPDIR}/rustbad"; mkdir -p "${proj}/tests"
  printf 'fn check_widget() {\n    let _ = 1;\n}\n' > "${proj}/tests/widget.rs"
  run sh -c "cd '${proj}' && . '${LIB}' && test_decl_present check_widget rust"
  [ "$status" -ne 0 ]
}

@test "test_decl_present: rejects rust fn sitting BELOW an unrelated #[test]" {
  proj="${TMPDIR}/rustbelow"; mkdir -p "${proj}/tests"
  printf '#[test]\nfn other() {}\n\nfn check_widget() {}\n' \
    > "${proj}/tests/widget.rs"
  run sh -c "cd '${proj}' && . '${LIB}' && test_decl_present check_widget rust"
  [ "$status" -ne 0 ]
}

@test "test_decl_present: rejects kotlin bare fun without @Test" {
  proj="${TMPDIR}/ktbad"; mkdir -p "${proj}"
  printf '  fun widgetWorks() {\n  }\n' > "${proj}/WidgetTest.kt"
  run sh -c "cd '${proj}' && . '${LIB}' && test_decl_present widgetWorks java-gradle"
  [ "$status" -ne 0 ]
}

# ─── PATH SAFETY ──────────────────────────────────────────────────────────────

@test "test_decl_present: finds a match under a directory whose path has a space" {
  proj="${TMPDIR}/spacepath"; mkdir -p "${proj}/my tests"
  printf '#[test]\nfn check_widget() {}\n' > "${proj}/my tests/widget.rs"
  ( cd "${proj}" && test_decl_present "$(esc check_widget)" rust )
}

# ─── MULTI-INCLUDE (several --include flags must split into separate flags) ────

@test "test_decl_present: node --include splits *.ts and *.js (match in .js)" {
  proj="${TMPDIR}/multinode"; mkdir -p "${proj}"
  # No .ts file; the declaration lives in a .js file. If grep_includes were
  # passed as one un-split flag, the *.js include would not apply and the
  # match would be missed.
  printf "it('multi include', () => {});\n" > "${proj}/widget.test.js"
  ( cd "${proj}" && test_decl_present "$(esc 'multi include')" node )
}

@test "test_decl_present: java --include splits *.java and *.kt (match in .kt)" {
  proj="${TMPDIR}/multijava"; mkdir -p "${proj}"
  printf '  @Test\n  fun widgetWorks() {\n  }\n' > "${proj}/WidgetTest.kt"
  ( cd "${proj}" && test_decl_present "$(esc widgetWorks)" java-gradle )
}

# ─── mandate_test_names ───────────────────────────────────────────────────────

@test "mandate_test_names: extracts one name per bullet incl. spaced names" {
  sprint="${TMPDIR}/sprint.md"
  cat > "${sprint}" <<'EOF'
## Overview
- `not_a_mandate` (edge: should be ignored, wrong section)

## Cross-Module Test Mandate
- `test_widget_alpha` (edge: orders → widget)
- `adds two numbers together` (edge: math → calc)
- `TestWidget` (edge: api → widget)

## Test contract
- `also_ignored` (edge: outside the mandate section)
EOF
  run mandate_test_names "${sprint}"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'test_widget_alpha'
  echo "$output" | grep -qx 'adds two numbers together'
  echo "$output" | grep -qx 'TestWidget'
  ! echo "$output" | grep -q 'not_a_mandate'
  ! echo "$output" | grep -q 'also_ignored'
}

@test "mandate_test_names: empty when no mandate section" {
  sprint="${TMPDIR}/nomandate.md"
  printf '## Overview\n- `x` (edge: y)\n' > "${sprint}"
  run mandate_test_names "${sprint}"
  [ -z "$output" ]
}
