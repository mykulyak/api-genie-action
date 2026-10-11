# Helpers shared by the scripts of the API Genie GitHub Action. Sourced, not executed.
#
# The scripts read their inputs from INPUT_* environment variables (set by action.yml) and the
# runner's GITHUB_* / RUNNER_* variables, so they can be run outside GitHub Actions by setting
# those variables (see ../tests/run.sh).

set -euo pipefail

# The scripts run with bash 3.2, the bash of macOS runners: no associative arrays, no globstar,
# and "${array[@]}" of an empty array is an error under set -u, hence ${array[@]+"${array[@]}"}.

# Prints an error annotation and exits with 1
fail() {
    echo "::error::$*"
    exit 1
}

# Appends name=value to the step outputs; the value may span several lines
set_output() {
    local name=$1 value=$2
    if [[ $value == *$'\n'* ]]; then
        local delimiter="APIGENIE_EOF_$RANDOM$RANDOM"
        printf '%s<<%s\n%s\n%s\n' "$name" "$delimiter" "$value" "$delimiter" >>"$GITHUB_OUTPUT"
    else
        printf '%s=%s\n' "$name" "$value" >>"$GITHUB_OUTPUT"
    fi
}

is_windows() {
    [ "${RUNNER_OS:-}" = Windows ]
}

# A path usable by bash: Windows paths (C:\...) become /c/... on Windows runners
unix_path() {
    if is_windows && command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$1"
    else
        printf '%s\n' "$1"
    fi
}

# A path for the runner and for other programs: /c/... becomes C:\... on Windows runners
native_path() {
    if is_windows && command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
    else
        printf '%s\n' "$1"
    fi
}

# Appends markdown to the job summary, unless the summary input is false
summary() {
    if [ "${INPUT_SUMMARY:-true}" = true ] && [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        printf '%s\n' "$@" >>"$GITHUB_STEP_SUMMARY"
    fi
}

# Appends a file to the job summary inside a collapsed block, cut to 300 lines and 64 KiB so the
# summary stays below GitHub's 1 MiB limit
summary_details() {
    local title=$1 file=$2 language=${3:-text}
    [ -s "$file" ] || return 0
    local lines
    lines=$(wc -l <"$file")
    summary "<details><summary>$title</summary>" "" "\`\`\`$language"
    if [ "${INPUT_SUMMARY:-true}" = true ] && [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        head -n 300 "$file" | head -c 65536 >>"$GITHUB_STEP_SUMMARY"
        # head -c may cut the last line
        [ -z "$(tail -c 1 "$GITHUB_STEP_SUMMARY")" ] || echo >>"$GITHUB_STEP_SUMMARY"
    fi
    summary "\`\`\`"
    if [ "$lines" -gt 300 ]; then
        summary "" "_Truncated: $lines lines, see the step log for all of them._"
    fi
    summary "" "</details>" ""
}

# Fills the FILES array from INPUT_FILES: one entry per line, or, when there is a single line,
# entries separated by whitespace. Entries are glob patterns (** included); a pattern matching
# nothing is an error, as is an empty list. Duplicates are dropped, keeping the first occurrence.
expand_files() {
    FILES=()
    local -a entries=()
    local line
    if [[ ${INPUT_FILES:-} == *$'\n'* ]]; then
        while IFS= read -r line; do
            line=${line#"${line%%[![:space:]]*}"}
            line=${line%"${line##*[![:space:]]}"}
            if [ -n "$line" ]; then
                entries+=("$line")
            fi
        done <<<"$INPUT_FILES"
    else
        read -r -a entries <<<"${INPUT_FILES:-}"
    fi
    [ ${#entries[@]} -gt 0 ] || fail "The 'files' input is empty: list the files to process."

    shopt -s nullglob
    local entry match
    # the files found so far, each between newlines; bash 3.2 has no associative arrays
    local seen=$'\n'
    for entry in "${entries[@]}"; do
        local -a matches=()
        if [[ $entry == *'**'* ]]; then
            # bash 3.2 has no globstar
            expand_globstar_pattern "$entry"
            matches=(${GLOB_MATCHES[@]+"${GLOB_MATCHES[@]}"})
        elif [[ $entry == *[\*\?\[]* ]]; then
            # unquoted on purpose: the entry is a glob pattern
            # shellcheck disable=SC2206
            matches=($entry)
        elif [ -e "$entry" ]; then
            matches=("$entry")
        fi
        [ ${#matches[@]} -gt 0 ] || fail "No file matches '$entry'."
        for match in "${matches[@]}"; do
            case $seen in
            *$'\n'"$match"$'\n'*) ;;
            *)
                seen=$seen$match$'\n'
                FILES+=("$match")
                ;;
            esac
        done
    done
    shopt -u nullglob
}

# Fills the GLOB_MATCHES array with the sorted matches of the glob pattern $1, which contains
# "**", like globstar would: a "**" path segment matches zero or more directories, hidden ones
# and symbolic links excepted; the other segments are ordinary glob patterns, so "?", brackets
# and the rule that "*" skips hidden files work as in bash. A trailing "**" also matches the
# directories. Needs nullglob.
expand_globstar_pattern() {
    local pattern=$1 start="" segment match sorted
    local -a segments=() parts=()
    if [[ $pattern == /* ]]; then
        start=/
    fi
    IFS=/ read -r -a segments <<<"$pattern"
    for segment in ${segments[@]+"${segments[@]}"}; do
        if [ -n "$segment" ]; then
            parts+=("$segment")
        fi
    done
    GLOB_MATCHES=()
    if [ ${#parts[@]} -gt 0 ]; then
        expand_globstar_segments "$start" "${parts[@]}"
    fi
    if [ ${#GLOB_MATCHES[@]} -gt 1 ]; then
        # bash sorts all the matches of a pattern together; the walk does not
        sorted=$(printf '%s\n' "${GLOB_MATCHES[@]}" | LC_ALL=C sort)
        GLOB_MATCHES=()
        while IFS= read -r match; do
            GLOB_MATCHES+=("$match")
        done <<<"$sorted"
    fi
}

# Appends to GLOB_MATCHES what the pattern segments $2... match below the directory $1 (ending
# with a slash, or empty for the working directory). Every branch succeeds: set -e is on.
expand_globstar_segments() {
    local dir=$1 segment=$2
    shift 2
    local candidate
    if [ "$segment" = '**' ]; then
        if [ $# -eq 0 ]; then
            # a trailing **: the directory itself, then everything below it
            if [ -n "$dir" ]; then
                GLOB_MATCHES+=("$dir")
            fi
            set -- '*'
        fi
        # zero directories, then one or more: every subdirectory ("*/" skips hidden ones)
        expand_globstar_segments "$dir" "$@"
        for candidate in "$dir"*/; do
            if ! [ -L "${candidate%/}" ]; then
                expand_globstar_segments "$candidate" '**' "$@"
            fi
        done
    elif [ $# -eq 0 ]; then
        # the last segment; a literal one (no glob characters, so nullglob does not apply to it)
        # only matches when it exists
        for candidate in "$dir"$segment; do
            if [ -e "$candidate" ] || [ -L "$candidate" ]; then
                GLOB_MATCHES+=("$candidate")
            fi
        done
    else
        for candidate in "$dir"$segment/; do
            if [ -d "$candidate" ]; then
                expand_globstar_segments "$candidate" "$@"
            fi
        done
    fi
}

# Fills the EXTRA_ARGS array from INPUT_ARGS, split on whitespace. Expand it as
# ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}: it may be empty, and set -u is on.
split_args() {
    EXTRA_ARGS=()
    if [ -n "${INPUT_ARGS:-}" ]; then
        read -r -a EXTRA_ARGS <<<"$INPUT_ARGS"
    fi
}

# Runs apigenie with the given arguments, its standard output going to the file $1 and its
# standard error to $1.err; sets CLI_EXIT to its exit status. Never fails the script by itself.
run_cli() {
    local out=$1
    shift
    set +e
    "$APIGENIE" "$@" >"$out" 2>"$out.err"
    CLI_EXIT=$?
    set -e
    # Windows builds may end lines with CRLF; the parsing below expects LF
    local file
    for file in "$out" "$out.err"; do
        tr -d '\r' <"$file" >"$file.lf"
        mv "$file.lf" "$file"
    done
}

# Prints what run_cli captured into the step log: standard output (which the problem matcher
# reads) and standard error
show_output() {
    local out=$1
    [ -s "$out" ] && cat "$out"
    [ -s "$out.err" ] && cat "$out.err" >&2
    return 0
}

# Fails with the CLI's own error message: for exit statuses that mean the CLI could not run
fail_with_cli_error() {
    local out=$1 what=$2
    local message=""
    [ -s "$out.err" ] && message=$(head -n 5 "$out.err" | tr '\n' ' ')
    fail "apigenie $what failed (exit status $CLI_EXIT)${message:+: $message}"
}

# A temporary directory below RUNNER_TEMP
make_temp_dir() {
    local root
    root=$(unix_path "${RUNNER_TEMP:-${TMPDIR:-/tmp}}")
    mkdir -p "$root"
    mktemp -d "$root/apigenie-XXXXXX"
}
