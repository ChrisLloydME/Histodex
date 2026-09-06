#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p .tmp/cache/clang .tmp/swift-config .tmp/swift-security .tmp/tmp
export TMPDIR="$PWD/.tmp/tmp"
export CLANG_MODULE_CACHE_PATH="$PWD/.tmp/cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.tmp/cache/clang"
export XDG_CACHE_HOME="$PWD/.tmp/cache"
exec swift "${1:-test}" --package-path Packages/HistodexCore --scratch-path "$PWD/.tmp/build/core" --cache-path "$PWD/.tmp/cache" --config-path "$PWD/.tmp/swift-config" --security-path "$PWD/.tmp/swift-security" --disable-sandbox "${@:2}"
