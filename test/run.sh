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
summary
