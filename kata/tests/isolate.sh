# shellcheck shell=sh
# ABOUTME: Points HOME, XDG, Git, and Tracker at a fixture directory so a test never reads or writes the operator's configuration.
# ABOUTME: Sourced by every kata test after it creates its temporary root; the caller sets KATA_ISOLATE_ROOT first.
[ -n "${KATA_ISOLATE_ROOT:-}" ] || { printf 'set KATA_ISOLATE_ROOT before sourcing isolate.sh\n' >&2; exit 1; }
mkdir -p "$KATA_ISOLATE_ROOT/home" "$KATA_ISOLATE_ROOT/config/tracker" "$KATA_ISOLATE_ROOT/state"
HOME="$KATA_ISOLATE_ROOT/home"
XDG_CONFIG_HOME="$KATA_ISOLATE_ROOT/config"
XDG_STATE_HOME="$KATA_ISOLATE_ROOT/state"
GIT_CONFIG_GLOBAL="$KATA_ISOLATE_ROOT/gitconfig"
GIT_CONFIG_NOSYSTEM=1
TRACKER_NO_UPDATE_CHECK=1
export HOME XDG_CONFIG_HOME XDG_STATE_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM TRACKER_NO_UPDATE_CHECK
# No hooks path, so no operator hook runs; a fixed identity, so no test depends on the operator's.
cat >"$GIT_CONFIG_GLOBAL" <<'GITCONFIG'
[init]
defaultBranch = main
[user]
name = Kata test
email = kata-test@example.invalid
[commit]
gpgsign = false
GITCONFIG
# Tracker refuses to run even a tool-only workflow without a provider key. No test runs an agent node, so this
# value is never sent anywhere.
printf 'OPENAI_API_KEY=fixture-not-a-key\n' >"$XDG_CONFIG_HOME/tracker/.env"
