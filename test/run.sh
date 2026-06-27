#!/usr/bin/env sh
set -u
# shellcheck source=test/helpers.sh
. "$(dirname "$0")/helpers.sh"

t_help_lists_identities() {
  _sandbox
  run help
  assert_status "$ST" 0 help_status
  assert_contains "$OUT" "usage: gitid" help_usage
  assert_contains "$OUT" "traversal" help_lists_traversal
  _cleanup
}

t_help_lists_identities

t_apply_sets_include() {
  _sandbox; r="$(new_repo apply1)"; cd "$r"
  run traversal
  assert_status "$ST" 0 apply_status
  assert_eq "$(git config user.email)" "trav@example.com" apply_email
  n="$(git config --local --get-all include.path | wc -l | tr -d ' ')"
  assert_eq "$n" "1" apply_one_include
  cd /; _cleanup
}

t_apply_idempotent_and_switch() {
  _sandbox; r="$(new_repo apply2)"; cd "$r"
  run traversal; run traversal
  assert_eq "$(git config --local --get-all include.path | wc -l | tr -d ' ')" "1" apply_twice_one
  run hgto
  assert_eq "$(git config user.email)" "hg@example.com" switch_email
  assert_eq "$(git config --local --get-all include.path | wc -l | tr -d ' ')" "1" switch_one
  cd /; _cleanup
}

t_apply_strips_residue() {
  _sandbox; r="$(new_repo apply3)"; cd "$r"
  # simulate legacy `cat >>` residue placed AFTER an include line (the shadowing case)
  git config --local --add include.path "$GITID_DIR/traversal.gitconfig"
  printf '[user]\n\temail = old-cat@example.com\n' >> .git/config
  run traversal
  assert_eq "$(git config user.email)" "trav@example.com" residue_stripped
  cd /; _cleanup
}

t_apply_unknown_name_errors() {
  _sandbox; r="$(new_repo apply4)"; cd "$r"
  run nope
  assert_status "$ST" 1 unknown_status
  assert_contains "$OUT" "no identity file" unknown_msg
  cd /; _cleanup
}

t_apply_sets_include
t_apply_idempotent_and_switch
t_apply_strips_residue
t_apply_unknown_name_errors

t_show_reports_active() {
  _sandbox; r="$(new_repo show1)"; cd "$r"
  run traversal; run show
  assert_status "$ST" 0 show_status
  assert_contains "$OUT" "email:  trav@example.com" show_email
  assert_contains "$OUT" "active: traversal" show_active
  cd /; _cleanup
}

t_show_none_when_unset() {
  _sandbox; r="$(new_repo show2)"; cd "$r"
  run show
  assert_contains "$OUT" "active: (none / inherited)" show_none
  cd /; _cleanup
}

t_show_warns_residue() {
  _sandbox; r="$(new_repo show3)"; cd "$r"
  git config --local user.email "old-cat@example.com"
  run show
  assert_contains "$OUT" "warning" show_warn
  cd /; _cleanup
}

t_show_reports_active
t_show_none_when_unset
t_show_warns_residue

summary
