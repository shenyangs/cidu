#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/storage.sh
swiftc Sources/Core.swift Sources/Formats.swift Sources/MacFormats.swift Sources/WeType.swift Sources/Compatibility.swift Sources/Migration.swift Tests/NativeValidation.swift "${storage_flags[@]}" -o build/native-tests
build/native-tests "$PWD/build/词渡.app/Contents/MacOS/EngineProbe"
