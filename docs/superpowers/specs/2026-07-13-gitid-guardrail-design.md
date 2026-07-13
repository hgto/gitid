# gitid guardrail + per-identity enforcement

## Problem

gitid maps remote URLs to identities via global `[includeIf "hasconfig:remote.*.url:…"]` rules.
When an agent commits in a repo whose remote matches **no** rule — or that has no remote yet —
git has no `user.email`, so it silently fabricates `you@hostname` and commits it. Those bad
identities leak into history.

## Goal

Fail closed. If nothing supplies a real identity, the commit must error rather than invent one.
Additionally, a rule may be marked *enforced*: if a repo's remote matches an enforced rule but
the effective identity is the wrong one, the commit must also fail.

## Design

Two layers with distinct mechanisms:

### Layer 1 — Floor: `user.useConfigOnly=true` (native git)

gitid sets this global flag. Git then refuses to auto-detect an identity from hostname/GECOS and
aborts any commit where `user.name`/`user.email` can't be resolved from config. This is the true
backstop: it also fires under `git commit --no-verify`, and needs no hook. A matching `includeIf`
rule or an explicit `gitid <name>` satisfies it.

### Layer 2 — Enforcement: opt-in per identity, via a global pre-commit hook

The floor can't catch a *wrong* identity that is nonetheless set. Enforcement does. An identity is
marked enforced by writing `gitid.enforce = true` into its `<name>.gitconfig` snippet
(`gitid enforce <name>` / `gitid unenforce <name>`). At commit time, if the repo's remote matches a
rule whose identity is enforced and the effective email ≠ the rule's expected email, the commit is
blocked.

Enforcement requires intercepting the commit, which git config alone cannot do, so it runs from a
global `pre-commit` hook. `--no-verify` bypasses this layer (intentional, explicit override); the
floor still holds.

### Hook management: gitid owns `core.hooksPath`, chains to everything

A global `core.hooksPath` shadows both any prior global hooks dir and every repo's `.git/hooks`, for
*all* hook types. To avoid silently dropping anything, `gitid guard install`:

1. Sets `user.useConfigOnly=true`.
2. Records the prior `core.hooksPath` in `gitid.prevHooksPath` (only if it isn't already gitid's dir).
3. Records the resolved absolute gitid path in `gitid.bin` (symlink-resolved).
4. Points `core.hooksPath` at `$GITID_DIR/hooks`.
5. Writes one static **dispatcher** script there and symlinks it under the full client-side hook
   name set (`pre-commit`, `commit-msg`, `pre-push`, `post-checkout`, …).

The dispatcher (static; reads all config at runtime, so nothing is baked/interpolated):

1. Captures stdin once to a temp file if present, to replay to multiple chained targets (`pre-push`).
2. If invoked as `pre-commit`: runs `gitid guard check`; non-zero → abort.
3. Chains the same-named hook from (a) `gitid.prevHooksPath` and (b) the repo's real
   `.git/hooks` (`git rev-parse --absolute-git-dir`/hooks — never `core.hooksPath`, so no recursion),
   forwarding `"$@"` and the captured stdin; any non-zero target propagates.

`gitid guard check` is the enforcement policy: in a repo, resolve the matched rule's identity via the
existing `expected_identity_file()`; if that snippet has `gitid.enforce = true` and the effective
email differs, exit non-zero; otherwise pass (no rule, or rule not enforced → pass, floor covers
no-identity). `gitid check` is unchanged (human/CI diagnostics).

## Commands

- `gitid guard install` — idempotent; safe to re-run.
- `gitid guard uninstall [--all]` — restore prior `core.hooksPath` (or unset), remove dispatchers and
  `gitid.prevHooksPath`/`gitid.bin`. Leaves `useConfigOnly` unless `--all`.
- `gitid guard status` — report `useConfigOnly`, hooksPath ownership, dispatcher presence, chain target.
- `gitid guard check` — used by the hook (enforced-mismatch → non-zero).
- `gitid enforce <name>` / `gitid unenforce <name>` — toggle `gitid.enforce` in the snippet.
- `gitid rules` / `gitid show` — gain an `[enforced]` marker.

## Enforce flag storage

`gitid.enforce = true` inside `<name>.gitconfig`. Native git format, no new store; resolves through
the existing rule→snippet path. Enforcement travels with the identity (per-identity, not per-glob;
acceptable — enforcing two rules that map to the same identity differently is not a real need).

## Testing (`test/run.sh`)

Sandboxed HOME/XDG (existing `_sandbox`). Cases:

- install sets `useConfigOnly=true` + `core.hooksPath` + an executable dispatcher.
- `enforce`/`unenforce` toggle the snippet key.
- `rules` shows `[enforced]` for an enforced rule.
- enforced mismatch blocks the commit; enforced match commits.
- no identity + no rule → commit fails via the floor.
- chaining: a prior global hook and a repo-local hook both run (marker files).
- `--no-verify` bypasses enforcement but a set identity still commits (floor not triggered).
- uninstall restores the prior hooksPath and removes the dispatcher.

## Edge cases (documented in README)

- `--no-verify` bypasses enforcement; the floor cannot be bypassed.
- A repo that sets its own **local** `core.hooksPath` opts out of gitid's global hook.
- `pre-push` stdin is captured and replayed so chained hooks each receive it.
