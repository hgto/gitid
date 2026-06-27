# bash completion for gitid
_gitid() {
  local cur subs ids
  cur="${COMP_WORDS[COMP_CWORD]}"
  subs="show rules check migrate migrate-global completion help"
  ids="$(GITID_DIR="${GITID_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/git}"; for p in "$GITID_DIR"/*.gitconfig; do [ -f "$p" ] || continue; b=${p##*/}; printf '%s ' "${b%.gitconfig}"; done)"
  if [ "$COMP_CWORD" -eq 1 ]; then
    mapfile -t COMPREPLY < <(compgen -W "$subs $ids" -- "$cur")
  fi
}
complete -F _gitid gitid
