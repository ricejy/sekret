#!/usr/bin/env bash
# Human-in-the-loop fallback from diagnosing-bugs/scripts/hitl-loop.template.sh.
# Only user-observed facts belong in these answers; native reports are separate.
set -euo pipefail
capture() {
  local var="$1" question="$2" answer
  printf '\n>>> %s\n' "$question"
  read -r -p '    > ' answer
  printf -v "$var" '%s' "$answer"
}
capture STOP_OBSERVATION 'In Sekret Local Eval, tap Run locally; once text appears, tap Stop. Does it say cancelled and re-enable Run? Then run again and let it finish. Report both outcomes and any freeze.'
capture BACKGROUND_OBSERVATION 'Run again; once text appears, swipe Home, wait 2 seconds, then reopen Sekret Local Eval. Does it show cancellation and allow another run to finish? Report both outcomes and any crash.'
printf '\nUSER_REPORTED_STOP=%s\nUSER_REPORTED_BACKGROUND=%s\n' "$STOP_OBSERVATION" "$BACKGROUND_OBSERVATION"
