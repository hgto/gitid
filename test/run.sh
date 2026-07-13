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
  _sandbox; r="$(new_repo apply1)"; cd "$r" || exit
  run traversal
  assert_status "$ST" 0 apply_status
  assert_eq "$(git config user.email)" "trav@example.com" apply_email
  n="$(git config --local --get-all include.path | wc -l | tr -d ' ')"
  assert_eq "$n" "1" apply_one_include
  cd /; _cleanup
}

t_apply_idempotent_and_switch() {
  _sandbox; r="$(new_repo apply2)"; cd "$r" || exit
  run traversal; run traversal
  assert_eq "$(git config --local --get-all include.path | wc -l | tr -d ' ')" "1" apply_twice_one
  run hgto
  assert_eq "$(git config user.email)" "hg@example.com" switch_email
  assert_eq "$(git config --local --get-all include.path | wc -l | tr -d ' ')" "1" switch_one
  cd /; _cleanup
}

t_apply_strips_residue() {
  _sandbox; r="$(new_repo apply3)"; cd "$r" || exit
  # simulate legacy `cat >>` residue placed AFTER an include line (the shadowing case)
  git config --local --add include.path "$GITID_DIR/traversal.gitconfig"
  printf '[user]\n\temail = old-cat@example.com\n' >> .git/config
  run traversal
  assert_eq "$(git config user.email)" "trav@example.com" residue_stripped
  cd /; _cleanup
}

t_apply_unknown_name_errors() {
  _sandbox; r="$(new_repo apply4)"; cd "$r" || exit
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
  _sandbox; r="$(new_repo show1)"; cd "$r" || exit
  run traversal; run show
  assert_status "$ST" 0 show_status
  assert_contains "$OUT" "email:  trav@example.com" show_email
  assert_contains "$OUT" "active: traversal" show_active
  cd /; _cleanup
}

t_show_none_when_unset() {
  _sandbox; r="$(new_repo show2)"; cd "$r" || exit
  run show
  assert_contains "$OUT" "active: (none / inherited)" show_none
  cd /; _cleanup
}

t_show_warns_residue() {
  _sandbox; r="$(new_repo show3)"; cd "$r" || exit
  git config --local user.email "old-cat@example.com"
  run show
  assert_contains "$OUT" "warning" show_warn
  cd /; _cleanup
}

t_show_reports_active
t_show_none_when_unset
t_show_warns_residue

t_rules_lists_and_marks() {
  _sandbox; r="$(new_repo rules1)"; cd "$r" || exit
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
  _sandbox; r="$(new_repo check1)"; cd "$r" || exit
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

t_completion_via_symlink() {
  # Regression: invoked through a symlink (e.g. ~/bin/gitid -> .../vendor/gitid/gitid),
  # completion must resolve the link to find its bundled completion/ files.
  _sandbox
  ln -s "$GITID" "$SANDBOX/gitid-link"
  OUT="$("$SANDBOX/gitid-link" completion bash 2>&1)"; ST=$?
  assert_status "$ST" 0 comp_symlink_status
  assert_contains "$OUT" "complete -F" comp_symlink_has_complete
  cd /; _cleanup
}

t_completion_via_symlink

# Regression: expand_tilde must quote ~ in strip pattern
# Before the fix, ${1#~/} undergoes tilde expansion so ~/... paths are NOT
# expanded correctly — they become $HOME/~/... instead of $HOME/...

t_check_tilde_path_in_includeif() {
  _sandbox; r="$(new_repo check_tilde)"; cd "$r" || exit
  git remote add origin "git@github.com:InteractionLabs/x.git"
  # Use tilde form ~/ids/traversal.gitconfig in the global includeIf path
  printf '[includeIf "hasconfig:remote.*.url:*github.com[:/]InteractionLabs/**"]\n\tpath = ~/ids/traversal.gitconfig\n' > "$SANDBOX/.gitconfig"
  # Set local identity to what traversal.gitconfig provides
  git config --local user.email "trav@example.com"
  run check
  assert_status "$ST" 0 check_tilde_status
  assert_contains "$OUT" "gitid: ok" check_tilde_msg
  cd /; _cleanup
}

t_check_tilde_path_in_includeif

t_migrate_global_tilde_unconditional_include() {
  _sandbox
  # Seed global config with inline user identity AND unconditional include using ~/... path
  printf '[user]\n\temail = glob@example.com\n[include]\n\tpath = ~/ids/extra.gitconfig\n' > "$SANDBOX/.gitconfig"
  # Create the referenced file with a user identity that should be stripped
  printf '[user]\n\temail = inc@example.com\n' > "$SANDBOX/ids/extra.gitconfig"
  run migrate-global --apply
  # The include file's identity must be stripped (this is what the bug silently skips)
  result="$(git config -f "$SANDBOX/ids/extra.gitconfig" user.email 2>/dev/null || printf EMPTY)"
  assert_eq "$result" "EMPTY" mg_tilde_include_stripped
  cd /; _cleanup
}

t_migrate_global_tilde_unconditional_include

# --- guardrail + enforcement ---------------------------------------------

_isx() { if [ -x "$1" ]; then printf yes; else printf no; fi; }
_exists() { if [ -e "$1" ]; then printf yes; else printf no; fi; }
_committed() { if git commit -q "$@" 2>/dev/null; then printf yes; else printf no; fi; }
seed_rule() {
  printf '[includeIf "hasconfig:remote.*.url:*github.com[:/]InteractionLabs/**"]\n\tpath = %s/traversal.gitconfig\n' "$GITID_DIR" >> "$SANDBOX/.gitconfig"
}

t_guard_install_sets_floor_and_hook() {
  _sandbox
  run guard install
  assert_status "$ST" 0 gi_status
  assert_eq "$(git config --global --bool user.useConfigOnly)" "true" gi_useconfigonly
  assert_eq "$(git config --global core.hooksPath)" "$GITID_DIR/hooks" gi_hookspath
  assert_eq "$(_isx "$GITID_DIR/hooks/pre-commit")" "yes" gi_precommit_x
  assert_eq "$(_isx "$GITID_DIR/hooks/pre-push")" "yes" gi_prepush_x
  _cleanup
}

t_guard_status_reports() {
  _sandbox
  run guard install; run guard status
  assert_contains "$OUT" "useConfigOnly: true" gs_uco
  assert_contains "$OUT" "(gitid)" gs_owned
  assert_contains "$OUT" "dispatcher:    installed" gs_disp
  _cleanup
}

t_enforce_toggles_snippet() {
  _sandbox
  run enforce traversal
  assert_status "$ST" 0 enf_status
  assert_eq "$(git config -f "$GITID_DIR/traversal.gitconfig" --bool gitid.enforce)" "true" enf_set
  run unenforce traversal
  assert_eq "$(git config -f "$GITID_DIR/traversal.gitconfig" --bool gitid.enforce 2>/dev/null || printf unset)" "unset" enf_unset
}

t_rules_marks_enforced() {
  _sandbox; r="$(new_repo rulesenf)"; cd "$r" || exit
  git remote add origin "git@github.com:InteractionLabs/x.git"
  seed_rule
  run enforce traversal
  run rules
  assert_contains "$OUT" "[enforced]" rulesenf_mark
  cd /; _cleanup
}

t_enforced_mismatch_blocks_commit() {
  _sandbox
  seed_rule
  run guard install
  run enforce traversal
  r="$(new_repo enfblock)"; cd "$r" || exit
  git remote add origin "git@github.com:InteractionLabs/x.git"
  # wrong local identity shadows the rule's expected identity
  git config --local user.email "hg@example.com"
  git config --local user.name "Wrong"
  : > f; git add f
  assert_eq "$(_committed -m x)" "no" enfblock_blocked
  cd /; _cleanup
}

t_enforced_match_commits() {
  _sandbox
  seed_rule
  run guard install
  run enforce traversal
  r="$(new_repo enfok)"; cd "$r" || exit
  git remote add origin "git@github.com:InteractionLabs/x.git"
  : > f; git add f
  assert_eq "$(_committed -m x)" "yes" enfok_commits
  cd /; _cleanup
}

t_floor_blocks_no_identity() {
  _sandbox
  run guard install
  r="$(new_repo floor)"; cd "$r" || exit
  : > f; git add f
  # no rule, no identity -> useConfigOnly makes git refuse
  assert_eq "$(_committed -m x)" "no" floor_blocked
  cd /; _cleanup
}

t_chaining_runs_prev_and_repo_hooks() {
  _sandbox
  mkdir -p "$SANDBOX/prevhooks"
  printf '#!/bin/sh\ntouch "%s/PREV_RAN"\n' "$SANDBOX" > "$SANDBOX/prevhooks/pre-commit"
  chmod +x "$SANDBOX/prevhooks/pre-commit"
  git config --global core.hooksPath "$SANDBOX/prevhooks"
  run guard install
  assert_eq "$(git config --global gitid.prevHooksPath)" "$SANDBOX/prevhooks" chain_prev_recorded
  r="$(new_repo chain)"; cd "$r" || exit
  printf '#!/bin/sh\ntouch "%s/REPO_RAN"\n' "$SANDBOX" > .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  run traversal   # gives a valid identity (no rule matches -> enforcement passes)
  : > f; git add f
  assert_eq "$(_committed -m x)" "yes" chain_commits
  assert_eq "$(_exists "$SANDBOX/PREV_RAN")" "yes" chain_prev_ran
  assert_eq "$(_exists "$SANDBOX/REPO_RAN")" "yes" chain_repo_ran
  cd /; _cleanup
}

t_noverify_bypasses_enforcement_not_floor() {
  _sandbox
  seed_rule
  run guard install
  run enforce traversal
  r="$(new_repo noverify)"; cd "$r" || exit
  git remote add origin "git@github.com:InteractionLabs/x.git"
  git config --local user.email "hg@example.com"
  git config --local user.name "Wrong"
  : > f; git add f
  # --no-verify skips the hook; identity IS set so the floor doesn't fire
  assert_eq "$(_committed --no-verify -m x)" "yes" noverify_commits
  cd /; _cleanup
}

t_uninstall_restores_prev() {
  _sandbox
  git config --global core.hooksPath "$SANDBOX/prevhooks"
  run guard install
  run guard uninstall
  assert_eq "$(git config --global core.hooksPath)" "$SANDBOX/prevhooks" uninstall_restored
  assert_eq "$(_exists "$GITID_DIR/hooks/pre-commit")" "no" uninstall_removed
  _cleanup
}

t_precommit_no_hang_on_pipe_stdin() {
  # Regression: pre-commit must NOT read stdin. A commit run with an inherited
  # open pipe as stdin (agent/subprocess context) must not hang on `cat`.
  can_bound || return 0   # truly no way to bound runtime; skip rather than risk a hang
  _sandbox
  run guard install
  r="$(new_repo pipe)"; cd "$r" || exit
  run traversal
  : > f; git add f
  mkfifo "$SANDBOX/f.fifo"
  ( exec 9>"$SANDBOX/f.fifo"; sleep 30 ) &   # hold the fifo open well past the bound
  wpid=$!
  bounded 8 git commit -q -m x < "$SANDBOX/f.fifo"; st=$?
  kill "$wpid" 2>/dev/null || true
  wait "$wpid" 2>/dev/null || true   # reap so the shell doesn't print a "Terminated" notice
  assert_status "$st" 0 pipe_no_hang
  cd /; _cleanup
}

t_precommit_fails_closed_without_gitid() {
  # Regression: if the hook can't locate a gitid binary, block the commit
  # rather than silently skipping enforcement.
  _sandbox
  run guard install
  git config --global gitid.bin "/nonexistent/gitid"
  r="$(new_repo failclosed)"; cd "$r" || exit
  run traversal   # valid identity, so only the missing-binary path can block
  : > f; git add f
  # PATH without gitid; git itself lives in /usr/bin or /bin
  if PATH=/usr/bin:/bin git commit -q -m x 2>/dev/null; then out=yes; else out=no; fi
  assert_eq "$out" "no" failclosed_blocked
  cd /; _cleanup
}

t_guard_install_sets_floor_and_hook
t_guard_status_reports
t_precommit_no_hang_on_pipe_stdin
t_precommit_fails_closed_without_gitid
t_enforce_toggles_snippet
t_rules_marks_enforced
t_enforced_mismatch_blocks_commit
t_enforced_match_commits
t_floor_blocks_no_identity
t_chaining_runs_prev_and_repo_hooks
t_noverify_bypasses_enforcement_not_floor
t_uninstall_restores_prev

summary
