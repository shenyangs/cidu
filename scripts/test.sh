#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
source scripts/storage.sh
swiftc Sources/Core.swift Sources/Formats.swift Sources/Shandianshuo.swift Sources/Compatibility.swift Sources/MacFormats.swift Sources/WeType.swift Sources/Migration.swift Tests/ShandianshuoTests.swift Tests/MigrationTests.swift Tests/CoreTests.swift Tests/MacTests.swift "${storage_flags[@]}" -o build/core-tests
build/core-tests "$@"
