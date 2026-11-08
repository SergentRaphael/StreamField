#!/usr/bin/env bash
# Lance une commande ; si elle échoue, publie la fin du journal en « annotation »
# (visible sur la page du build, et lisible pour corriger plus vite).
set -o pipefail
"$@" 2>&1 | tee .run.log
code=${PIPESTATUS[0]}
if [ "$code" -ne 0 ]; then
  msg=$(grep -E "error|Error|ERROR|FAILED|Exception|rror:" .run.log | grep -v "^\s*$" | tail -n 80)
  [ -z "$msg" ] && msg=$(tail -n 80 .run.log)
  msg=$(printf '%s\n' "$msg" | head -c 30000 | sed -e 's/%/%25/g' -e 's/\r//g' | awk 'BEGIN{ORS="%0A"} {print}')
  echo "::error title=Échec de : $1 $2::$msg"
fi
exit "$code"
