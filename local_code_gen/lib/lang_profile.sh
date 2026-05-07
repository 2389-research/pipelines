# Language profile — single source of truth for per-language dispatch.
# Sourced by sprint_runner_qwen.dip / sprint_exec_qwen.dip / bench_local_fix_sr.dip
# (and any future dip in this directory) so adding a new language is one
# place to edit, not 7 sites × 3 dips.
#
# Functions emit to stdout; callers capture via $(...). Naming:
#   detect_*    — probe filesystem to identify project shape
#   lang_*      — given a lang token (python|go|node|rust|ruby|java-maven|java-gradle|unknown),
#                 emit the corresponding profile field
#
# To add a language `foo`:
#   1. detect_lang: add an `[ -f "$pr/foomanifest" ]` clause
#   2. lang_install_cmd / lang_test_cmd / lang_src_glob / lang_src_dirs /
#      lang_test_count_pattern / lang_test_grep_includes: add a `foo)` case
#   3. lang_failure_block: add an awk extractor for the test runner's output shape
#   4. lang_syntax_check: optionally add a per-extension fast-parse case
#
# That's it. No dip changes needed.

# ─── Detection ────────────────────────────────────────────────────────────────

# detect_proj_root: probe a few common nested-project conventions; fall back
# to "." (current dir) for flat layouts. Echoes the chosen subdir.
detect_proj_root() {
  local sub
  for sub in backend frontend server api app service core; do
    if [ -f "$sub/pyproject.toml" ] || [ -f "$sub/requirements.txt" ] \
       || [ -f "$sub/go.mod" ]      || [ -f "$sub/package.json" ] \
       || [ -f "$sub/Cargo.toml" ]  || [ -f "$sub/Gemfile" ] \
       || [ -f "$sub/pom.xml" ]     || [ -f "$sub/build.gradle" ] \
       || [ -f "$sub/build.gradle.kts" ]; then
      echo "$sub"; return
    fi
  done
  echo "."
}

# detect_lang: given a proj_root, identify the project's language by
# looking at its package manifest. Echoes one of:
#   python | go | node | rust | ruby | java-maven | java-gradle | unknown
detect_lang() {
  local pr="${1:-.}"
  if   [ -f "$pr/pyproject.toml" ] || [ -f "$pr/requirements.txt" ]; then echo "python"
  elif [ -f "$pr/go.mod" ]; then echo "go"
  elif [ -f "$pr/package.json" ]; then echo "node"
  elif [ -f "$pr/Cargo.toml" ]; then echo "rust"
  elif [ -f "$pr/Gemfile" ]; then echo "ruby"
  elif [ -f "$pr/pom.xml" ]; then echo "java-maven"
  elif [ -f "$pr/build.gradle" ] || [ -f "$pr/build.gradle.kts" ]; then echo "java-gradle"
  else echo "unknown"; fi
}

# ─── Per-language profile fields ──────────────────────────────────────────────

# lang_install: install the project's deps. Runs in the calling shell (no
# subshell, no eval) so the function has access to $WORKDIR_ABS from Setup.
# Caller must `cd` to proj_root first. Idempotent on already-installed projects.
lang_install() {
  case "$1" in
    python)
      if [ -f pyproject.toml ]; then
        uv sync --all-extras > "$WORKDIR_ABS/.ai/install.log" 2>&1 \
          || uv sync >> "$WORKDIR_ABS/.ai/install.log" 2>&1 || true
      else
        pip install -r requirements.txt > "$WORKDIR_ABS/.ai/install.log" 2>&1 || true
      fi ;;
    go)          go mod tidy 2>/dev/null || true ;;
    node)        npm install > "$WORKDIR_ABS/.ai/install.log" 2>&1 || true ;;
    rust)        cargo build --quiet 2>/dev/null || true ;;
    ruby)        bundle install > "$WORKDIR_ABS/.ai/install.log" 2>&1 || true ;;
    java-maven)  : ;;   # mvn install is slow — let RunTests do `mvn test`
    java-gradle) : ;;   # gradle is slow — let RunTests do ./gradlew test
    *)           : ;;
  esac
}

# lang_test_cmd: project's test command as a shell string. Used for two
# purposes: (a) Setup writes it to .ai/test_command.txt so CloudFix can read
# what command the project uses, (b) human-readable diagnostics. The actual
# test execution goes through lang_run_tests (no eval).
lang_test_cmd() {
  case "$1" in
    python)
      if [ -f pyproject.toml ]; then
        echo 'uv run pytest -v'
      else
        echo 'pytest -v'
      fi ;;
    go)          echo 'go test ./...' ;;
    node)        echo 'npm test' ;;
    rust)        echo 'cargo test' ;;
    ruby)
      if [ -d spec ] || grep -q "rspec" Gemfile 2>/dev/null; then
        echo 'bundle exec rspec'
      else
        echo 'bundle exec rake test'
      fi ;;
    java-maven)  echo 'mvn test -q' ;;
    java-gradle) echo './gradlew test --console=plain' ;;
    *)           echo "echo 'no test runner detected'; exit 1" ;;
  esac
}

# lang_run_tests: actually run the project's tests, redirecting both stdout
# and stderr to $1. Returns the test runner's exit code. Caller must `cd` to
# proj_root first. Mirrors lang_test_cmd's per-language dispatch but executes
# directly (no eval).
# Args: $1=output_file, $2=lang
lang_run_tests() {
  local out="$1" lang="$2"
  case "$lang" in
    python)
      if [ -f pyproject.toml ]; then
        uv run pytest -v > "$out" 2>&1
      else
        pytest -v > "$out" 2>&1
      fi ;;
    go)          go test ./... > "$out" 2>&1 ;;
    node)        npm test > "$out" 2>&1 ;;
    rust)        cargo test > "$out" 2>&1 ;;
    ruby)
      if [ -d spec ] || grep -q "rspec" Gemfile 2>/dev/null; then
        bundle exec rspec > "$out" 2>&1
      else
        bundle exec rake test > "$out" 2>&1
      fi ;;
    java-maven)  mvn test -q > "$out" 2>&1 ;;
    java-gradle) ./gradlew test --console=plain > "$out" 2>&1 ;;
    *)
      echo "no test runner detected (lang=$lang)" > "$out"
      return 1 ;;
  esac
}

# lang_src_glob: file-extension pattern for `find -name` to locate source
# files. Emits a single shell-glob string. Caller may need multiple globs
# (e.g., node has both *.ts and *.js); see lang_src_glob_extras for those.
lang_src_glob() {
  case "$1" in
    python)                 echo '*.py' ;;
    go)                     echo '*.go' ;;
    node)                   echo '*.ts' ;;  # *.js handled via lang_src_glob_extras
    rust)                   echo '*.rs' ;;
    ruby)                   echo '*.rb' ;;
    java-maven|java-gradle) echo '*.java' ;;  # *.kt via lang_src_glob_extras
    *)                      echo '*' ;;
  esac
}

# lang_src_glob_extras: additional globs for multi-extension languages.
# Returns space-separated list (or empty). Caller uses for `find ... -o -name X`.
lang_src_glob_extras() {
  case "$1" in
    node)                   echo '*.js' ;;
    java-maven|java-gradle) echo '*.kt' ;;
    *)                      echo '' ;;
  esac
}

# lang_src_dirs: subdirs of proj_root to walk when building qwen's source-bundle
# context. Space-separated.
lang_src_dirs() {
  case "$1" in
    python)                 echo "app tests" ;;
    go)                     echo "cmd internal pkg" ;;
    node)                   echo "src tests test" ;;
    rust)                   echo "src tests" ;;
    ruby)                   echo "lib spec test app" ;;
    java-maven|java-gradle) echo "src" ;;
    *)                      echo "src" ;;
  esac
}

# lang_find_prune: extra `find` predicates for skipping vendored/build dirs.
# Emits a shell-quoted argument list ready to splice (caller word-splits).
lang_find_prune() {
  case "$1" in
    python) echo "-not -path */__pycache__/* -not -path */.venv/*" ;;
    go)     echo "-not -path */vendor/*" ;;
    node)   echo "-not -path */node_modules/* -not -path */dist/*" ;;
    rust)   echo "-not -path */target/*" ;;
    ruby)   echo "-not -path */vendor/*" ;;
    java-maven|java-gradle) echo "-not -path */target/* -not -path */build/*" ;;
    *)      echo "" ;;
  esac
}

# lang_test_count_pattern: regex (POSIX ERE, ready for `grep -E`) that
# matches a line declaring a test in this language. Used by Audit to count
# tests on disk and tests in the sprint spec's "## Test contract" section.
lang_test_count_pattern() {
  case "$1" in
    python)                 echo '^(async )?def test_' ;;
    go)                     echo '^func Test' ;;
    node)                   echo '^[[:space:]]*(describe|it|test)\(' ;;
    rust)                   echo '^#\[(tokio::)?test\]' ;;
    ruby)                   echo '^[[:space:]]*(describe|it|context|def test_)' ;;
    java-maven|java-gradle) echo '^[[:space:]]*@(Test|ParameterizedTest|RepeatedTest)' ;;
    *)                      echo 'NEVER_MATCHES_ANYTHING' ;;
  esac
}

# lang_test_grep_includes: file-extension --include flags for `grep -r`,
# used by Audit's on-disk test count. Space-separated.
lang_test_grep_includes() {
  case "$1" in
    python)                 echo '--include=*.py' ;;
    go)                     echo '--include=*.go' ;;
    node)                   echo '--include=*.ts --include=*.js' ;;
    rust)                   echo '--include=*.rs' ;;
    ruby)                   echo '--include=*.rb' ;;
    java-maven|java-gradle) echo '--include=*.java --include=*.kt' ;;
    *)                      echo '' ;;
  esac
}

# lang_failure_block: extract the "interesting failure detail" subsection from
# the test runner's output. Format is genuinely different per runner, so this
# is the most language-specific function. Echoes the extracted block to stdout.
# Args: $1=lang, $2=path-to-test-output-file
lang_failure_block() {
  local lang="$1" out="$2"
  case "$lang" in
    python) awk '/^=+ FAILURES =+$/{f=1;next} f && /^=+ short test summary/{exit} f' "$out" ;;
    go)     awk '/^FAIL$/{exit} /^=== RUN|^--- FAIL/{f=1} f' "$out" ;;
    rust)   awk '/^failures:$/{f=1} /^test result:/{exit} f' "$out" ;;
    ruby)   awk '/^Failures:$/{f=1;next} f && /^Finished in/{exit} f' "$out" ;;
    *)      cat "$out" ;;
  esac
}

# lang_failure_summary: one-line-per-failure summary matching the runner's
# convention (e.g. `FAILED tests/test_x.py::test_y`).
# Args: $1=lang, $2=path-to-test-output-file
lang_failure_summary() {
  local lang="$1" out="$2"
  case "$lang" in
    python) grep -E "^(FAILED|ERROR) " "$out" 2>/dev/null || true ;;
    go)     grep -E "^--- FAIL:" "$out" 2>/dev/null || true ;;
    rust)   grep -E "^test .* FAILED" "$out" 2>/dev/null || true ;;
    ruby)   grep -E "^[[:space:]]*[0-9]+\) " "$out" 2>/dev/null || true ;;
    node)   grep -E "✗|FAIL|fail" "$out" 2>/dev/null | head -20 || true ;;
    *)      head -40 "$out" 2>/dev/null || true ;;
  esac
}

# lang_failing_test_files: extract paths of test files that failed, one per
# line, sorted-unique. Used by LocalFix to include them in qwen's context bundle.
# Args: $1=lang, $2=path-to-test-output-file
lang_failing_test_files() {
  local lang="$1" out="$2"
  case "$lang" in
    python)
      { grep -oE 'FAILED [^ ]+\.py' "$out" 2>/dev/null | awk '{print $2}'
        grep -oE 'ERROR [^ ]+\.py'  "$out" 2>/dev/null | awk '{print $2}'
      } | awk -F: '{print $1}' | sort -u ;;
    go)
      # `--- FAIL: TestX (0.00s)` doesn't include filenames in default output;
      # falling back to grepping for any *_test.go reference in errors.
      grep -oE '[A-Za-z0-9_./-]+_test\.go' "$out" 2>/dev/null | sort -u ;;
    rust)
      # cargo's failure lines reference `tests/foo.rs:NN` style paths.
      grep -oE 'tests/[A-Za-z0-9_./-]+\.rs' "$out" 2>/dev/null | sort -u ;;
    *)  ;;  # other langs: rely on FAIL_BLOCKS containing filenames
  esac
}

# lang_syntax_check: per-file syntax pre-check before writing. Echoes any
# error messages to stdout (caller treats non-empty as failure). Skips silently
# for languages where a quick check requires project context (Java/Kotlin/.NET).
# Args: $1=path-to-file
lang_syntax_check() {
  local fp="$1"
  case "$fp" in
    *.go)      gofmt -e "$fp" 2>&1 >/dev/null | head -5 ;;
    *.py)      python3 -m py_compile "$fp" 2>&1 | head -5 ;;
    *.ts|*.js) node -c "$fp" 2>&1 | head -5 ;;
    *.rs)      rustc --edition 2021 --emit=metadata -o /dev/null "$fp" 2>&1 | head -5 ;;
    *.rb)      ruby -c "$fp" 2>&1 | head -5 ;;
    # Java/Kotlin/.NET — quick parse needs classpath; defer to RunTests.
  esac
}

# ─── Self-test (only runs if invoked directly, not when sourced) ──────────────

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  echo "lang_profile.sh self-test:"
  echo "  detect_proj_root: $(detect_proj_root)"
  pr=$(detect_proj_root); lang=$(detect_lang "$pr")
  echo "  detect_lang ($pr): $lang"
  echo "  lang_test_cmd: $(lang_test_cmd "$lang")"
  echo "  lang_src_dirs: $(lang_src_dirs "$lang")"
  echo "  lang_test_count_pattern: $(lang_test_count_pattern "$lang")"
fi
