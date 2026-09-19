#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-run}"
case "$MODE" in run|--build|--install|--verify|--logs|--debug) ;; *) printf 'Usage: %s [--build|--install|--verify|--logs|--debug]\n' "$0"; exit 2 ;; esac
if [[ "$MODE" != "--build" ]]; then pkill -x MouseControl 2>/dev/null || true; fi
CONFIGURATION=Debug
if [[ "$MODE" == "--install" ]]; then CONFIGURATION=Release; fi
xcodegen generate --spec project.yml
xcodebuild -project MouseControl.xcodeproj -scheme Debug -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' -derivedDataPath build/MouseControl build
APP="$PWD/build/MouseControl/Build/Products/$CONFIGURATION/Chuu.app"
if [[ "$MODE" == "--build" ]]; then printf '\nBuilt: %s\n' "$APP"; exit 0; fi
if [[ "$MODE" == "--install" ]]; then
  DEST="$HOME/Applications/Chuu.app"
  mkdir -p "$HOME/Applications"
  if [[ -e "$DEST" ]]; then
    IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DEST/Contents/Info.plist")
    [[ "$IDENTIFIER" == "moe.khan.MouseControl" ]] || { printf 'Unrelated app at install path.\n' >&2; exit 1; }
    mv "$DEST" "$DEST.previous-$(date +%Y%m%d-%H%M%S)"
  fi
  ditto "$APP" "$DEST"
  codesign --verify --deep --strict "$DEST"
  LEGACY="$HOME/Applications/Mouse Control.app"
  if [[ -d "$LEGACY" ]]; then
    LEGACY_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$LEGACY/Contents/Info.plist")
    if [[ "$LEGACY_ID" == "moe.khan.MouseControl" ]]; then
      mv "$LEGACY" "$LEGACY.previous-$(date +%Y%m%d-%H%M%S)"
    fi
  fi
  APP="$DEST"
fi
# The app pauses its event processor while the original Mos is running.
/usr/bin/open "$APP"
case "$MODE" in
  --verify) sleep 3; pgrep -x MouseControl ;;
  --logs) /usr/bin/log stream --info --style compact --predicate 'process == "MouseControl"' ;;
  --debug) lldb -n MouseControl ;;
esac
