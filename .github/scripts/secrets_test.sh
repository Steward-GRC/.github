#!/usr/bin/env bash
# Self-test for the scan step of .github/workflows/secrets.yml. It runs that
# step's own script, read from the workflow, against throwaway local repos.
# Needs gitleaks at the version the workflow pins, and python3 with PyYAML.
#
# The test key is built at run time from a random suffix, so no file in this
# repo holds anything a secret scanner would match.
#
# Run from anywhere:
#   bash .github/scripts/secrets_test.sh
set -euo pipefail

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workflows="$scripts_dir/../workflows"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail=0
expect_exit() {
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1 (want exit $2, got $3)"; fail=1; fi
}
expect_contains() {
  if grep -qF -- "$2" "$3"; then echo "ok   $1"; else echo "FAIL $1 (missing: $2)"; fail=1; fi
}

read_yaml() {
  python3 - "$@" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
if sys.argv[2] == "scan":
    print(next(s["run"] for s in wf["jobs"]["secrets"]["steps"] if s.get("name") == "Scan for secrets"), end="")
else:
    print(wf["env"][sys.argv[2]])
PY
}

read_yaml "$workflows/secrets.yml" scan >"$work/scan.sh"
want_version="$(read_yaml "$workflows/secrets.yml" GITLEAKS_VERSION)"
got_version="$(gitleaks version)"
expect_exit "gitleaks on PATH is the pinned $want_version" "$want_version" "$got_version"
for k in GITLEAKS_VERSION GITLEAKS_SHA256; do
  expect_exit "checks.yml pins the same $k" "$(read_yaml "$workflows/secrets.yml" "$k")" "$(read_yaml "$workflows/checks.yml" "$k")"
done

# scan <event> <base> <head> <log>: prints the step's exit code.
scan() {
  local rc=0
  (cd "$work/repo" && EVENT="$1" BASE="$2" HEAD="$3" RUNNER_TEMP="$work" bash "$work/scan.sh") >"$4" 2>&1 || rc=$?
  echo "$rc"
}
commit() {
  git -C "$work/repo" add -A
  git -C "$work/repo" commit -q -s -m "$1"
  git -C "$work/repo" rev-parse HEAD
}

# Commits use the ambient git identity: the repo is local-only scratch,
# deleted on exit and never pushed.
git init -q -b main "$work/repo"

echo "# fixture" >"$work/repo/README.md"
root="$(commit "chore: root")"

# A fake AWS-style access key for this test only, never a real credential.
fake_key="AKIA$(python3 -c 'import secrets; print("".join(secrets.choice("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567") for _ in range(16)))')"
printf 'aws_access_key_id = %s\n' "$fake_key" >"$work/repo/settings.ini"
leaky="$(commit "feat: add settings")"
git -C "$work/repo" rm -q settings.ini
removed="$(commit "fix: drop settings")"

echo "clean" >>"$work/repo/README.md"
clean="$(commit "docs: clean change")"

rc="$(scan pull_request "$removed" "$clean" "$work/clean.log")"
expect_exit "a clean PR range passes" 0 "$rc"
expect_contains "it names the range" "Scanning ${removed}..${clean}." "$work/clean.log"

rc="$(scan pull_request "$root" "$leaky" "$work/leaky.log")"
expect_exit "a PR range adding a key fails" 1 "$rc"
if grep -qF -- "$fake_key" "$work/leaky.log"; then
  echo "FAIL the finding is redacted"; fail=1
else
  echo "ok   the finding is redacted"
fi

rc="$(scan merge_group "$root" "$clean" "$work/group.log")"
expect_exit "a merge group range holding a removed key still fails" 1 "$rc"

rc="$(scan push "" "" "$work/push.log")"
expect_exit "a push scans the full history" 1 "$rc"
expect_contains "it says so" "Scanning the full history." "$work/push.log"

git -C "$work/repo" switch -q -c bad "$root"
printf 'aws_access_key_id = %s\n' "$fake_key" >"$work/repo/other.ini"
commit "feat: a key on another branch" >/dev/null
git -C "$work/repo" switch -q main
rc="$(scan pull_request "$removed" "$clean" "$work/branch.log")"
expect_exit "a key on another branch doesn't fail a clean PR" 0 "$rc"

printf '[[rules]]\nid = "extra"\nregex = %s\n' "'''clean'''" >"$work/repo/.gitleaks.toml"
rc="$(scan pull_request "$removed" "$clean" "$work/config.log")"
expect_exit "a repo .gitleaks.toml can't add rules" 0 "$rc"
rm "$work/repo/.gitleaks.toml"

rc="$(scan schedule "" "" "$work/schedule.log")"
expect_exit "any other event scans the full history" 1 "$rc"
expect_contains "it says so too" "Scanning the full history." "$work/schedule.log"

rc="$(scan pull_request "" "" "$work/norange.log")"
expect_exit "a PR with no range is an error" 2 "$rc"

echo
if [[ "$fail" == 0 ]]; then
  echo "secrets_test.sh: all checks passed"
else
  echo "secrets_test.sh: FAILURES ABOVE"
fi
exit "$fail"
