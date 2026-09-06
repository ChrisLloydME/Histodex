#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p .tmp/tmp .tmp/cache/clang .tmp/build
export LLVM_PROFILE_FILE="$PWD/.tmp/build/app-%p.profraw"
export TMPDIR="$PWD/.tmp/tmp"
export CLANG_MODULE_CACHE_PATH="$PWD/.tmp/cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.tmp/cache/clang"
export CFFIXED_USER_HOME="$PWD/.tmp/xcode-home"
export SWIFTPM_TESTS_PACKAGECACHE="$PWD/.tmp/cache"
export XDG_CACHE_HOME="$PWD/.tmp/cache"
exec xcodebuild -project Histodex.xcodeproj -scheme Histodex -configuration Debug -derivedDataPath "$PWD/.tmp/build/app" -clonedSourcePackagesDirPath "$PWD/.tmp/build/core" -packageCachePath "$PWD/.tmp/cache" -disablePackageRepositoryCache CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build "$@"
