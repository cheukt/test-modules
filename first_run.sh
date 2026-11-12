#!/bin/sh
# Bundled only in the first-run versions. viam-server passes the module config's env.
delay="${FIRST_RUN_DELAY_SEC:-0}"
echo "first run: FIRST_RUN_DELAY_SEC=$delay FIRST_RUN_FAIL=${FIRST_RUN_FAIL:-0}"
sleep "$delay"
if [ "${FIRST_RUN_FAIL:-0}" = "1" ]; then
  echo "FIRST_RUN_FAIL=1, failing" >&2
  exit 1
fi
echo "first run succeeded"
