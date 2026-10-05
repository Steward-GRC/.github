#!/usr/bin/env bash
# Fails when a go.mod in the repo builds against something CI can't
# reproduce:
#   - any replace directive;
#   - a github.com/Bugs5382/* module at a pseudo-version
#     (v0.0.0-<timestamp>-<commit>, vX.Y.Z-0.<timestamp>-<commit> or
#     vX.Y.Z-<pre>.0.<timestamp>-<commit>) rather than a tagged release;
#   - a github.com/Steward-GRC/* module at a pseudo-version whose commit isn't
#     reachable from its repo's main. While the org's modules are in
#     development they may be required at a commit on main; tags come at
#     release. Reachability is asked of GitHub's compare API the way
#     pin-check.sh asks it for proto pins:
#       repos/Steward-GRC/<repo>/compare/<commit>...main
#     passes on status "ahead" or "identical"; "behind", "diverged" and a 404
#     fail;
#   - an owner module at anything else that isn't a semver tag, such as a
#     pseudo-version with a short commit or timestamp, or a branch name.
# Third-party modules are left alone. Work against a local package checkout
# goes in a git-ignored go.work instead.
#
# The proto-sync workflow runs it from the root of the calling repo. It checks
# every go.mod below the root, skipping hidden directories (fetched protos,
# tool checkouts) and vendor/. It needs no Go toolchain. It needs gh on PATH,
# signed in or with GH_TOKEN set, only when a Steward-GRC module is at a
# pseudo-version.
set -euo pipefail

owners='^github\.com/(Bugs5382|Steward-GRC)/'
steward='^github\.com/Steward-GRC/([^/]+)'
pseudo='^v[0-9]+\.(0\.0-|[0-9]+\.[0-9]+-([0-9A-Za-z-]+\.)*0\.)[0-9]{14}-([0-9a-f]{12})(\+incompatible)?$'
pseudo_like='[0-9]{8,}-[0-9A-Za-z]{6,}(\+incompatible)?$'
tag='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+incompatible)?$'

# on_main <mod> <line> <path> <version> <commit>: asks the compare API whether
# <commit> is reachable from main of the Steward-GRC repo behind <path>.
on_main() {
  local mod="$1" n="$2" path="$3" ver="$4" commit="$5" repo out rc=0
  [[ "$path" =~ $steward ]]
  repo="Steward-GRC/${BASH_REMATCH[1]}"
  out="$(gh api "repos/$repo/compare/$commit...main?per_page=1" --jq .status 2>&1)" || rc=$?
  if ((rc != 0)); then
    if [[ "$out" == *"HTTP 404"* ]]; then
      echo "::error file=$mod,line=$n::$path is at a pseudo-version ($ver): $repo has no commit $commit (compare returned 404)."
    else
      echo "::error file=$mod,line=$n::$path is at a pseudo-version ($ver): comparing $commit with $repo main failed: ${out//$'\n'/ }"
    fi
    return 1
  fi
  case "$out" in
    ahead | identical)
      echo "$path $ver: $repo $commit is on main ($out)"
      ;;
    *)
      echo "::error file=$mod,line=$n::$path is at a pseudo-version ($ver) whose commit isn't reachable from $repo main (compare status: $out). Require a commit on main, or a tagged release."
      return 1
      ;;
  esac
}

mapfile -t mods < <(find . \( -name '.?*' -o -name vendor \) -prune -o -name go.mod -type f -print | sed 's|^\./||' | sort)
if ((${#mods[@]} == 0)); then
  echo "No go.mod: nothing to check."
  exit 0
fi

status=0
for mod in "${mods[@]}"; do
  bad=0
  dev=0
  block=""
  n=0
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    n=$((n + 1))
    line="${raw%%//*}"
    line="${line%$'\r'}"
    read -r -a f <<<"$line" || true
    ((${#f[@]} == 0)) && continue

    if [[ -n "$block" ]]; then
      if [[ "${f[0]}" == ")" ]]; then
        block=""
        continue
      fi
      words=("${f[@]}")
    else
      case "${f[0]}" in
        require | replace)
          if [[ "${f[1]:-}" == "(" ]]; then
            block="${f[0]}"
            continue
          fi
          block_once="${f[0]}"
          words=("${f[@]:1}")
          ;;
        *) continue ;;
      esac
    fi
    kind="${block:-$block_once}"

    if [[ "$kind" == replace ]]; then
      echo "::error file=$mod,line=$n::replace directive: ${words[*]}. Commit tagged versions only; link a local checkout with a git-ignored go.work."
      bad=1
    else
      path="${words[0]//\"/}"
      ver="${words[1]:-}"
      if [[ ! "$path" =~ $owners ]]; then
        continue
      elif [[ "$ver" =~ $pseudo ]]; then
        commit="${BASH_REMATCH[3]}"
        if [[ "$path" =~ $steward ]]; then
          if on_main "$mod" "$n" "$path" "$ver" "$commit"; then dev=1; else bad=1; fi
        else
          echo "::error file=$mod,line=$n::$path is at a pseudo-version ($ver). Require a tagged release; link a local checkout with a git-ignored go.work."
          bad=1
        fi
      elif [[ "$ver" =~ $pseudo_like || ! "$ver" =~ $tag ]]; then
        echo "::error file=$mod,line=$n::$path is at a malformed version ($ver). Require a tagged release, or for a Steward-GRC module a pseudo-version of a commit on main."
        bad=1
      fi
    fi
  done <"$mod"

  if ((bad == 1)); then
    status=1
  elif ((dev == 1)); then
    echo "$mod: no replace directives, owner packages at tagged releases or Steward-GRC commits on main"
  else
    echo "$mod: no replace directives, owner packages at tagged releases"
  fi
done

exit "$status"
