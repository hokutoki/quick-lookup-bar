#!/bin/bash
# Build 調べものバー.app into ~/Applications
# Optional: SIGN_ID=<codesign identity> ./build.sh (keeps Accessibility permission across rebuilds)
set -e
cd "$(dirname "$0")"
APP="${APP_OUTPUT:-$HOME/Applications/調べものバー.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
swiftc -O main.swift AppTransfer.swift LookupSettings.swift LookupPanel.swift SettingsWindow.swift -o "$APP/Contents/MacOS/QuickLookupBar"
codesign --force -s "${SIGN_ID:--}" --identifier local.taka.quicklookupbar "$APP"
echo "Built $APP"
