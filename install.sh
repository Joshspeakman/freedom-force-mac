#!/bin/bash
# install.sh --game-dir <Freedom Force folder> [--app-dir DIR] [--data-dir DIR] [--in-place]
# install.sh --gog-installer <setup_freedom_force_*.exe>   (GOG offline installer; needs: brew install innoextract)
# install.sh --nightly                 installs "Freedom Force Nightly.app" next to the stable app: the newest
#                                      experimental work (the repository's nightly branch, fetched from GitHub and
#                                      built in build/nightly; this checkout is left as it is). It shares the data
#                                      folder (saves and settings) with the stable app. Run it again to update.
#
# With no game option, the game folder of an app already installed is used again (reinstall or update).
#
# Builds the natively recompiled Freedom Force from your own copy of the GOG release (1.3, build 19478) and installs
# "Freedom Force Native.app" (no Wine, no Rosetta). recomp/build_ff.sh checks every file it recompiles against
# game/MANIFEST.txt. The game folder is only read: settings, saves and logs go to the data folder (default
# ~/Games/FreedomForceNative). Needs the Xcode command line tools and python3 (the recompiler installs capstone with
# pip into recomp/.venv).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GAME=""; GOG_EXE=""; APPS="$HOME/Applications"; DATA="$HOME/Games/FreedomForceNative"
NIGHTLY=""; AS_NIGHTLY=""; ARGS=()
IN_PLACE=""
while [ $# -gt 0 ]; do
  case "$1" in --in-place) IN_PLACE=1; ARGS+=("$1"); shift; continue;; esac
  case "$1" in --nightly) NIGHTLY=1; shift; continue;; --as-nightly) AS_NIGHTLY=1; shift; continue;; esac
  ARGS+=("$1"); [ $# -gt 1 ] && case "$1" in --*) case "$2" in --*) ;; *) ARGS+=("$2");; esac;; esac
  case "$1" in
    --game-dir) GAME="$2"; shift 2;; --gog-installer) GOG_EXE="$2"; shift 2;; --app-dir) APPS="$2"; shift 2;; --data-dir) DATA="$2"; shift 2;;
    *) echo "unknown option $1"; exit 1;;
  esac
done
# the stable app, or (--as-nightly, used by --nightly) the nightly one next to it
APP_NAME="Freedom Force Native"; APP_SHOWN="Freedom Force"; APP_ID=native; APP_LOG=FreedomForceNative
[ -n "$AS_NIGHTLY" ] && { APP_NAME="Freedom Force Nightly"; APP_SHOWN="Freedom Force Nightly"; APP_ID=nightly; APP_LOG=FreedomForceNightly; }
installed_game() {     # the game folder an installed app was set up with (for reinstalls and updates)
  local a L v x; for a in "Freedom Force Native" "Freedom Force Nightly"; do
    L="$APPS/$a.app/Contents/MacOS/launcher"; [ -f "$L" ] || continue
    v="$(grep -m1 '^DEF_GAME=' "$L" | cut -d= -f2-)"           # shell-quoted (printf %q)
    if [ -n "$v" ]; then eval "x=$v"; printf '%s\n' "$x"; return 0; fi
  done; return 0
}
# --nightly: fetch the nightly branch into build/nightly and let its own install.sh install the nightly app
if [ -n "$NIGHTLY" ] && [ -z "$AS_NIGHTLY" ]; then
  command -v git >/dev/null || { echo "git is needed for --nightly"; exit 1; }
  W="$HERE/build/nightly"; echo "== fetching the nightly branch"
  git -C "$HERE" fetch -q origin nightly
  git -C "$HERE" worktree prune
  if [ -e "$W/.git" ]; then git -C "$W" checkout -q -f --detach origin/nightly
  else mkdir -p "$HERE/build"; git -C "$HERE" worktree add -q -f --detach "$W" origin/nightly; fi
  echo "== nightly: $(git -C "$W" log -1 --format='%h %s')"
  [ -e "$W/recomp/.venv" ] || [ ! -d "$HERE/recomp/.venv" ] || ln -s "$HERE/recomp/.venv" "$W/recomp/.venv"   # share the tools
  if [ -z "$GAME$GOG_EXE" ]; then G="$(installed_game)"; [ -n "$G" ] && ARGS+=(--game-dir "$G"); fi
  exec "$W/install.sh" --as-nightly ${ARGS[@]+"${ARGS[@]}"}
fi
if [ -n "$GOG_EXE" ]; then       # unpack the installer into the data folder; the app reads the game from there
  [ -f "$GOG_EXE" ] || { echo "no such file: $GOG_EXE"; exit 1; }
  command -v innoextract >/dev/null || { echo "innoextract is needed for --gog-installer: brew install innoextract"; exit 1; }
  X="$DATA/gog-extract"; M=.freedom-force-gog-extract        # an earlier extract is replaced only if this script made it
  if [ -e "$X" ]; then [ -f "$X/$M" ] || { echo "$X exists and wasn't made by install.sh: move it away first"; exit 1; }; rm -rf "$X"; fi
  mkdir -p "$X"; touch "$X/$M"; echo "== unpacking $GOG_EXE"
  innoextract --gog -s -d "$X" "$GOG_EXE"
  GAME="$(dirname "$(find "$X" -maxdepth 2 -name fforce.exe -print -quit)")"
  [ -f "$GAME/fforce.exe" ] || { echo "fforce.exe not found in the installer"; exit 1; }
  # innoextract keeps what GOG's installer adds to the game folder in app/ (an empty System/startup.py among GOG's own
  # files): it goes into the data folder's copy of the game folder (the runtime reads data/game over the game folder)
  if [ -f "$X/app/System/startup.py" ] && [ ! -e "$DATA/game/System/startup.py" ]; then
    mkdir -p "$DATA/game/System"; cp "$X/app/System/startup.py" "$DATA/game/System/startup.py"
  fi
fi
[ -n "$GAME" ] || GAME="$(installed_game)"
[ -n "$GAME" ] || { echo "usage: install.sh --game-dir <Freedom Force folder> | --gog-installer <setup_freedom_force_*.exe>"; exit 1; }
GAME="$(cd "$GAME" && pwd)"
for tool in clang python3; do command -v $tool >/dev/null || { echo "$tool is missing: install the Xcode command line tools (xcode-select --install)"; exit 1; }; done
[ "$(uname -m)" = arm64 ] || { echo "the native build is for Apple Silicon Macs"; exit 1; }
[ -f "$GAME/fforce.exe" ] || { echo "no fforce.exe in $GAME"; exit 1; }
echo "== recompiling $GAME/fforce.exe and the game's DLLs (a few minutes)"
"$HERE/recomp/build_ff.sh" "$GAME"
"$HERE/recomp/tools/build_app.sh" "$HERE/recomp/work/ff" >/dev/null

A="$APPS/$APP_NAME.app"; echo "== installing $A"
if [ -e "$A" ]; then           # replaced only if it is an app this script installed
  [ -f "$A/Contents/MacOS/launcher" ] && grep -q '^# .* launcher (generated by install.sh)' "$A/Contents/MacOS/launcher" \
    || { echo "$A exists and wasn't installed by install.sh: move it away first"; exit 1; }
  rm -rf "$A"
fi
mkdir -p "$APPS" "$A/Contents/MacOS" "$A/Contents/Resources"
W="$HERE/recomp/work/ff"
cp "$W/app/FreedomForceNative" "$W/app/shaders.metal" "$W/app/dsr_snapshot.bin" "$A/Contents/MacOS/"
cp "$W/fforce.exe" "$A/Contents/Resources/fforce.exe"
mkdir -p "$DATA"
# the launch window's art, composed from this copy of the game (its main menu; GOG's banner) and the Steam store logo;
# nothing from the game is stored in this project. Without it the window draws its title.
echo "== the launch window's art, from your game"
T="$(mktemp -d)"
if python3 -I "$HERE/recomp/tools/ff_art.py" "$GAME" "$T/src" && clang -fobjc-arc -framework AppKit "$HERE/recomp/tools/ff_art.m" -o "$T/ff_art" 2>/dev/null \
   && "$T/ff_art" "$T/src" "$DATA/art"; then cp -R "$DATA/art" "$A/Contents/Resources/art"
else echo "   (no art: the launch window draws its title)"; fi
rm -rf "$T"
# The game is copied into the data folder (game-files) and the app reads it from there, so the folder it was installed
# from is no longer needed and can be deleted. On a Mac the copy is an APFS clone: it takes no extra space. Updates and
# reinstalls keep using the copy. --in-place reads the given folder instead (nothing is copied).
if [ -z "$IN_PLACE" ]; then case "$GAME/" in "$DATA"/*) ;; *)
  GF="$DATA/game-files"; echo "== copying the game from $GAME into $GF"
  mkdir -p "$DATA"; rm -rf "$GF.part"
  if [ "$(uname -s)" = Darwin ]; then cp -cRL "$GAME" "$GF.part" 2>/dev/null || { rm -rf "$GF.part"; cp -RL "$GAME" "$GF.part"; }
  else cp -RL --reflink=auto "$GAME" "$GF.part"; fi
  rm -rf "$GF"; mv "$GF.part" "$GF"
  echo "== the app reads the game from $GF: $GAME is no longer needed (delete it to free the space)"; GAME="$GF";;
esac; fi
mkdir -p "$DATA" "$APPS"; DATA="$(cd "$DATA" && pwd)"; APPS="$(cd "$APPS" && pwd)"; GAME="$(cd "$GAME" && pwd)"   # the updater keeps these, from any working directory
Q_APPS=$(printf '%q' "$APPS")
Q_GAME=$(printf '%q' "$GAME"); Q_DATA=$(printf '%q' "$DATA")      # shell-quoted: any folder name is only data
# updates from the launcher: the branch this app follows (main, or nightly for Nightly), the commit it was built from and
# the checkout it was installed from; its updater fetches the branch into a worktree there and rebuilds the app from it
U_BRANCH=main; U_DIR=stable; [ -n "$AS_NIGHTLY" ] && { U_BRANCH=nightly; U_DIR=nightly; }
U_REPO="$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"; U_REPO="${U_REPO%/.git}"
U_BUILT="$(git -C "$HERE" rev-parse HEAD 2>/dev/null || true)"
if [ -n "$U_REPO" ] && [ -n "$U_BUILT" ] && git -C "$U_REPO" remote get-url origin >/dev/null 2>&1; then
  cat > "$A/Contents/MacOS/update" <<UPDATE
#!/bin/bash
# $APP_NAME updater (generated by install.sh): "update --check" prints the newest commit of $U_BRANCH on GitHub;
# "update" fetches it into a worktree of the checkout this app was installed from and rebuilds the app from it
set -euo pipefail
REPO=$(printf '%q' "$U_REPO"); BRANCH=$U_BRANCH; W="\$REPO/build/$U_DIR"
export GIT_TERMINAL_PROMPT=0                              # never wait for a password prompt
# a private repository: the token of its owner's gh login (git's gh credential helper reads GH_TOKEN), whichever gh account is active
OWNER="\$(git -C "\$REPO" remote get-url origin | sed -E 's#.*github.com[:/]([^/]+)/.*#\1#')"
[ -n "\${GH_TOKEN:-}" ] || GH_TOKEN="\$(PATH="/opt/homebrew/bin:/usr/local/bin:\$PATH" gh auth token --user "\$OWNER" 2>/dev/null || true)"; [ -z "\$GH_TOKEN" ] || export GH_TOKEN
if [ "\${1:-}" = --check ]; then git -C "\$REPO" ls-remote origin "refs/heads/\$BRANCH" | cut -f1; exit 0; fi
echo "== fetching \$BRANCH from GitHub"
git -C "\$REPO" fetch -q origin "\$BRANCH"
git -C "\$REPO" worktree prune
if [ -e "\$W/.git" ]; then git -C "\$W" checkout -q -f --detach "origin/\$BRANCH"
else mkdir -p "\$REPO/build"; git -C "\$REPO" worktree add -q -f --detach "\$W" "origin/\$BRANCH"; fi
echo "== \$BRANCH: \$(git -C "\$W" log -1 --format='%h %s')"
[ -e "\$W/recomp/.venv" ] || [ ! -d "\$REPO/recomp/.venv" ] || ln -s "\$REPO/recomp/.venv" "\$W/recomp/.venv"   # share the tools
exec "\$W/install.sh" --game-dir $Q_GAME --data-dir $Q_DATA --app-dir $Q_APPS $( [ -n "$IN_PLACE" ] && echo "--in-place" )$( [ -n "$AS_NIGHTLY" ] && echo " --as-nightly" )
UPDATE
  chmod +x "$A/Contents/MacOS/update"
fi
cat > "$A/Contents/MacOS/launcher" <<LAUNCH
#!/bin/bash
# $APP_NAME launcher (generated by install.sh)
DEF_GAME=$Q_GAME
DEF_DATA=$Q_DATA
GAME="\${DS_GAME_DIR:-\$DEF_GAME}"; DATA="\${DS_NATIVE_DATA:-\$DEF_DATA}"
mkdir -p "\$DATA/drive_c/Users/player/Documents"
L="\$DATA/$APP_LOG.log"                                   # keep the log small: previous one as .old
[ -f "\$L" ] && [ "\$(stat -f %z "\$L")" -gt 5000000 ] && mv -f "\$L" "\$DATA/$APP_LOG.old.log"
B="\$(cd "\$(dirname "\$0")" && pwd)"
export DS_LOG_FILE="\$L"                                    # crash reports attach this app's own log
[ -x "\$B/update" ] && export DS_UPDATER="\$B/update" DS_UPDATE_BRANCH=$U_BRANCH DS_BUILT_COMMIT=$U_BUILT   # the launcher's Updates row
exec "\$B/FreedomForceNative" --exe "\$B/../Resources/fforce.exe" --game "\$GAME" --data "\$DATA" 2>>"\$L"
LAUNCH
chmod +x "$A/Contents/MacOS/launcher"
# The app's executable is the game itself (macOS recognises a game, and turns on Game Mode, only for a bundle whose
# executable is the program): it reads these settings when opened (the launcher script above is for the terminal)
P="$A/Contents/Resources/launch.plist"; plutil -create xml1 "$P"
plutil -insert game -string "$GAME" "$P"; plutil -insert data -string "$DATA" "$P"; plutil -insert log -string "$APP_LOG" "$P"
plutil -insert exe -string fforce.exe "$P"; plutil -insert branch -string "$U_BRANCH" "$P"; plutil -insert built -string "$U_BUILT" "$P"
cat > "$A/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_SHOWN</string>
  <key>CFBundleIdentifier</key><string>io.github.freedom-force-macos.$APP_ID</string>
  <key>CFBundleExecutable</key><string>FreedomForceNative</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.3</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>GCSupportsGameMode</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
I="$(mktemp -d)"
# the icon: Minuteman from the launch window's art (tools/ff_icon.m), else GOG's (his badge, 256 pixels), else the
# exe's own (32 pixels, blurry when enlarged)
GOG_ICO="$(ls "$GAME"/goggame-*.ico 2>/dev/null | head -1 || true)"
if clang -fobjc-arc -framework AppKit "$HERE/recomp/tools/ff_icon.m" -o "$I/ff_icon" 2>/dev/null \
   && "$I/ff_icon" "$DATA/art" "$I/ff1024.png" ${AS_NIGHTLY:+--nightly} 2>/dev/null; then
  sips -z 512 512 "$I/ff1024.png" --out "$I/ff512.png" >/dev/null
  sips -s format icns "$I/ff512.png" --out "$A/Contents/Resources/icon.icns" >/dev/null 2>&1 || true
elif { [ -n "$GOG_ICO" ] && sips -s format png "$GOG_ICO" --out "$I/ff.png" >/dev/null 2>&1 \
       && [ "$(sips -g pixelWidth "$I/ff.png" 2>/dev/null | awk '/pixelWidth/ {print $2}')" -ge 128 ]; } \
   || { python3 "$HERE/recomp/tools/extract_icon.py" "$GAME/fforce.exe" "$I/ff.ico" 2>/dev/null && sips -s format png "$I/ff.ico" --out "$I/ff.png" >/dev/null 2>&1; }; then
  sips -z 512 512 "$I/ff.png" --out "$I/ff512.png" >/dev/null
  if [ -n "$AS_NIGHTLY" ] && clang -fobjc-arc -framework AppKit "$HERE/recomp/tools/nightly_icon.m" -o "$I/nightly_icon" 2>/dev/null \
     && "$I/nightly_icon" "$I/ff512.png" "$I/n.png" && sips -z 512 512 "$I/n.png" --out "$I/ff512.png" >/dev/null; then :; fi   # dark tile, NIGHTLY band
  sips -s format icns "$I/ff512.png" --out "$A/Contents/Resources/icon.icns" >/dev/null 2>&1 || true
fi
rm -rf "$I"
codesign --force --deep --sign - "$A" >/dev/null 2>&1 || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$A" 2>/dev/null || true
echo "== done: $A (data in $DATA)"
