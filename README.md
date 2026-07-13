[![CI](https://github.com/hgto/gitid/actions/workflows/ci.yml/badge.svg)](https://github.com/hgto/gitid/actions/workflows/ci.yml)

# gitid

A minimal POSIX shell tool for managing multiple Git identities via `git include` — no config file format changes, no wrappers around `git commit`.

## How it works

`gitid` stores identity snippets as `<name>.gitconfig` files in `GITID_DIR` (default: `~/.config/git/`). Each file contains a `[user]` block:

```ini
# ~/.config/git/work.gitconfig
[user]
    name  = Thomas Hughes
    email = thomas@work.example.com
```

Applying an identity writes an `include.path` entry into the repo's local `.git/config`, so Git resolves the identity from the snippet file. Global `[includeIf]` rules (keyed on remote URL patterns) can activate identities automatically without any per-repo `gitid <name>` call.

## Install

**Clone directly:**

```sh
git clone https://github.com/hgto/gitid.git ~/tools/gitid
ln -s ~/tools/gitid/gitid /usr/local/bin/gitid
```

**As a git submodule** (pinned to a commit, shared across your dotfiles):

```sh
# inside your dotfiles repo
git submodule add https://github.com/hgto/gitid.git tools/gitid
ln -s "$PWD/tools/gitid/gitid" /usr/local/bin/gitid
```

## GITID_DIR convention

Set `GITID_DIR` to the directory holding your identity snippet files (default: `${XDG_CONFIG_HOME:-$HOME/.config}/git`).

Each identity is a file named `<name>.gitconfig` containing at minimum a `[user]` block:

```ini
[user]
    name        = Jane Dev
    email       = jane@example.com
    signingkey  = ABC123          # optional
```

You can also add `[github]` or other sections — `gitid` includes the whole file.

## Usage

### Apply an identity to the current repo

```sh
gitid work
# gitid: work applied
```

Writes `include.path = ~/.config/git/work.gitconfig` into `.git/config`. Running it again on the same identity is idempotent; switching identities replaces the previous include.

### Show the active identity

```sh
gitid show
# name:   Thomas Hughes
# email:  thomas@work.example.com
# active: work
```

Reports the resolved `user.name`, `user.email`, and which identity file is active in the local config. Warns if an inline `[user]` block is shadowing the include.

### List global includeIf rules

```sh
gitid rules
# ▸ *github.com[:/]work/**  -> work
#   *github.com[:/]oss/**   -> oss
```

Reads `[includeIf]` blocks from your global config and prints each rule with its mapped identity. A `▸` prefix marks rules that match the current repo's remote URLs.

### Check identity correctness

```sh
gitid check
# gitid: ok (thomas@work.example.com)
```

Compares the effective identity against what the matching `[includeIf]` rule expects. Exits non-zero on mismatch and suggests the fix:

```
gitid: identity mismatch: effective=personal@example.com expected=thomas@work.example.com
  fix: gitid work
```

### Fail closed instead of committing a hostname identity

By default, when no identity is set and no `[includeIf]` rule matches, Git silently invents
`you@hostname` and commits it. `gitid guard install` prevents that:

```sh
gitid guard install
# gitid: guard installed (useConfigOnly=true, hooksPath=~/.config/git/hooks)
```

It does two things:

- Sets `user.useConfigOnly=true` globally — Git then **refuses** to auto-detect an identity and
  aborts any commit where `user.name`/`user.email` can't be resolved from config. This floor holds
  even under `git commit --no-verify`.
- Installs a global `pre-commit` hook (via `core.hooksPath`) that runs the enforcement check below.
  The hook **chains** to any previous global hooks dir and each repo's own `.git/hooks`, so nothing
  you already rely on is shadowed.

```sh
gitid guard status      # show useConfigOnly, hooksPath ownership, and the chain target
gitid guard uninstall   # restore the previous hooksPath; add --all to also drop useConfigOnly
```

### Enforce a specific identity per remote

The floor guarantees *some* real identity; enforcement guarantees the *right* one. Mark an identity
enforced, and any commit whose remote matches a rule mapping to it must use it — a stale or wrong
identity is rejected:

```sh
gitid enforce work      # writes gitid.enforce = true into work.gitconfig
gitid unenforce work
```

With `guard install` active, committing in a repo whose remote matches an enforced rule while the
effective identity differs fails:

```
gitid: identity mismatch (enforced): effective=you@laptop.local expected=jane@work.example.com
  fix: gitid work
```

Enforced rules are flagged in `gitid rules` and `gitid show`.

Notes:

- `git commit --no-verify` bypasses enforcement (the floor still applies), and a repo that sets its
  own **local** `core.hooksPath` opts out of the global hook.
- The dispatcher chains the standard client-side hooks; the specialized `fsmonitor-watchman` and
  Perforce (`p4-*`) hooks are not wrapped, so a prior global one of those keeps running only if you
  invoke it yourself.
- Because the dispatcher chains each repo's own `.git/hooks`, installing the guard **re-enables**
  repo-local hooks. If you had set a global `core.hooksPath` specifically to disable untrusted
  repo-local hooks, note that gitid's chaining runs them again.

### Migrate inline identities out of repo configs

Dry-run (default — no writes):

```sh
gitid migrate ~/src
# would-clean  ~/src/project-a  ( user.email user.name )
# clean        ~/src/project-b
```

Apply:

```sh
gitid migrate --apply ~/src
# cleaned  ~/src/project-a  ( user.email user.name )
```

Recursively finds `.git` directories under the given path (`.` if omitted) and removes inline `user.*` keys from each repo's local config. Use this to clean up repos that had identities set directly rather than via includes.

### Migrate inline identities out of global config

Dry-run:

```sh
gitid migrate-global
# would-clean  /home/jane/.config/git/config  ( user.email user.name )
```

Apply:

```sh
gitid migrate-global --apply
# cleaned  /home/jane/.config/git/config  ( user.email user.name )
```

Same as `migrate` but targets the global config file (and any files referenced by unconditional `include.path` entries in it). `[includeIf]` entries and referenced snippet files are left untouched.

### Shell completion

```sh
# Bash — add to ~/.bashrc:
eval "$(gitid completion bash)"

# Zsh — add to ~/.zshrc:
eval "$(gitid completion zsh)"
```

## Worktree note

Identity is per-repo and **shared across all of a repo's worktrees**. This is intentional: `gitid <name>` writes `include.path` via `git config --local`, which edits the repo's shared `.git/config` (not the worktree-local `config` file). Every worktree of the same repo sees the same identity.

## License

MIT — see [LICENSE](LICENSE).
