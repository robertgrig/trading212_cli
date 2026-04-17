#!/usr/bin/env bash
# Local installer for trading212. Symlinks ~/bin/trading212 → ~/Private/trading212_cli/trading212.
# No sudo, no writes outside $HOME.

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/bin"

chmod +x "$DIR/trading212"
mkdir -p "$BIN"
ln -sf "$DIR/trading212" "$BIN/trading212"

mkdir -p "$HOME/.t212"
chmod 700 "$HOME/.t212"

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) printf '\n[!] Add %s to your PATH. Example:\n    echo '\''export PATH="$HOME/bin:$PATH"'\'' >> ~/.zshrc\n\n' "$BIN" ;;
esac

printf '[ok] trading212 installed → %s -> %s\n' "$BIN/trading212" "$DIR/trading212"
"$BIN/trading212" --version
printf '\nNext:\n  trading212 auth demo\n  trading212 account summary\n'
