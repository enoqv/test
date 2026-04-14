# Dependency updates (Renovate)

Renovate runs from `.github/workflows/renovate.yml` (self-hosted via GitHub
Actions, not the Mend GitHub App). Configuration lives in `renovate.json`.

One-time setup on a fresh clone/fork:

1. Create a fine-grained Personal Access Token scoped to this repo with:
   - **Contents**: Read and write
   - **Pull requests**: Read and write
   - **Workflows**: Read and write  (required — `GITHUB_TOKEN` cannot edit workflow files)
   - **Issues**: Read and write  (required — Renovate maintains the
     `Dependency Dashboard` issue; without this, Renovate runs log
     `Could not ensure issue ... 403 Resource not accessible`)
   - **Commit statuses**: Read and write  (required — Renovate writes a
     `renovate/stability-days` commit status to track the `minimumReleaseAge`
     window; without this the run aborts with a misleading "Repository has
     changed during renovation" error)
   - **Dependabot alerts**: Read-only  (required for the `vulnerabilityAlerts`
     overlay in `renovate.json` to fire — see *Vulnerability-driven PRs* below)
2. Add it as a repository secret named `RENOVATE_TOKEN`.
3. The workflow then runs every 6 hours (at 00:00 / 06:00 / 12:00 / 18:00 UTC)
   and can also be triggered manually via the Actions tab, with an optional
   dry-run toggle.

## Vulnerability-driven PRs

Renovate has **two independent vulnerability channels**, and they use
different data sources. Enabling both gives the best coverage; each by
itself has blind spots.

| Channel                   | Data source                           | Enabled by                                                 |
| ------------------------- | ------------------------------------- | ---------------------------------------------------------- |
| `vulnerabilityAlerts`     | **GitHub Dependabot alerts** (GHSA)   | GitHub repo settings + PAT permission (see below)          |
| `osvVulnerabilityAlerts`  | **[OSV.dev](https://osv.dev/)**       | `"osvVulnerabilityAlerts": true` in `renovate.json`        |

The OSV channel is the same data source that `govulncheck` (run in CI)
queries against `vuln.go.dev`, so enabling it keeps Renovate and
`govulncheck` aligned: if `govulncheck` fails the build on a CVE,
Renovate should already have (or shortly open) a fix PR for the same
advisory. The GHSA channel occasionally has curated GitHub-only advisories
that OSV has not yet picked up, and vice-versa.

Quoting the [official docs](https://docs.renovatebot.com/configuration-options/#vulnerabilityalerts)
on what a `vulnerabilityAlerts` PR bypasses:

> When Renovate creates a `vulnerabilityAlerts` PR, it ignores settings
> like `branchConcurrentLimit`, `commitHourlyLimit`, `prConcurrentLimit`,
> `prHourlyLimit`, or `schedule`. […] In short: vulnerability alerts
> "skip the line".

That means CVE fixes are never delayed by `minimumReleaseAge: 15 days`,
the hourly PR cap, or the Dependency Dashboard approval gate.

**Required setup for the GHSA channel** (per
[Renovate docs](https://docs.renovatebot.com/configuration-options/#vulnerabilityalerts)):

1. Repo → **Settings → Code security** (formerly "Advanced Security"):
   - Enable **Dependency graph**.
   - Enable **Dependabot alerts**.
   - (Without both of these, GitHub has no alert feed for Renovate to
     read, and the `vulnerabilityAlerts` overlay in `renovate.json` stays
     inert — vulnerability-driven PRs look identical to regular dep bumps,
     with the `dependencies` label but no `security` label.)
2. Add **Dependabot alerts: Read-only** to the `RENOVATE_TOKEN` PAT
   (listed in the PAT permissions block above). For a Renovate GitHub App
   deployment, the equivalent permission is `vulnerability_alerts: read`.

**Required setup for the OSV channel:**

Add this line to `renovate.json` (default is `false`):

```json
"osvVulnerabilityAlerts": true
```

OSV coverage is limited to *direct* dependencies, and only for the
datasources Renovate forwards to OSV — `go`, `npm`, `maven`, `pypi`,
`crate`, `hex`, `hackage`, `nuget`, `packagist`, `rubygems`. The Go
module tree in this repo is fully covered.

**Verifying it works:**

Trigger `Renovate` via **Actions → Renovate → Run workflow** with
`logLevel: debug`. In the log you should see entries like:

```
DEBUG: Found N vulnerability alerts
DEBUG: Matched OSV vulnerabilities for <package>
```

And any CVE-driven PR will carry the `security` label (set by the
`vulnerabilityAlerts` overlay at `renovate.json`). If no PR ever carries
the `security` label, one of the two channels above is still misconfigured.
