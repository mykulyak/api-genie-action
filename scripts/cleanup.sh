#!/usr/bin/env bash
# Runs at the end of the action, also when it failed: removes the telemetry file apigenie wrote
# into the workspace (unless it was there before) and unregisters the problem matchers, which
# would otherwise annotate the output of later steps.
#
# Inputs: INPUT_COMMAND, TELEMETRY_EXISTED (false when run.sh found no telemetry file)

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

if [ -n "${INPUT_COMMAND:-}" ]; then
    if [ "${TELEMETRY_EXISTED:-}" = false ]; then
        rm -f .apigenie.telemetry
    fi
    for owner in apigenie-lint apigenie-diff-breaking apigenie-diff-non-breaking; do
        echo "::remove-matcher owner=$owner::"
    done
fi
