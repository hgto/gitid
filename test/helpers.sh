# shellcheck shell=sh
# POSIX-sh test helpers. Sourced by test/run.sh.
# shellcheck disable=SC1007
GITID="${GITID:-$(CDPATH= cd "$(dirname "$0")/.." && pwd)/gitid}"
_tests=0 _fails=0

_sandbox() {
  SANDBOX="$(mktemp -d)"
  export GITID_DIR="$SANDBOX/ids"
  mkdir -p "$GITID_DIR"
  printf '[user]\n\tname = T\n\temail = trav@example.com\n[github]\n\tuser = hgto\n' > "$GITID_DIR/traversal.gitconfig"
  printf '[user]\n\tname = T\n\temail = hg@example.com\n' > "$GITID_DIR/hgto.gitconfig"
  HOME="$SANDBOX"; export HOME
  unset GIT_CONFIG_GLOBAL XDG_CONFIG_HOME 2>/dev/null || true
}
_cleanup() { [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"; }

new_repo() { d="$SANDBOX/repo_$1"; mkdir -p "$d"; git -C "$d" init -q; printf '%s' "$d"; }

run() { # captures stdout+stderr in $OUT, status in $ST
  OUT="$("$GITID" "$@" 2>&1)"
  # shellcheck disable=SC2034
  ST=$?
}

assert_eq() { _tests=$((_tests+1)); [ "$1" = "$2" ] && return 0; _fails=$((_fails+1)); printf 'FAIL %s: got [%s] want [%s]\n' "$3" "$1" "$2"; }
assert_contains() { _tests=$((_tests+1)); case "$1" in *"$2"*) return 0;; esac; _fails=$((_fails+1)); printf 'FAIL %s: [%s] missing [%s]\n' "$3" "$1" "$2"; }
assert_status() { _tests=$((_tests+1)); [ "$1" -eq "$2" ] && return 0; _fails=$((_fails+1)); printf 'FAIL %s: status %s want %s (out: %s)\n' "$3" "$1" "$2" "${OUT:-}"; }
summary() { printf '\n%s tests, %s failures\n' "$_tests" "$_fails"; [ "$_fails" -eq 0 ]; }
