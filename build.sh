#!/bin/bash
# Builds VinylQ — the app and its desktop widgets — and installs it.
#
#   ./build.sh            release build -> /Applications/VinylQ.app
#                         (build/VinylQ.app is a shortcut to it)
#   ./build.sh debug      debug build
#   ./build.sh --run      build, then (re)launch
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
CONFIG=Release
RUN=0
for arg in "$@"; do
  case "$arg" in
    debug)   CONFIG=Debug ;;
    release) CONFIG=Release ;;
    --run)   RUN=1 ;;
  esac
done

if [ ! -f "$HERE/Packaging/AppIcon.icns" ]; then
  echo "→ drawing the icon"
  "$HERE/Packaging/make-icon.sh" >/dev/null 2>&1 || echo "  (skipped: icon renderer unavailable)"
fi

# Signing. macOS only runs desktop widgets from a properly signed extension,
# so use your Apple Development certificate — the free one Xcode makes when
# you sign in with your Apple ID. A stable signature also means macOS
# remembers "VinylQ may control Spotify / Music" across rebuilds.
# Override with VINYLQ_SIGN_IDENTITY="Apple Development: …"; without any
# certificate the build falls back to ad-hoc, and the widgets won't load.
WANT="${VINYLQ_SIGN_IDENTITY:-}"
SIGN_ARGS=(CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
SIGNED_AS="ad-hoc (widgets need an Apple Development certificate)"
pick_identity() {
  local me line hash name subject team org first=""
  me="$(id -F 2>/dev/null)"
  while IFS= read -r line; do
    hash="$(echo "$line" | awk '{print $2}')"
    name="$(echo "$line" | sed -E 's/.*"(.*)".*/\1/')"
    [ -n "$WANT" ] && [ "$name" != "$WANT" ] && continue
    subject="$(security find-certificate -c "$name" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null)"
    team="$(echo "$subject" | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p')"
    org="$(echo "$subject" | sed -nE 's/.*O ?= ?([^/,]*).*/\1/p')"
    [ -z "$team" ] && continue
    # Prefer the certificate in your own name when there's more than one.
    if [ "$org" = "$me" ] || [ -n "$WANT" ]; then
      echo "$hash $team $name"; return
    fi
    [ -z "$first" ] && first="$hash $team $name"
  done < <(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development")
  [ -n "$first" ] && echo "$first"
}
PICKED="$(pick_identity)"
if [ -n "$PICKED" ]; then
  read -r HASH TEAM NAME <<< "$PICKED"
  SIGN_ARGS=(CODE_SIGN_IDENTITY="$HASH" DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE_SPECIFIER=)
  SIGNED_AS="$NAME"
fi

echo "→ compiling ($CONFIG)"
xcodebuild -project "$HERE/VinylQ.xcodeproj" -target VinylQ -configuration "$CONFIG" \
  SYMROOT="$HERE/build/xcode" OBJROOT="$HERE/build/xcode/obj" \
  ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES \
  "${SIGN_ARGS[@]}" \
  -quiet build

BUILT="$HERE/build/xcode/$CONFIG/VinylQ.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Where VinylQ is installed. macOS only lists desktop widgets from apps that
# live in an Applications folder, and gets confused by several copies of the
# same widget, so the app goes to /Applications and build/VinylQ.app becomes a
# shortcut to it. VINYLQ_INSTALL_DIR=<folder> picks somewhere else.
INSTALL_DIR="${VINYLQ_INSTALL_DIR:-/Applications}"
if [ ! -w "$INSTALL_DIR" ]; then
  INSTALL_DIR="$HOME/Applications"
  mkdir -p "$INSTALL_DIR"
fi
APP="$INSTALL_DIR/VinylQ.app"
ours() { [ "$(defaults read "$1/Contents/Info" CFBundleIdentifier 2>/dev/null)" = "app.wax.deck" ]; }
if [ -e "$APP" ] && [ ! -L "$APP" ] && ! ours "$APP"; then
  echo "✗ $APP belongs to a different app; not replacing it."
  echo "  Set VINYLQ_INSTALL_DIR to install somewhere else."
  exit 1
fi

# A running copy — including one from before the app was called VinylQ — is
# asked to quit first (it saves the widgets' state on the way out), so the new
# build and its widgets take over cleanly.
WAS_RUNNING=0
for NAME_RUNNING in VinylQ Wax; do
  if pgrep -x "$NAME_RUNNING" >/dev/null 2>&1; then
    WAS_RUNNING=1
    pkill -TERM -x "$NAME_RUNNING" || true
  fi
done
for _ in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -x VinylQ >/dev/null 2>&1 || pgrep -x Wax >/dev/null 2>&1 || break
  sleep 0.3
done

echo "→ installing $APP"
rm -rf "$APP"
ditto "$BUILT" "$APP"

# One VinylQ as far as macOS is concerned: forget the intermediate builds, any
# old copy in build/, and the app from when it was still called Wax.
for OTHER in "$HERE"/build/xcode/*/VinylQ.app "$HERE/build/VinylQ.app" \
             "$INSTALL_DIR/Wax.app" "$HERE/build/Wax.app"; do
  [ -e "$OTHER" ] || [ -L "$OTHER" ] || continue
  [ "$OTHER" -ef "$APP" ] && continue
  for WIDGETS in "$OTHER"/Contents/PlugIns/*.appex; do
    pluginkit -r "$WIDGETS" >/dev/null 2>&1 || true
  done
  "$LSREGISTER" -u "$OTHER" >/dev/null 2>&1 || true
  case "$OTHER" in
    */Wax.app) if [ -L "$OTHER" ] || ours "$OTHER"; then rm -rf "$OTHER"; fi ;;
  esac
done
if [ "$APP" != "$HERE/build/VinylQ.app" ]; then
  rm -rf "$HERE/build/VinylQ.app"
  ln -s "$APP" "$HERE/build/VinylQ.app"
fi

# Introduce the app, and the widget extension inside it, to macOS.
"$LSREGISTER" -f -R "$APP" >/dev/null 2>&1 || true
pluginkit -a "$APP/Contents/PlugIns/VinylQWidgets.appex" >/dev/null 2>&1 || true

echo "✓ $APP"
echo "  signed: $SIGNED_AS"
if [ "$RUN" = "1" ] || [ "$WAS_RUNNING" = "1" ]; then
  open "$APP"
fi
