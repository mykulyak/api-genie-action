# Compares INPUT_FILES with their versions at a git commit (INPUT_BASE, else DEFAULT_BASE: the
# pull request's base or the commit before a push), or one file with INPUT_BASE_FILE. Sourced by
# run.sh.
#
# Outputs: exit-code, status (none, non-breaking or breaking)

# shellcheck source=pr_comment.sh
source "$(dirname "${BASH_SOURCE[0]}")/pr_comment.sh"

for arg in ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}; do
    if [ "$arg" = --update-version ]; then
        fail "--update-version is not supported by the action."
    fi
done

expand_files
formatter=${INPUT_FORMATTER:-unix}
report=${INPUT_REPORT:-changelog}
case $report in
status | changelog | detailed) ;;
*) fail "Invalid report '$report': use status, changelog or detailed." ;;
esac

work=$(make_temp_dir)
old_files=()
new_files=()

if [ -n "${INPUT_BASE_FILE:-}" ]; then
    [ ${#FILES[@]} -eq 1 ] || fail "With base-file, 'files' must name exactly one file (it names ${#FILES[@]})."
    [ -f "$INPUT_BASE_FILE" ] || fail "The base file '$INPUT_BASE_FILE' does not exist."
    old_files+=("$INPUT_BASE_FILE")
    new_files+=("${FILES[0]}")
    base_label=$INPUT_BASE_FILE
else
    base=${INPUT_BASE:-${DEFAULT_BASE:-}}
    if [ -z "$base" ] || [[ $base =~ ^0+$ ]]; then
        fail "Nothing to compare with: set 'base' to a git ref, or 'base-file'. Pull requests and" \
            "pushes default to their base commit."
    fi
    git rev-parse --git-dir >/dev/null 2>&1 || fail "Not in a git repository: run actions/checkout first."
    if ! git cat-file -e "$base^{commit}" 2>/dev/null; then
        echo "Fetching $base"
        git fetch --quiet --no-tags --depth=1 origin "$base" ||
            fail "Cannot fetch $base: check out the repository with fetch-depth: 0."
        base=FETCH_HEAD
    fi
    sha=$(git rev-parse --verify "$base^{commit}") || fail "'$base' is not a commit."
    base_label=$(git rev-parse --short "$sha")
    prefix=$(git rev-parse --show-prefix)
    toplevel=$(unix_path "$(git rev-parse --show-toplevel)")

    index=0
    for file in "${FILES[@]}"; do
        # the path of the file in the repository, as git show wants it
        unix_file=$(unix_path "$file")
        if [[ $unix_file == /* ]]; then
            [[ $unix_file == "$toplevel"/* ]] || fail "'$file' is not in the repository."
            path_in_repo=${unix_file#"$toplevel"/}
        else
            path_in_repo=$prefix${unix_file#./}
        fi
        if git cat-file -e "$sha:$path_in_repo" 2>/dev/null; then
            index=$((index + 1))
            # same name, so that the extension still tells the kind of document
            mkdir -p "$work/base/$index"
            old_file=$work/base/$index/$(basename "$file")
            git show "$sha:$path_in_repo" >"$old_file"
            old_files+=("$old_file")
            new_files+=("$file")
        else
            echo "::notice file=$file::$file is new since $base_label: nothing to compare it with."
        fi
    done
fi

status=none
exit_code=0
summary "### apigenie diff" "" "Compared with \`$base_label\`." ""
comment_files=$work/comment-files.md
: >"$comment_files"
for i in "${!new_files[@]}"; do
    old=${old_files[i]}
    new=${new_files[i]}
    out=$work/diff-$i

    # the status, for the output and the summary
    run_cli "$out.status" diff --report status --formatter json ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} "$old" "$new"
    if [ "$CLI_EXIT" -ne 0 ] && [ "$CLI_EXIT" -ne 1 ]; then
        set_output exit-code "$CLI_EXIT"
        fail_with_cli_error "$out.status" "diff of $new"
    fi
    file_status=$(sed -nE 's/.*"status" *: *"([a-z-]+)".*/\1/p' "$out.status" | head -n 1)
    [ -n "$file_status" ] || fail "Unexpected output of apigenie diff: $(head -c 200 "$out.status")"
    [ "$CLI_EXIT" -gt "$exit_code" ] && exit_code=$CLI_EXIT
    case $file_status in
    breaking) status=breaking ;;
    non-breaking) [ "$status" = breaking ] || status=non-breaking ;;
    esac

    # the report in the log, where the problem matcher turns unix lines into annotations; the
    # positions are those of the new file, which is the one in the workspace
    echo "apigenie diff --report $report --formatter $formatter $new ($file_status)"
    run_cli "$out.log" diff --report "$report" --formatter "$formatter" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} "$old" "$new"
    show_output "$out.log"

    summary "#### \`$new\`: $file_status" ""
    printf '#### `%s`: %s\n\n' "$new" "$file_status" >>"$comment_files"
    if [ "$file_status" != none ] && { [ "${INPUT_SUMMARY:-true}" = true ] || pr_comment_enabled; }; then
        run_cli "$out.md" diff --report "$report" --formatter markdown ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} "$old" "$new"
        if [ -s "$out.md" ]; then
            summary "<details><summary>Changes</summary>" ""
            if [ "${INPUT_SUMMARY:-true}" = true ]; then
                summary_cut "$out.md"
            fi
            summary "" "</details>" ""
            cat "$out.md" >>"$comment_files"
            printf '\n' >>"$comment_files"
        fi
    fi
done

if [ ${#new_files[@]} -eq 0 ]; then
    summary "No file to compare." ""
fi
set_output exit-code "$exit_code"
set_output status "$status"

if pr_comment_enabled; then
    comment=$work/comment.md
    case $status in
    breaking) headline="**Breaking changes.**" ;;
    non-breaking) headline="Non-breaking changes only." ;;
    *) headline="No API changes." ;;
    esac
    {
        pr_comment_marker
        printf '### apigenie diff\n\n%s Compared with `%s`.\n\n' "$headline" "$base_label"
        if [ ${#new_files[@]} -eq 0 ]; then
            printf 'No file to compare.\n'
        fi
    } >"$comment"
    # GitHub refuses comments longer than 65536 characters
    limit=60000
    if [ "$(wc -c <"$comment_files")" -gt "$limit" ]; then
        head -c "$limit" "$comment_files" >>"$comment"
        printf '\n\n_Truncated: the full report is in the job summary%s._\n' \
            "${GITHUB_RUN_ID:+ of ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/$GITHUB_RUN_ID}" >>"$comment"
    else
        cat "$comment_files" >>"$comment"
    fi
    post_sticky_comment "$comment" "$([ "$status" = none ] && echo false || echo true)"
fi

if [ "$INPUT_FAIL_ON" != never ] && [ "$status" = breaking ]; then
    fail "apigenie diff found breaking changes."
fi
