# Checks that INPUT_FILES are formatted (apigenie format --check). Sourced by run.sh.
#
# Outputs: exit-code, status (clean or changed), changed-files (one per line)

expand_files

work=$(make_temp_dir)
changed=$work/changed
problems=$work/problems
: >"$changed"
: >"$problems"
exit_code=0

# the CLI takes at most 100 files at a time
batch_size=100
for ((start = 0; start < ${#FILES[@]}; start += batch_size)); do
    batch=("${FILES[@]:start:batch_size}")
    args=(format --check)
    [ -n "${INPUT_CONFIG:-}" ] && args+=(--config "$INPUT_CONFIG")
    args+=(${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} "${batch[@]}")

    out=$work/format-$start.out
    echo "apigenie format --check ... (${#batch[@]} file(s))"
    run_cli "$out" "${args[@]}"
    show_output "$out"
    [ "$CLI_EXIT" -gt "$exit_code" ] && exit_code=$CLI_EXIT
    if [ "$CLI_EXIT" -ne 0 ] && [ "$CLI_EXIT" -ne 1 ]; then
        set_output exit-code "$CLI_EXIT"
        fail_with_cli_error "$out" "format --check"
    fi
    # standard output: the files that would change; standard error: their count, and the files
    # that can't be formatted (syntax errors, unsupported documents)
    cat "$out" >>"$changed"
    grep -v 'file(s) would be reformatted\.$' "$out.err" >>"$problems" || true
done
set_output exit-code "$exit_code"

changed_count=$(grep -c . "$changed" || true)
if [ "$changed_count" -gt 0 ]; then
    status=changed
else
    status=clean
fi
set_output status "$status"
set_output changed-files "$(cat "$changed")"

summary "### apigenie format --check" ""
if [ "$changed_count" -gt 0 ]; then
    summary "$changed_count of ${#FILES[@]} file(s) are not formatted:" ""
    while IFS= read -r file; do
        summary "- \`$file\`"
        echo "::warning file=$file::$file is not formatted; run apigenie format on it."
    done <"$changed"
    summary "" "Format them with \`apigenie format <files>\`$([ -n "${INPUT_CONFIG:-}" ] && echo " --config $INPUT_CONFIG")." ""
else
    summary "All ${#FILES[@]} file(s) are formatted." ""
fi
if [ -s "$problems" ]; then
    summary_details "Files that could not be formatted" "$problems"
fi

# files that can't be formatted are errors whatever fail-on says, like invalid input for lint
[ -s "$problems" ] && fail "apigenie format could not format some files: $(head -n 3 "$problems" | tr '\n' ' ')"
if [ "$INPUT_FAIL_ON" != never ] && [ "$changed_count" -gt 0 ]; then
    fail "$changed_count file(s) are not formatted."
fi
