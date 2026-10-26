#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/storage.sh
swiftc Sources/Core.swift Sources/Formats.swift Sources/Compatibility.swift Sources/MacFormats.swift Sources/WeType.swift Sources/Migration.swift Sources/BaiduAutomation.swift Sources/PermissionGuide.swift Sources/Preflight.swift Sources/LiveMigration.swift Tests/PreflightTests.swift "${storage_flags[@]}" -o build/preflight-tests -framework AppKit -framework SwiftUI
build/preflight-tests
