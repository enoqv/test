# Branch protection (recommended)

The required-status-checks list, signed-commit policy, and code-owner
review requirement below are what we expect on the `main` branch. They
are documented here rather than baked into a script because GitHub
exposes them through the UI, and several of the entries (status check
names) only exist after the first run lands.

## minimumReleaseAge background

`renovate.json` uses `internalChecksFilter: "flexible"` together with
`minimumReleaseAge: "15 days"`. This combination means:

- If a **matured older version** (≥ 15 days old) exists, Renovate
  opens a PR for that version and waits for the newest release to
  mature.
- If **no matured version** exists (e.g. a brand-new major that
  skipped patch releases), Renovate still opens a PR for the latest
  version, but posts a **`renovate/stability-days`** commit status of
  **`pending`** until the release ages past the window.

The "pending" status only *blocks merges* if branch protection is
configured to require it.

## Settings → Branches → Branch protection rules → `main`

1. **Branch name pattern**: `main`.
2. **Require a pull request before merging**.
   - **Require approvals**: 1 (or more).
   - **Dismiss stale pull request approvals when new commits are pushed**.
   - **Require review from Code Owners**. This activates the
     `.github/CODEOWNERS` file: changes to workflows, the Dockerfile,
     linter config, Renovate config, and `docs/` cannot land without
     the owner's review.
3. **Require status checks to pass before merging** and **Require
   branches to be up to date before merging**.

   Add the checks below to the search box. **Status checks only appear
   after they have run at least once on a PR targeting `main`** — open
   a throwaway PR first if a check name does not autocomplete.

   | Check name | Workflow | Notes |
   |---|---|---|
   | `Lint (hadolint)` | `_validate.yml` | Dockerfile lint + digest-pin gate |
   | `Lint (golangci-lint)` | `_validate.yml` | govet + errcheck + ineffassign + staticcheck + unused + gosec |
   | `Test` | `_validate.yml` | `go test -race ./...` |
   | `Govulncheck (Go vulnerability reachability)` | `_validate.yml` | OSV-backed |
   | `Verify base image signatures` | `_validate.yml` | cosign verify of every `FROM @sha256:...` |
   | `Trivy CVE scan` | `_validate.yml` | OS + library, blocks on CRITICAL/HIGH |
   | `Dependency review (PR only)` | `_validate.yml` | PR-only, GHSA-backed |
   | `Analyze (Go)` | `codeql.yml` | CodeQL, security-and-quality queries |
   | `renovate/stability-days` | (Renovate-set) | **Enforces `minimumReleaseAge`** |

4. **Require signed commits**.
5. **Require linear history**.
6. **Do not allow bypassing the above settings**.
7. **Restrict who can push to matching branches** → leave empty (push
   to `main` should only happen via PR merge anyway).

Once `renovate/stability-days` is a required check, any Renovate PR
whose release has not yet matured will be un-mergeable (even by a
human clicking the button) until the age window elapses and Renovate
flips the status to `success` on its next run.

> Status checks only appear in the search box after they have run at
> least once on a PR targeting `main`. If you can't find one, open a
> throwaway PR that touches the relevant workflow, let CI run, then
> come back and add it.

## Image signature verification

The publish workflow signs every released image both via cosign
keyless signing (Sigstore) and via the GitHub-native artifact
attestation API.

### cosign (post-rename — current)

For images pushed by `.github/workflows/publish.yml`:

```sh
cosign verify \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
  --certificate-identity-regexp='^https://github\.com/<owner>/<repo>/\.github/workflows/publish\.yml@refs/tags/v.+' \
  ghcr.io/<owner>/<repo>:<tag>
```

### cosign (pre-rename — legacy)

For images pushed before the rename of `release.yml` →`publish.yml`,
the workflow-identity subject ends in `release.yml@refs/tags/<tag>`
and the older regex is required:

```sh
cosign verify \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
  --certificate-identity-regexp='^https://github\.com/<owner>/<repo>/\.github/workflows/release\.yml@refs/tags/v.+' \
  ghcr.io/<owner>/<repo>:<tag>
```

The cutoff is the merge of the commit that renamed `release.yml` →
`publish.yml`; any `v*.*.*` tag built before that commit landed on
`main` has the legacy identity, any tag built after has the new one.
Pick the regex based on when the tag's commit reached `main`.

### gh attestation (no cosign needed)

For consumers who do not have `cosign` installed, the same image is
also covered by GitHub's first-party attestation API:

```sh
gh attestation verify \
  oci://ghcr.io/<owner>/<repo>@<digest> \
  --owner <owner>
```

To pull the SPDX SBOM that ships alongside:

```sh
gh attestation verify \
  oci://ghcr.io/<owner>/<repo>@<digest> \
  --predicate-type 'https://spdx.dev/Document' \
  --owner <owner>
```

## Known scan limitations

- **Trivy in `_validate.yml` scans amd64 only.** The `Build local
  image for scanning` step uses `load: true`, which BuildKit only
  supports for a single architecture; arm64 is therefore not scanned
  in CI. In practice this rarely matters — the base image (Go builder
  alpine, distroless static-debian12) ships identical package sets
  for both architectures — but a publisher-only arm64 OS package
  vulnerability would not be caught here. The publish workflow's
  in-image SBOM attestation does cover arm64, so a downstream Trivy
  scan against the pushed image will still see it.

- **govulncheck is reachability-aware, not Trivy.** A CRITICAL-rated
  CVE in a Go dependency where the vulnerable function is never
  called is silently passed by `govulncheck`. Trivy will still flag
  it. The two scanners are not redundant; each catches what the
  other ignores.
