#compdef gitid
_gitid() {
  local -a subs ids
  subs=(show rules check migrate migrate-global completion help)
  local d="${GITID_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/git}" p b
  for p in "$d"/*.gitconfig(N); do b=${p:t}; ids+=("${b%.gitconfig}"); done
  _describe 'gitid' subs -- ids
}
compdef _gitid gitid
