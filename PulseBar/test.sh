#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
build_dir="${PULSEBAR_BUILD_DIR:-$project_dir/.build-local}"
mkdir -p "$build_dir"
swiftc -module-cache-path "$build_dir/test-cache" -o "$build_dir/traffic-tests" \
    "$project_dir/Sources/PulseBar/Core.swift" "$project_dir/Sources/PulseBar/BatteryRuntimeModel.swift" "$project_dir/Sources/PulseBar/PanelRefresh.swift" "$project_dir/Tests/TrafficTests.swift"
"$build_dir/traffic-tests"
