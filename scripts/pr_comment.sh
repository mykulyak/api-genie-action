# The diff report as a pull request comment that later runs update in place, so that it outlives
# the annotations, which disappear once the files change. Sourced by diff.sh.
#
# Inputs: INPUT_PR_COMMENT, INPUT_PR_COMMENT_KEY, PR_NUMBER (empty outside pull requests),
# GH_TOKEN, GITHUB_REPOSITORY

# Whether the report goes to a comment: on pull requests, unless the pr-comment input is false
pr_comment_enabled() {
    [ "${INPUT_PR_COMMENT:-true}" = true ] && [ -n "${PR_NUMBER:-}" ]
}

# The hidden first line that tells the comment of this step from the others. The key is cut to
# characters that need no quoting in the jq filter of find_pr_comment.
pr_comment_marker() {
    local key=${INPUT_PR_COMMENT_KEY:-${GITHUB_WORKFLOW:-}/${GITHUB_JOB:-}}
    key=$(printf '%s' "$key" | tr -c 'A-Za-z0-9._/ -' '-')
    printf '<!-- apigenie-diff:%s -->\n' "$key"
}

pr_comment_warning() {
    local message=$1 err=$2
    local detail=""
    [ -s "$err" ] && detail=$(head -n 3 "$err" | tr '\n' ' ')
    detail=${detail% }
    echo "::warning::$message${detail:+ ($detail)}. The token needs the pull-requests: write" \
        "permission; pull requests from forks only get a read-only one."
}

# Creates or updates the comment with the body in the file $1, which starts with the marker.
# $2 is false when there are no changes: then no new comment is created, but an existing one is
# still updated, so that it doesn't keep reporting changes that were reverted. Never fails.
post_sticky_comment() {
    local body=$1 changes=$2
    if ! command -v gh >/dev/null 2>&1; then
        echo "::warning::gh is not installed: the diff report is not posted to the pull request."
        return 0
    fi

    local marker err ids id
    marker=$(pr_comment_marker)
    err=$body.err
    if ! ids=$(gh api --paginate "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" \
        --jq ".[] | select(.body | contains(\"$marker\")) | .id" 2>"$err"); then
        pr_comment_warning "Cannot read the comments of pull request #$PR_NUMBER" "$err"
        return 0
    fi
    id=${ids%%$'\n'*}

    if [ -z "$id" ] && [ "$changes" = false ]; then
        return 0
    fi
    if [ -n "$id" ]; then
        if gh api --method PATCH "repos/$GITHUB_REPOSITORY/issues/comments/$id" \
            -F "body=@$(native_path "$body")" >/dev/null 2>"$err"; then
            echo "Updated the diff report on pull request #$PR_NUMBER."
        else
            pr_comment_warning "Cannot update the comment of pull request #$PR_NUMBER" "$err"
        fi
    else
        if gh api --method POST "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" \
            -F "body=@$(native_path "$body")" >/dev/null 2>"$err"; then
            echo "Posted the diff report to pull request #$PR_NUMBER."
        else
            pr_comment_warning "Cannot comment on pull request #$PR_NUMBER" "$err"
        fi
    fi
    return 0
}
