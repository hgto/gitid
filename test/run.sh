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

t_rules_lists_and_marks() {
  _sandbox; r="$(new_repo rules1)"; cd "$r"
  git remote add origin "git@github.com:InteractionLabs/x.git"
  # seed an includeIf rule into this repo's effective config via a global file
  printf '[includeIf "hasconfig:remote.*.url:*github.com[:/]InteractionLabs/**"]\n\tpath = %s/traversal.gitconfig\n' "$GITID_DIR" > "$SANDBOX/.gitconfig"
  run rules
  assert_status "$ST" 0 rules_status
  assert_contains "$OUT" "-> traversal" rules_name
  assert_contains "$OUT" "▸" rules_mark
  cd /; _cleanup
}

t_rules_lists_and_marks

t_check_mismatch_then_ok() {
  _sandbox; r="$(new_repo check1)"; cd "$r"
  git remote add origin "git@github.com:InteractionLabs/x.git"
  printf '[includeIf "hasconfig:remote.*.url:*github.com[:/]InteractionLabs/**"]\n\tpath = %s/traversal.gitconfig\n' "$GITID_DIR" > "$SANDBOX/.gitconfig"
  # force a wrong local identity
  git config --local user.email "hg@example.com"
  run check
  assert_status "$ST" 1 check_mismatch_status
  assert_contains "$OUT" "mismatch" check_mismatch_msg
  # fix it
  git config --local --unset-all user.email
  run traversal; run check
  assert_status "$ST" 0 check_ok_status
  cd /; _cleanup
}

t_check_mismatch_then_ok

t_migrate_dryrun_then_apply() {
  _sandbox
  a="$(new_repo mig_a)"; b="$(new_repo mig_b)"
  git -C "$a" config --local user.email "old@example.com"
  run migrate "$SANDBOX"
  assert_status "$ST" 0 migrate_dry_status
  assert_contains "$OUT" "would-clean" migrate_dry_marks
  assert_eq "$(git -C "$a" config --local --get user.email)" "old@example.com" migrate_dry_nowrite
  run migrate --apply "$SANDBOX"
  assert_contains "$OUT" "cleaned" migrate_apply_marks
  assert_eq "$(git -C "$a" config --local --get user.email 2>/dev/null || printf EMPTY)" "EMPTY" migrate_apply_wrote
  : "$b"
  cd /; _cleanup
}

t_migrate_dryrun_then_apply

t_migrate_global_strips_default_keeps_includeif() {
  _sandbox
  # global file has an inline default identity AND a conditional includeIf snippet ref
  printf '[user]\n\temail = global-default@example.com\n[includeIf "hasconfig:remote.*.url:*github.com[:/]ypcrts/**"]\n\tpath = %s/traversal.gitconfig\n' "$GITID_DIR" > "$SANDBOX/.gitconfig"
  run migrate-global
  assert_contains "$OUT" "would-clean" mg_dry
  assert_eq "$(git config --global --get user.email)" "global-default@example.com" mg_dry_nowrite
  run migrate-global --apply
  assert_contains "$OUT" "cleaned" mg_apply
  assert_eq "$(git config --global --get user.email 2>/dev/null || printf EMPTY)" "EMPTY" mg_removed
  # the includeIf snippet must be untouched
  assert_eq "$(git config -f "$GITID_DIR/traversal.gitconfig" user.email)" "trav@example.com" mg_snippet_intact
  cd /; _cleanup
}

t_migrate_global_strips_default_keeps_includeif

t_completion_emits_bash() {
  _sandbox
  run completion bash
  assert_status "$ST" 0 comp_status
  assert_contains "$OUT" "complete -F" comp_has_complete
  run completion fish
  assert_status "$ST" 1 comp_bad_shell
  cd /; _cleanup
}

t_completion_emits_bash

summary
