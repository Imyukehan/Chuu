#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-run}"
case "$MODE" in run|--build|--install|--install-app|--verify|--logs|--debug) ;; *) printf 'Usage: %s [--build|--install|--install-app PATH|--verify|--logs|--debug]\n' "$0"; exit 2 ;; esac
if [[ "$MODE" == "--install-app" ]]; then
  [[ $# == 2 && -d "$2" ]] || { printf 'Provide a notarized Chuu.app path.\n' >&2; exit 2; }
  APP="$(cd "$2" && pwd -P)"
  [[ "$APP" != "$HOME/Applications/Chuu.app" ]] || { printf 'Source is already installed.\n' >&2; exit 2; }
  IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")
  [[ "$IDENTIFIER" == "moe.khan.MouseControl" ]] || { printf 'Not a Chuu app.\n' >&2; exit 1; }
  codesign --verify --deep --strict "$APP"
  SIGNATURE=$(codesign -dvv "$APP" 2>&1)
  [[ "$SIGNATURE" == *'TeamIdentifier=7XZ82S4RRS'* && "$SIGNATURE" == *'Authority=Developer ID Application:'* ]] || {
    printf 'Expected Chuu Developer ID signing identity.\n' >&2; exit 1;
  }
  xcrun stapler validate "$APP"
  spctl --assess --type execute "$APP"
fi
if [[ "$MODE" != "--build" ]]; then pkill -x MouseControl 2>/dev/null || true; fi
if [[ "$MODE" != "--install-app" ]]; then
  CONFIGURATION=Debug
  if [[ "$MODE" == "--install" ]]; then CONFIGURATION=Release; fi
  xcodegen generate --spec project.yml
  xcodebuild -project Chuu.xcodeproj -scheme Chuu -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' -derivedDataPath build/Chuu build
  APP="$PWD/build/Chuu/Build/Products/$CONFIGURATION/Chuu.app"
fi
if [[ "$MODE" == "--build" ]]; then printf '\nBuilt: %s\n' "$APP"; exit 0; fi
if [[ "$MODE" == "--install" || "$MODE" == "--install-app" ]]; then
  DEST="$HOME/Applications/Chuu.app"
  BACKUP="$HOME/Library/Application Support/moe.khan.MouseControl/InstallBackup/Chuu.app"
  mkdir -p "$HOME/Applications"
  codesign --verify --deep --strict "$APP"
  # Keep one rollback copy outside Applications, never an accumulating list.
  if [[ -e "$BACKUP" ]]; then
    IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$BACKUP/Contents/Info.plist")
    [[ "$IDENTIFIER" == "moe.khan.MouseControl" ]] || { printf 'Unrelated app at backup path.\n' >&2; exit 1; }
    swift -e 'import Foundation; try FileManager.default.trashItem(at: URL(fileURLWithPath: CommandLine.arguments[1]), resultingItemURL: nil)' "$BACKUP"
  fi
  if [[ -e "$DEST" ]]; then
    IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DEST/Contents/Info.plist")
    [[ "$IDENTIFIER" == "moe.khan.MouseControl" ]] || { printf 'Unrelated app at install path.\n' >&2; exit 1; }
    mkdir -p "$(dirname "$BACKUP")"
    mv "$DEST" "$BACKUP"
  fi
  if ! ditto "$APP" "$DEST" || ! codesign --verify --deep --strict "$DEST"; then
    if [[ -e "$DEST" ]]; then
      swift -e 'import Foundation; try FileManager.default.trashItem(at: URL(fileURLWithPath: CommandLine.arguments[1]), resultingItemURL: nil)' "$DEST"
    fi
    if [[ -e "$BACKUP" ]]; then mv "$BACKUP" "$DEST"; fi
    printf 'Installation failed; previous app restored.\n' >&2
    exit 1
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
