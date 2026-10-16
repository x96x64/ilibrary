#!/bin/sh
set -eu
# The Command Line Tools omit the discovery paths of Swift Testing in Swift Build.
# Derive the paths from the selected toolchain; do not embed a developer's home directory.
if command -v xcode-select >/dev/null 2>&1; then
    developer_dir=$(xcode-select -p)
    plugin="$developer_dir/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
    frameworks="$developer_dir/Library/Developer/Frameworks"
    if [ -f "$plugin" ] && [ -d "$frameworks/Testing.framework" ]; then
        exec swift test --disable-xctest -Xswiftc -load-plugin-library -Xswiftc "$plugin" \
            -Xlinker -rpath -Xlinker "$frameworks" \
            -Xlinker -rpath -Xlinker "$developer_dir/Library/Developer/usr/lib" "$@"
    fi
fi
exec swift test --disable-xctest "$@"
