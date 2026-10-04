#!/usr/bin/env bash
# Self-test for pin-check.sh. It touches no network: a fake gh on PATH answers
# the compare calls the way the GitHub API does.
#
# Cases:
#   - good:     a commit on main (compare status "ahead" or "identical")
#   - pr-head:  a squash-merged PR head, never on main ("diverged")
#   - missing:  a SHA the repo doesn't have (HTTP 404)
#   - a pin ahead of main, an unknown repo and malformed lines fail too
#
# Run from anywhere:
#   bash .github/scripts/pin-check_test.sh
set -euo pipefail

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pin_check="$scripts_dir/pin-check.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail=0
ok() { echo "ok: $1"; }
bad() {
  echo "FAIL: $1"
  fail=1
}
expect_exit() { # expect_exit <desc> <want> <got>
  if [[ "$2" == "$3" ]]; then ok "$1 (exit $3)"; else bad "$1 (want exit $2, got $3)"; fi
}
expect_contains() { # expect_contains <desc> <needle> <file>
  if grep -qF -- "$2" "$3"; then
    ok "$1"
  else
    bad "$1 (missing: $2)"
    sed 's/^/    /' "$3" >&2
  fi
}
expect_not_contains() { # expect_not_contains <desc> <needle> <file>
  if grep -qF -- "$2" "$3"; then
    bad "$1 (should not contain: $2)"
    sed 's/^/    /' "$3" >&2
  else
    ok "$1"
  fi
}

# run <dir> <log>: runs pin-check.sh in <dir> and echoes its exit code.
run() {
  local rc=0
  (cd "$1" && bash "$pin_check") >"$2" 2>&1 || rc=$?
  sed 's/^/    | /' "$2" >&2
  echo "$rc"
}

good=1111111111111111111111111111111111111111
same=2222222222222222222222222222222222222222
head=3333333333333333333333333333333333333333
gone=4444444444444444444444444444444444444444
behind=5555555555555555555555555555555555555555

# The fake gh answers `gh api repos/<org>/<repo>/compare/<sha>...main?per_page=1 --jq .status`
# and 404s on anything else, as the API does for an unknown repo or commit.
fake="$work/bin"
mkdir -p "$fake"
{
  echo '#!/usr/bin/env bash'
  echo '[[ "$1" == api ]] || exit 9'
  echo 'case "$2" in'
  echo "  repos/fixture-org/steward-audit/compare/$good...main?per_page=1) echo ahead ;;"
  echo "  repos/fixture-org/steward-core/compare/$same...main?per_page=1) echo identical ;;"
  echo "  repos/fixture-org/steward-delivery/compare/$head...main?per_page=1) echo diverged ;;"
  echo "  repos/fixture-org/steward-identity/compare/$behind...main?per_page=1) echo behind ;;"
  echo '  *)'
  echo "    echo '{\"message\":\"Not Found\",\"status\":\"404\"}'"
  echo '    echo "gh: Not Found (HTTP 404)" >&2'
  echo '    exit 1'
  echo '    ;;'
  echo 'esac'
} >"$fake/gh"
chmod +x "$fake/gh"

echo "=== offline: fake compare API ==="
export PROTO_SYNC_ORG=fixture-org

mkdir -p "$work/good"
printf '%s\n' "# a comment, then a blank line" "" \
  "STEWARD_AUDIT_REF=$good" "STEWARD_CORE_REF=$same" >"$work/good/proto-refs.env"
rc="$(PATH="$fake:$PATH" run "$work/good" "$work/good.log")"
expect_exit "good pins pass" 0 "$rc"
expect_contains "ahead is on main" "STEWARD_AUDIT_REF: fixture-org/steward-audit $good is on main (ahead)" "$work/good.log"
expect_contains "identical is on main" "STEWARD_CORE_REF: fixture-org/steward-core $same is on main (identical)" "$work/good.log"

mkdir -p "$work/bad"
printf '%s\n' \
  "STEWARD_AUDIT_REF=$good" \
  "STEWARD_DELIVERY_REF=$head" \
  "STEWARD_CORE_REF=$gone" \
  "STEWARD_IDENTITY_REF=$behind" \
  "STEWARD_NOSUCH_REF=$good" \
  "STEWARD_SHORT_REF=abc123" \
  "OTHER_REF=$good" >"$work/bad/proto-refs.env"
rc="$(PATH="$fake:$PATH" run "$work/bad" "$work/bad.log")"
expect_exit "bad pins fail" 1 "$rc"
expect_not_contains "the good pin isn't flagged" "::error file=proto-refs.env::STEWARD_AUDIT_REF" "$work/bad.log"
expect_contains "a PR head off main fails" \
  "::error file=proto-refs.env::STEWARD_DELIVERY_REF: $head isn't reachable from fixture-org/steward-delivery main (compare status: diverged)." "$work/bad.log"
expect_contains "a missing SHA fails" \
  "::error file=proto-refs.env::STEWARD_CORE_REF: fixture-org/steward-core has no commit $gone (compare returned 404)." "$work/bad.log"
expect_contains "a pin ahead of main fails" \
  "::error file=proto-refs.env::STEWARD_IDENTITY_REF: $behind isn't reachable from fixture-org/steward-identity main (compare status: behind)." "$work/bad.log"
expect_contains "an unknown repo fails" \
  "::error file=proto-refs.env::STEWARD_NOSUCH_REF: fixture-org/steward-nosuch has no commit $good (compare returned 404)." "$work/bad.log"
expect_contains "a short SHA fails" \
  "::error file=proto-refs.env::Not a STEWARD_<NAME>_REF=<40-hex commit> line: STEWARD_SHORT_REF=abc123" "$work/bad.log"
expect_contains "a ref outside STEWARD_ fails" \
  "::error file=proto-refs.env::Not a STEWARD_<NAME>_REF=<40-hex commit> line: OTHER_REF=$good" "$work/bad.log"

mkdir -p "$work/none"
rc="$(PATH="$fake:$PATH" run "$work/none" "$work/none.log")"
expect_exit "no proto-refs.env passes" 0 "$rc"

echo
if [[ "$fail" == 0 ]]; then
  echo "pin-check_test.sh: all checks passed"
else
  echo "pin-check_test.sh: FAILURES ABOVE"
fi
exit "$fail"
