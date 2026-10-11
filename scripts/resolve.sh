#!/usr/bin/env bash
# Decides which apigenie to install: the version and the release asset of the runner's platform.
#
# Inputs:  INPUT_VERSION (latest, X.Y.Z or cli-X.Y.Z), INPUT_BINARY (an already built binary)
# Outputs: version, platform, asset, exe

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# The first release with the asset names this action downloads, `lint` failing on errors and
# `format --check`
MIN_VERSION=0.9.0
RELEASE_REPO=${APIGENIE_RELEASE_REPO:-https://github.com/mykulyak/api-genie.git}

# Succeeds when version $1 is lower than version $2 (semantic versions; a pre-release is lower
# than its release)
version_lt() {
    local a=$1 b=$2
    local a_base=${a%%-*} b_base=${b%%-*}
    local a_pre="" b_pre=""
    [[ $a == *-* ]] && a_pre=${a#*-}
    [[ $b == *-* ]] && b_pre=${b#*-}
    local -a a_parts b_parts
    IFS=. read -r -a a_parts <<<"$a_base"
    IFS=. read -r -a b_parts <<<"$b_base"
    local i
    for i in 0 1 2; do
        local x=$((10#${a_parts[i]:-0})) y=$((10#${b_parts[i]:-0}))
        if ((x != y)); then
            ((x < y))
            return
        fi
    done
    if [ -z "$a_pre" ] || [ -z "$b_pre" ]; then
        # equal bases: only a pre-release is lower than the release
        [ -n "$a_pre" ] && [ -z "$b_pre" ]
        return
    fi
    [[ $a_pre < $b_pre ]]
}

# Sets LATEST to the newest release: the highest version without a pre-release suffix or, when
# there is none, the highest pre-release. Not run in $(...), so that fail() is seen.
latest_version() {
    local tags
    tags=$(git ls-remote --tags --refs "$RELEASE_REPO" 'refs/tags/cli-*') ||
        fail "Cannot list the releases of $RELEASE_REPO."
    local best_stable="" best_any="" tag version
    while read -r _ tag; do
        version=${tag#refs/tags/cli-}
        [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || continue
        if [ -z "$best_any" ] || version_lt "$best_any" "$version"; then
            best_any=$version
        fi
        if [[ $version != *-* ]] && { [ -z "$best_stable" ] || version_lt "$best_stable" "$version"; }; then
            best_stable=$version
        fi
    done <<<"$tags"
    [ -n "$best_any" ] || fail "$RELEASE_REPO has no apigenie release (no cli-* tag)."
    LATEST=${best_stable:-$best_any}
}

if [ -n "${INPUT_BINARY:-}" ]; then
    binary=$(unix_path "$INPUT_BINARY")
    [ -f "$binary" ] || fail "The binary '$INPUT_BINARY' does not exist."
    version=$("$binary" --version) || fail "Cannot run '$INPUT_BINARY --version'."
    set_output version "$version"
    set_output platform local
    set_output asset ""
    set_output exe "$(basename "$binary")"
    echo "Using $INPUT_BINARY (apigenie $version)"
    exit 0
fi

case "${RUNNER_OS:-}/${RUNNER_ARCH:-}" in
Linux/X64) platform=linux-x64 archive=tar.gz exe=apigenie ;;
macOS/ARM64) platform=macos-arm64 archive=zip exe=apigenie ;;
Windows/X64) platform=windows-x64 archive=zip exe=apigenie.exe ;;
*)
    fail "apigenie has no release for ${RUNNER_OS:-?}/${RUNNER_ARCH:-?} runners. Supported runners:" \
        "Linux x64 (ubuntu-*), macOS arm64 (macos-14 and newer) and Windows x64 (windows-*)."
    ;;
esac

version=${INPUT_VERSION:-latest}
version=${version#cli-}
version=${version#v}
if [ "$version" = latest ]; then
    latest_version
    version=$LATEST
    echo "The latest release is $version"
elif ! [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
    fail "Invalid version '$INPUT_VERSION': use latest, X.Y.Z or cli-X.Y.Z."
fi
if version_lt "$version" "$MIN_VERSION"; then
    fail "apigenie $version is too old for this action: use $MIN_VERSION or newer."
fi

set_output version "$version"
set_output platform "$platform"
set_output asset "apigenie-$version-$platform.$archive"
set_output exe "$exe"
echo "Installing apigenie $version for $platform"
