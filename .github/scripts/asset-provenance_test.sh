#!/usr/bin/env bash
# Self-test for the asset provenance step of .github/workflows/secrets.yml. It
# runs that step's own script, read from the workflow, against throwaway local
# repos. Needs python3 with PyYAML.
#
# Run from anywhere:
#   bash .github/scripts/asset-provenance_test.sh
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

python3 - "$workflows/secrets.yml" >"$work/scan.sh" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
print(next(s["run"] for s in wf["jobs"]["secrets"]["steps"] if s.get("name") == "Scan assets for provenance metadata"), end="")
PY

# A minimal PNG: signature, IHDR, an optional extra chunk, IEND. Chunk CRCs
# are not checked by the scan, so they are zero.
png() {
  python3 - "$1" "${2:-}" <<'PY'
import struct, sys
out, extra = sys.argv[1], sys.argv[2]
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + b"\0\0\0\0"
data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
if extra:
    data += chunk(b"caBX", b"\0\0\0\x20jumb\0\0\0\x18jumdc2pa")
data += chunk(b"IEND", b"")
open(out, "wb").write(data)
PY
}

new_repo() {
  local dir="$work/$1"
  git init -q "$dir"
  echo "$dir"
}

run_scan() {
  local code=0
  (cd "$1" && bash "$work/scan.sh") >"$2" 2>&1 || code=$?
  echo "$code"
}

repo="$(new_repo clean)"
png "$repo/logo.png"
printf '<svg xmlns="http://www.w3.org/2000/svg"/>\n' >"$repo/mark.svg"
git -C "$repo" add . && git -C "$repo" commit -qm clean
expect_exit "clean assets pass" 0 "$(run_scan "$repo" "$work/clean.log")"

repo="$(new_repo png)"
png "$repo/icon.PNG" c2pa
git -C "$repo" add . && git -C "$repo" commit -qm marked
expect_exit "a PNG with a C2PA chunk fails" 1 "$(run_scan "$repo" "$work/png.log")"
expect_contains "the failing PNG is named" "icon.PNG" "$work/png.log"

repo="$(new_repo svg)"
printf '<svg xmlns="http://www.w3.org/2000/svg"><metadata>c2pa.assertions</metadata></svg>\n' >"$repo/mark.svg"
git -C "$repo" add . && git -C "$repo" commit -qm marked
expect_exit "an SVG with C2PA metadata fails" 1 "$(run_scan "$repo" "$work/svg.log")"
expect_contains "the failing SVG is named" "mark.svg" "$work/svg.log"

repo="$(new_repo untracked)"
png "$repo/tracked.png"
git -C "$repo" add . && git -C "$repo" commit -qm clean
png "$repo/stray.png" c2pa
expect_exit "untracked files are not scanned" 0 "$(run_scan "$repo" "$work/untracked.log")"

repo="$(new_repo text)"
printf 'The scan looks for c2pa markers in assets.\n' >"$repo/README.md"
git -C "$repo" add . && git -C "$repo" commit -qm docs
expect_exit "text files that mention c2pa are not scanned" 0 "$(run_scan "$repo" "$work/text.log")"

exit "$fail"
