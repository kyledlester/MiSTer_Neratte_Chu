#!/bin/sh
# Project rule: before ANY Quartus operation, wait while Quartus processes of other projects run.
# Usage: scripts/qwait.sh && <quartus command>
others() {
  powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name like 'quartus%'\" | Where-Object { \$_.CommandLine -notmatch 'NeratteChu' } | Select-Object -ExpandProperty CommandLine"
}
n=0
while [ -n "$(others)" ]; do
  [ $n = 0 ] && echo "qwait: waiting for other Quartus jobs: $(others | tr '\n' ' ')"
  n=1; sleep 20
done
