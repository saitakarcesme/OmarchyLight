#!/bin/sh
set -eu
if [ "$(uname -s)" != Darwin ]; then
    printf '%s\n' 'This optional tool requires macOS 13+ and Apple Command Line Tools.' >&2
    exit 1
fi
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
xcrun swiftc -swift-version 5 -parse-as-library -O \
    -framework AppKit -framework AVFoundation -framework CoreGraphics \
    -framework CoreImage -framework ScreenCaptureKit \
    "$script_dir/Probe.swift" -o "$script_dir/reference-probe"
printf '%s\n' "Built $script_dir/reference-probe"
