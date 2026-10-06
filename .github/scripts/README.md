# Shared workflows and their tools

The reusable workflows in `.github/workflows/` and the scripts behind them. Every Steward-GRC repo
calls them from its own `checks.yml`.

| Workflow | What it runs |
|---|---|
| `go.yml` | Go build and test: generated code current, buf lint and breaking, gofmt, go mod tidy, build, vet, test |
| `dco.yml` | the DCO sign-off on every commit (`dco-check.sh`) |
| `secrets.yml` | a gitleaks scan for committed credentials and keys, with gitleaks' default secret rules only |
| `proto-sync.yml` | the callee proto pin checks on PRs, and the scheduled pin refresh (`pin-check.sh`, `gomod-guard.sh`, `proto-sync.sh`) |
| `quality.yml` | opt-in, advisory only: golangci-lint, gosec, govulncheck and modernize on PRs (`quality-report.sh`) |

Every job runs on GitHub-hosted runners, has a timeout, and installs its tools at pinned versions:
actions by commit SHA, binaries checked against their SHA-256, Go tools through the Go checksum
database. None of them needs a secret beyond the default `GITHUB_TOKEN`.

## Calling them

A Go service's `checks.yml`:

```yaml
name: checks

on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]
  merge_group:
  push:
    branches: [main]
  schedule:
    - cron: "23 10 * * 1-5"
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: checks-${{ github.ref }}
  cancel-in-progress: true

jobs:
  checks:
    if: github.event_name != 'push' && github.event_name != 'schedule' && github.event_name != 'workflow_dispatch' && github.event.pull_request.draft != true
    uses: Steward-GRC/.github/.github/workflows/go.yml@main
    with:
      setup-script: scripts/ci-services.sh
  dco:
    if: github.event_name != 'push' && github.event_name != 'schedule' && github.event_name != 'workflow_dispatch' && github.event.pull_request.draft != true
    uses: Steward-GRC/.github/.github/workflows/dco.yml@main
  secrets:
    permissions:
      contents: read
    uses: Steward-GRC/.github/.github/workflows/secrets.yml@main
  proto-sync:
    if: github.event_name == 'pull_request' && github.event.pull_request.draft != true
    permissions:
      contents: read
    uses: Steward-GRC/.github/.github/workflows/proto-sync.yml@main
  proto-refresh:
    if: github.event_name == 'schedule' || github.event_name == 'workflow_dispatch'
    permissions:
      contents: write
      pull-requests: write
    uses: Steward-GRC/.github/.github/workflows/proto-sync.yml@main
```

- Drop `setup-script` when the tests need no containers. The script is the repo's own: it starts
  what its tests need (Postgres, RabbitMQ, RustFS) with `docker run` and appends any settings, such
  as a test DSN, to `$GITHUB_ENV`.
- Drop the `proto-sync` and `proto-refresh` jobs, and the schedule, in a repo that calls no other
  service.
- Keep the job id `secrets`: its required status check is `secrets / Secrets`. It takes no inputs
  and skips draft PRs itself. The `push` trigger on `main` is what gives it the full-history scan.
- Add the advisory `quality` job, described under [Quality](#quality), to see lint, SAST,
  vulnerability and modernize findings on a PR. It's opt-in and never required.
- Pin `@main` to a commit SHA (and `tools-ref` to the same SHA) when a repo needs to hold still
  while this repo changes.

## Run them locally

```bash
bash .github/scripts/dco-check.sh origin/main HEAD
bash <this repo>/.github/scripts/pin-check.sh
bash <this repo>/.github/scripts/gomod-guard.sh
bash <this repo>/.github/scripts/proto-sync.sh check
bash <this repo>/.github/scripts/proto-sync.sh refresh
```

The proto-sync scripts run from the root of the calling repo, with `buf` on the `PATH`;
`pin-check.sh`, and `gomod-guard.sh` when a Steward-GRC module is at a pseudo-version, also need
`gh`, signed in or with `GH_TOKEN` set. The self-tests run from anywhere
and touch no network:

```bash
bash .github/scripts/dco-check_test.sh
bash .github/scripts/secrets_test.sh
bash .github/scripts/pin-check_test.sh
bash .github/scripts/gomod-guard_test.sh
bash .github/scripts/proto-sync_test.sh
bash .github/scripts/quality-report_test.sh
```

This repo's own `checks.yml` runs actionlint and all six self-tests on every PR, and calls
`secrets.yml` on PRs, merge groups and pushes to `main`.

# DCO

`dco-check.sh <base> <head>` fails when any non-merge commit in `base..head` has no
`Signed-off-by: Name <email>` trailer. Merge commits are skipped. See
[CONTRIBUTING.md](../CONTRIBUTING.md) for how to sign off.

# Secrets

`secrets.yml` runs gitleaks, pinned to an exact version whose download is checked against the
SHA-256 in that release's checksums file:

- on `pull_request` it scans only the PR's own commits (`base..head`), and on `merge_group` only the
  group's, so a bad commit on some other branch never blocks every PR;
- on `push` (and any other event, such as a schedule) it scans the full history of the checked-out
  ref.

It runs gitleaks' built-in secret rules and nothing else: the scan always uses a config that only
extends the defaults, so a repo's own `.gitleaks.toml` can't add rules. Allow a false positive with a
`gitleaks:allow` comment on the line, or its fingerprint in the repo's `.gitleaksignore`. Findings are
redacted in the log.

`secrets_test.sh` runs the workflow's own scan step against throwaway repos: a range adding a fake
key fails, a clean range passes, a key on another branch doesn't fail a clean PR, and a push scans
the whole history. It builds its fake key at run time, so nothing committed here matches a secret
rule. It needs gitleaks at the pinned version on the `PATH`.

# Quality

`quality.yml` runs the heavy Go gates on a PR as **advisory** checks: their findings show on the PR
while it's under review, and they never fail it or block its merge. A repo opts in by adding one job
to its `checks.yml`:

```yaml
jobs:
  quality:
    if: github.event_name == 'pull_request' && github.event.pull_request.draft != true
    permissions:
      contents: read
    uses: Steward-GRC/.github/.github/workflows/quality.yml@main
```

It takes two optional inputs: `timeout-minutes` (each job's timeout, default 15) and `tools-ref`
(the ref of this repo to take `quality-report.sh` from, default `main`). Each tool runs in its own
job, side by side:

| Check | Tool |
|---|---|
| `quality / Lint (advisory)` | golangci-lint, with the repo's `.golangci.yml` when there is one |
| `quality / SAST (advisory)` | gosec, generated files skipped |
| `quality / Vulnerabilities (advisory)` | govulncheck: known vulnerabilities the code reaches in its dependencies |
| `quality / Modernize (advisory)` | the Go `modernize` analyzer, test files included |

The tool step continues on error, so findings never fail the job. `quality-report.sh` turns the
tool's output into warning annotations on the diff (the first 50) and a section of the job summary
with the full output and the count. Each job continues on error too, so even a failed install
leaves the caller's run green; the summary then says the tool didn't run. Never add these checks
to a ruleset's required status checks: they report, and fixing a finding is the author's call.

golangci-lint and gosec are release binaries checked against their SHA-256; govulncheck and
modernize come through `go install` and the Go checksum database. setup-go caches the module and
build caches, and the lint job also caches golangci-lint's own analysis cache.

Run the same tools locally from a repo's root:

```bash
golangci-lint run ./...
gosec -exclude-generated ./...
govulncheck ./...
modernize -test ./...
```

`quality-report_test.sh` feeds canned tool output to `quality-report.sh` and checks the
annotations and summary it writes. It needs none of the tools.

# Proto sync

A service never imports another service's Go module: it pins each callee's commit in
`proto-refs.env` (`STEWARD_<NAME>_REF=<commit>`, for `Steward-GRC/steward-<name>`), and its
`scripts/proto-generate.sh` fetches the callee's `proto/` at that commit and generates the client
stubs into its own `gen/`.

## What it checks

The `check` job (on a PR) runs two guards first, in every calling repo, with or without pins:

- **pin-check.sh** fails when a `STEWARD_<NAME>_REF` pin isn't reachable from the owner's `main`,
  asking GitHub's compare API (`repos/Steward-GRC/<repo>/compare/<pin>...main`). Status `ahead`
  or `identical` passes; `behind`, `diverged` and a 404 (no such repo or commit) fail. A
  squash-merged PR head still resolves on codeload until GitHub drops it, so a pin off `main`
  works for a while and then breaks with no warning. Pin the owner's merge commit instead.
- **gomod-guard.sh** checks every `go.mod` below the root (hidden directories and `vendor/`
  aside). It fails on:
  - a `replace` directive;
  - a `github.com/Bugs5382/*` module at a pseudo-version (`v0.0.0-<timestamp>-<commit>`,
    `vX.Y.Z-0.<timestamp>-<commit>` and the pre-release form). Bugs5382 modules use real tags only;
  - a `github.com/Steward-GRC/*` module at a pseudo-version whose commit isn't on its repo's
    `main`. While the org's own modules are in development, a service may require one at a
    pseudo-version of a commit on `main`; real tags (`v0.1.0` and on) come at release, and a tagged
    version always passes. The commit is checked the way `pin-check.sh` checks a pin:
    `repos/Steward-GRC/<repo>/compare/<commit>...main` passes on `ahead` or `identical`, and
    `behind`, `diverged` or a 404 fails. Require the owner's merge commit, never a PR head;
  - an owner module at anything that isn't a semver tag: a malformed pseudo-version (short
    commit or timestamp, upper-case hex) or a branch name.

  Third-party modules are left alone. The guard needs `gh` (signed in, or `GH_TOKEN`) only when a
  Steward-GRC module is at a pseudo-version.

To build and test against a local checkout of a package, use a git-ignored `go.work` beside the
service's `go.mod` instead (`go work init . ../go-<pkg>`, or `use . ../go-<pkg>` in the file).
Every Go repo ignores `go.work` and `go.work.sum`. Local callee protos come from the
`STEWARD_<SVC>_PROTO_DIR` overrides of the service's `scripts/proto-generate.sh`, never from an
edited pin.

Then, for each pin:

- **check** (on a PR) fails when a pin isn't on the owner's `main`, or when `buf breaking` finds
  that the owner's `main` breaks the protos at the pin. It only warns when `main`'s `proto/` has
  moved past the pin without a break, so an owner's additive change doesn't turn every caller's
  open PRs red.
- **refresh** (on the schedule) points every stale pin at the owner's `main`: a pin is stale when
  it isn't on `main` (a squash merge leaves the PR head off it) or when `proto/` differs. The
  workflow then reruns `scripts/proto-generate.sh` and opens or updates one PR from
  `chore/proto-refs`. CI doesn't start on a PR the workflow token opens, so a maintainer closes and
  reopens it. The org setting "Allow GitHub Actions to create and approve pull requests" must be on.
