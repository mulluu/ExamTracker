#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
output="${1:-$PWD/dist}"
if (( $# > 0 )); then shift; fi
mkdir -p "$output"
output="$(cd "$output" && pwd)"
app="$output/ExamTracker.app"

swift build -c release --product ExamTracker "$@"
binary_dir="$(swift build -c release --show-bin-path "$@")"

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
install -m 644 Assets/ExamTracker.icns "$app/Contents/Resources/ExamTracker.icns"
install -m 755 "$binary_dir/ExamTracker" "$app/Contents/MacOS/ExamTracker"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>ExamTracker</string>
    <key>CFBundleIdentifier</key><string>app.examtracker.mac</string>
    <key>CFBundleName</key><string>Экзамены</string>
    <key>CFBundleDisplayName</key><string>Экзамены</string>
    <key>CFBundleIconFile</key><string>ExamTracker.icns</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.3</string>
    <key>CFBundleVersion</key><string>4</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSExceptionDomains</key>
        <dict>
            <key>127.0.0.1</key>
            <dict>
                <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
            </dict>
        </dict>
    </dict>
</dict>
</plist>
PLIST
xattr -cr "$app"
codesign --force --sign - "$app"
printf '%s\n' "$app"
