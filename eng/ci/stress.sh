#!/usr/bin/env bash
# Repeat every real-tmux suite and keep one receipt per suite and iteration.
# Usage: stress.sh PWSH PACKAGE_ROOT REPEAT RECEIPT_DIR [SUITES]
# SUITES is a space-separated subset; the default is every repeatable suite.
set -u
pwsh=$1
package=$2
repeat=$3
receipts=$4
suites=${5:-$(python3 eng/ci/stress.py suites)} || exit 1
mkdir -p "${receipts}"
for iteration in $(seq 1 "${repeat}"); do
  mkdir -p "${receipts}/${iteration}"
  for suite in ${suites}; do
    rm -f "build/test-${suite}.json"
    # A failing suite is a measurement, not a reason to stop repeating.
    "${pwsh}" -NoLogo -NoProfile -File eng/Test.ps1 -Suite "${suite}" -PackageRoot "${package}" || true
    cp "build/test-${suite}.json" "${receipts}/${iteration}/" || echo "::warning::no receipt for ${suite} in iteration ${iteration}"
  done
done
