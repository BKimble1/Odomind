#!/bin/bash
# Prints the failures from xcodebuild logs, last, so a log tail finds them.
#
# The simulator writes thousands of "[error] CoreData: error: ..." lines about
# probing directories it cannot write to. They are harmless, and a plain
# `grep error:` returns nothing else — the real compiler errors, assertion
# messages and accessibility findings never make it past `head`. Hence the
# filtering.
set -uo pipefail

logs=("$@")
strip='s|/Users/runner/work/Odomind/Odomind/||'

# Simulator and framework chatter that is never the answer.
noise='CoreData: error:|\[error\] CoreData|^ *Information for /|^ *File (Device ID|Size|inode|user ID|group ID|Permissions)|component is (not )?(readable|writeable|a symbolic link)'

section() {
  echo
  echo "================ $1 ================"
}

grab() {
  grep -hE "$1" "${logs[@]}" 2>/dev/null | grep -vE "$noise" | sed "$strip"
}

section "COMPILER ERRORS"
grab "error:" \
  | grep -vE "^Test Case|XCTAssert|: error: -\[|Accessibility|contrast|hit region|Element" \
  | sort -u | head -40

section "ASSERTION FAILURES"
grab ": error: -\[|XCTAssert.* failed" | sort -u | head -40

section "ACCESSIBILITY AUDIT FINDINGS"
# The audit records issues rather than throwing, so they arrive as their own
# lines naming the element and the rule it broke.
grab "Accessibility|audit|contrast|hit region|Dynamic Type|clipped|no description" \
  | sort -u | head -40

section "FAILED TESTS"
grab "^Test Case .* failed" | head -40

section "END"
