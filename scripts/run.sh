#!/usr/bin/env bash
# Runs the command of the action (lint, format or diff) with the installed apigenie.
#
# Inputs:  APIGENIE (the executable), INPUT_COMMAND, INPUT_FAIL_ON and the inputs of the command
# Outputs: exit-code, status, telemetry-existed, and those of the command

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

scripts_dir=$(dirname "${BASH_SOURCE[0]}")

: "${APIGENIE:?APIGENIE is not set}"
APIGENIE=$(unix_path "$APIGENIE")

# Every run of apigenie writes .apigenie.telemetry into the working directory; cleanup.sh removes
# it unless it was there before
if [ -e .apigenie.telemetry ]; then
    set_output telemetry-existed true
else
    set_output telemetry-existed false
fi

INPUT_FAIL_ON=${INPUT_FAIL_ON:-error}
case $INPUT_FAIL_ON in
error | warning | never) ;;
*) fail "Invalid fail-on '$INPUT_FAIL_ON': use error, warning or never." ;;
esac

split_args

case ${INPUT_COMMAND:-} in
lint | format | diff)
    # shellcheck source=/dev/null
    source "$scripts_dir/$INPUT_COMMAND.sh"
    ;;
*) fail "Invalid command '${INPUT_COMMAND:-}': use lint, format or diff." ;;
esac
