#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

include_landing=false
case "${1:-}" in
  '') ;;
  --with-landing) include_landing=true ;;
  *) echo "Usage: $0 [--with-landing]" >&2; exit 2 ;;
esac

for command in flutter xcrun cwebp; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing $command. See docs/screenshots.md for setup." >&2
    exit 1
  fi
done

mkdir -p build
captures="$(mktemp -d "$PWD/build/readme-screenshots.XXXXXX")"
device=''
cleanup() {
  if [ -n "$device" ]; then
    xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
    xcrun simctl delete "$device" || true
  fi
  rm -rf "$captures"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

device="$(xcrun simctl create "Fitness Tracker README" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17 \
  com.apple.CoreSimulator.SimRuntime.iOS-27-0)"
xcrun simctl bootstatus "$device" -b
xcrun simctl status_bar "$device" override \
  --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryLevel 100

flutter test integration_test/readme_screenshots_test.dart -d "$device" \
  --dart-define="README_SCREENSHOT_DIR=$captures" \
  --dart-define="CAPTURE_LANDING_SCREENSHOTS=$include_landing"

# Finish all captures and conversions before replacing the galleries.
for screen in overview progress history log; do
  cwebp -quiet -lossless -resize 804 0 "$captures/readme-$screen.png" -o "$captures/$screen.webp"
done
if [ "$include_landing" = true ]; then
  for appearance in light dark; do
    for screen in overview progress history logging; do
      cwebp -quiet -lossless -resize 800 0 "$captures/$appearance-$screen.png" \
        -o "$captures/$screen-$appearance.webp"
    done
  done
fi

mkdir -p docs/screenshots
for screen in overview progress history log; do
  mv "$captures/$screen.webp" "docs/screenshots/$screen.webp"
done
echo "Updated Overview, Progress, History, and Log in docs/screenshots/."
if [ "$include_landing" = true ]; then
  for appearance in light dark; do
    for screen in overview progress history logging; do
      mv "$captures/$screen-$appearance.webp" "landing-page/assets/$screen-$appearance.webp"
    done
  done
  echo "Updated the light and dark landing page screenshots."
fi
