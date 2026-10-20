#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_build="$(mktemp -d "${TMPDIR:-/tmp}/quick-lookup-tests.XXXXXX")"
trap 'rm -rf "$test_build"' EXIT
cd "$repo_dir"
swiftc LookupSettings.swift tests/SettingsTests.swift -o "$test_build/settings-tests"
"$test_build/settings-tests"
swiftc LookupSettings.swift SettingsWindow.swift LookupPanel.swift AppTransfer.swift tests/PanelTests.swift -o "$test_build/panel-tests"
"$test_build/panel-tests"
swiftc LookupSettings.swift SettingsWindow.swift tests/SettingsEditorTests.swift -o "$test_build/editor-tests"
"$test_build/editor-tests" "$test_build/settings.png"
swiftc LookupSettings.swift SettingsWindow.swift tests/SettingsEditorBoundaries.swift -o "$test_build/editor-boundaries"
"$test_build/editor-boundaries" "$test_build/errors.png"

swiftc LookupSettings.swift SettingsWindow.swift LookupPanel.swift AppTransfer.swift tests/CompactPanelTests.swift -o "$test_build/compact-tests"
"$test_build/compact-tests"
