# Lints INPUT_FILES. Sourced by run.sh.
#
# Outputs: exit-code, status (clean, warnings or errors), error-count and warning-count (unix
# formatter only), sarif-file (with INPUT_SARIF)

expand_files
formatter=${INPUT_FORMATTER:-unix}

args=(lint --formatter "$formatter")
[ -n "${INPUT_CONFIG:-}" ] && args+=(--config "$INPUT_CONFIG")
args+=(${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} "${FILES[@]}")

work=$(make_temp_dir)
out=$work/lint.out
echo "apigenie ${args[*]}"
run_cli "$out" "${args[@]}"
show_output "$out"
set_output exit-code "$CLI_EXIT"

# 0: no errors, 1: errors (or an exception), anything else: an input could not be read
if [ "$CLI_EXIT" -ne 0 ] && [ "$CLI_EXIT" -ne 1 ]; then
    fail_with_cli_error "$out" lint
fi

# SARIF for code scanning, in a second run so that the log keeps its annotations. The file is
# outside the temporary directory: the upload step after this one reads it.
if [ "${INPUT_SARIF:-false}" = true ]; then
    sarif_args=(lint --formatter sarif)
    [ -n "${INPUT_CONFIG:-}" ] && sarif_args+=(--config "$INPUT_CONFIG")
    sarif_args+=(${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} "${FILES[@]}")
    sarif_base=$(mktemp "$(dirname "$work")/apigenie-lint-XXXXXX")
    sarif_file=$sarif_base.sarif
    mv "$sarif_base" "$sarif_file"
    lint_exit=$CLI_EXIT
    run_cli "$sarif_file" "${sarif_args[@]}"
    if [ "$CLI_EXIT" -eq 0 ] || [ "$CLI_EXIT" -eq 1 ]; then
        set_output sarif-file "$(native_path "$sarif_file")"
    else
        echo "::warning::apigenie lint --formatter sarif failed (exit status $CLI_EXIT): no SARIF to upload."
    fi
    rm -f "$sarif_file.err"
    CLI_EXIT=$lint_exit
fi

if [ "$formatter" = unix ]; then
    errors=$(grep -c ' \[Error/[^]]*\]$' "$out" || true)
    warnings=$(grep -c ' \[Warning/[^]]*\]$' "$out" || true)
    # exit status 1 without errors: the configuration or a document could not be parsed
    if [ "$CLI_EXIT" -eq 1 ] && [ "$errors" -eq 0 ]; then
        fail_with_cli_error "$out" lint
    fi
    set_output error-count "$errors"
    set_output warning-count "$warnings"
else
    # other formatters are not parsed: only the exit status tells whether there were errors
    errors=$([ "$CLI_EXIT" -eq 1 ] && echo 1 || echo 0)
    warnings=0
fi

if [ "$errors" -gt 0 ]; then
    status=errors
elif [ "$warnings" -gt 0 ]; then
    status=warnings
else
    status=clean
fi
set_output status "$status"

summary "### apigenie lint" ""
if [ "$formatter" = unix ]; then
    summary "${#FILES[@]} file(s) linted: **$errors error(s)**, $warnings warning(s)." ""
    if [ "$((errors + warnings))" -gt 0 ]; then
        summary "| File | Errors | Warnings |" "| --- | ---: | ---: |"
        # file names are everything before ":line:column: "
        sed -nE 's/^(.+):[0-9]+:[0-9]+: .* \[(Error|Warning)\/[^]]*\]$/\2 \1/p' "$out" |
            awk '{ kind = $1; $1 = ""; file = substr($0, 2); if (!(file in seen)) { seen[file] = 1; order[++n] = file } count[file, kind]++ }
                 END { for (i = 1; i <= n; i++) { f = order[i]; printf "| `%s` | %d | %d |\n", f, count[f, "Error"], count[f, "Warning"] } }' |
            while IFS= read -r row; do summary "$row"; done
        summary ""
    fi
else
    summary "${#FILES[@]} file(s) linted: $([ "$errors" -gt 0 ] && echo "**errors reported**" || echo "no errors")." ""
fi
summary_details "Output" "$out"

case $INPUT_FAIL_ON in
error) [ "$errors" -eq 0 ] || fail "apigenie lint reported $([ "$formatter" = unix ] && echo "$errors " || echo "")error(s)." ;;
warning) [ "$((errors + warnings))" -eq 0 ] || fail "apigenie lint reported $errors error(s) and $warnings warning(s)." ;;
never) ;;
esac
