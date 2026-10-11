#!/usr/bin/env bash
# Installs apigenie into the runner's tool cache and puts it on PATH.
#
# Inputs:  APIGENIE_VERSION, APIGENIE_PLATFORM, APIGENIE_ASSET, APIGENIE_EXE (from resolve.sh),
#          INPUT_BINARY (an already built binary: nothing is downloaded),
#          APIGENIE_DOWNLOAD_BASE_URL (where the assets are; defaults to the GitHub release)
# Outputs: path (of the executable, native on Windows), cache-hit

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Extracts the zip archive $1 into the directory $2. Git for Windows has no unzip, and its tar
# can't read zip archives, hence the alternatives.
extract_zip() {
    local archive=$1 dir=$2
    if command -v unzip >/dev/null 2>&1; then
        unzip -q -o "$archive" -d "$dir"
    elif command -v 7z >/dev/null 2>&1; then
        7z x -y -bd -o"$(native_path "$dir")" "$(native_path "$archive")" >/dev/null
    elif command -v powershell >/dev/null 2>&1; then
        powershell -NoProfile -NonInteractive -Command \
            "Expand-Archive -Force -LiteralPath '$(native_path "$archive")' -DestinationPath '$(native_path "$dir")'"
    else
        fail "Cannot extract $archive: neither unzip, 7z nor powershell is available."
    fi
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{ print $1 }'
    else
        shasum -a 256 "$1" | awk '{ print $1 }'
    fi
}

download() {
    local url=$1 target=$2
    curl --fail --silent --show-error --location --retry 3 --output "$target" "$url" ||
        fail "Cannot download $url."
}

if [ -n "${INPUT_BINARY:-}" ]; then
    binary=$(unix_path "$INPUT_BINARY")
    binary_dir=$(cd "$(dirname "$binary")" && pwd)
    native_path "$binary_dir" >>"$GITHUB_PATH"
    set_output path "$(native_path "$binary_dir/$(basename "$binary")")"
    set_output cache-hit false
    exit 0
fi

: "${APIGENIE_VERSION:?}" "${APIGENIE_PLATFORM:?}" "${APIGENIE_ASSET:?}" "${APIGENIE_EXE:?}"

tool_cache=$(unix_path "${RUNNER_TOOL_CACHE:?RUNNER_TOOL_CACHE is not set}")
tool_dir=$tool_cache/apigenie/$APIGENIE_VERSION/$APIGENIE_PLATFORM

if [ -f "$tool_dir/.complete" ] && [ -f "$tool_dir/$APIGENIE_EXE" ]; then
    echo "apigenie $APIGENIE_VERSION is in the tool cache"
    cache_hit=true
else
    cache_hit=false
    base_url=${APIGENIE_DOWNLOAD_BASE_URL:-https://github.com/mykulyak/api-genie/releases/download/cli-$APIGENIE_VERSION}
    work=$(make_temp_dir)
    trap 'rm -rf "$work"' EXIT

    echo "Downloading $base_url/$APIGENIE_ASSET"
    download "$base_url/$APIGENIE_ASSET" "$work/$APIGENIE_ASSET"
    download "$base_url/SHA256SUMS" "$work/SHA256SUMS"

    # sha256sum lines: "<hash>  <name>", or "<hash> *<name>" for binary mode
    expected=$(awk -v name="$APIGENIE_ASSET" '$2 == name || $2 == "*" name { print $1 }' "$work/SHA256SUMS")
    [ -n "$expected" ] || fail "SHA256SUMS of apigenie $APIGENIE_VERSION does not list $APIGENIE_ASSET."
    actual=$(sha256_of "$work/$APIGENIE_ASSET")
    [ "$expected" = "$actual" ] ||
        fail "The checksum of $APIGENIE_ASSET ($actual) does not match SHA256SUMS ($expected)."

    rm -rf "$tool_dir.tmp"
    mkdir -p "$tool_dir.tmp"
    case $APIGENIE_ASSET in
    *.tar.gz) tar -xzf "$work/$APIGENIE_ASSET" -C "$tool_dir.tmp" ;;
    *.zip) extract_zip "$work/$APIGENIE_ASSET" "$tool_dir.tmp" ;;
    *) fail "Unknown archive type: $APIGENIE_ASSET" ;;
    esac
    [ -f "$tool_dir.tmp/$APIGENIE_EXE" ] || fail "$APIGENIE_ASSET does not contain $APIGENIE_EXE."
    # apigenie-generator and apigenie-mock come in the same archive and land on the PATH too
    chmod +x "$tool_dir.tmp"/apigenie*
    touch "$tool_dir.tmp/.complete"
    # an interrupted extraction never leaves a directory that looks complete
    rm -rf "$tool_dir"
    mv "$tool_dir.tmp" "$tool_dir"
fi

reported=$("$tool_dir/$APIGENIE_EXE" --version) || fail "The installed apigenie does not run."
[ "$reported" = "$APIGENIE_VERSION" ] ||
    fail "The installed apigenie reports version $reported instead of $APIGENIE_VERSION."

native_path "$tool_dir" >>"$GITHUB_PATH"
set_output path "$(native_path "$tool_dir/$APIGENIE_EXE")"
set_output cache-hit "$cache_hit"
echo "Installed apigenie $APIGENIE_VERSION"
