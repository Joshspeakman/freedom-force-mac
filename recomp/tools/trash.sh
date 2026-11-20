# Sourced by build/check scripts: retain disposable artifacts in the user's Trash.
trash_paths() {
  local item bin
  for item in "$@"; do
    [ -e "$item" ] || [ -L "$item" ] || continue
    mkdir -p "$HOME/.Trash"
    bin=$(mktemp -d "$HOME/.Trash/freedom-force.XXXXXX") || return
    mv "$item" "$bin/" || return
  done
}
