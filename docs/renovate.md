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
2. Add it as a repository secret named `RENOVATE_TOKEN`.
3. The workflow then runs every 6 hours (at 00:00 / 06:00 / 12:00 / 18:00 UTC)
   and can also be triggered manually via the Actions tab, with an optional
   dry-run toggle.

## Vulnerability-driven PRs

Renovate has **two independent vulnerability channels**. They use
different data sources and have different setup costs. This repo
currently enables **only the OSV channel** (the zero-setup one); the
GHSA channel is documented below as an optional upgrade.

| Channel                   | Data source                           | Status          | Setup                                                      |
| ------------------------- | ------------------------------------- | --------------- | ---------------------------------------------------------- |
| `osvVulnerabilityAlerts`  | **[OSV.dev](https://osv.dev/)**       | **enabled**     | `"osvVulnerabilityAlerts": true` in `renovate.json`        |
| `vulnerabilityAlerts`     | **GitHub Dependabot alerts** (GHSA)   | not enabled     | GitHub repo settings + PAT permission (see *Optional* below) |

The OSV channel is the same data source that `govulncheck` (run in CI)
queries against `vuln.go.dev`, so enabling it keeps Renovate and
`govulncheck` aligned: if `govulncheck` fails the build on a CVE,
Renovate should already have (or shortly open) a fix PR for the same
advisory.

Quoting the [official docs](https://docs.renovatebot.com/configuration-options/#vulnerabilityalerts)
on what a vulnerability-alert PR bypasses:

> When Renovate creates a `vulnerabilityAlerts` PR, it ignores settings
> like `branchConcurrentLimit`, `commitHourlyLimit`, `prConcurrentLimit`,
> `prHourlyLimit`, or `schedule`. […] In short: vulnerability alerts
> "skip the line".

That means CVE fixes are never delayed by `minimumReleaseAge: 15 days`,
the hourly PR cap, or the Dependency Dashboard approval gate. The same
overlay applies to OSV-driven PRs.

### OSV channel (active)

Already configured in `renovate.json` as `"osvVulnerabilityAlerts": true`.
No GitHub setting needed. No PAT permission needed. Renovate downloads
the OSV database locally via
[renovate-offline](https://github.com/renovatebot/osv-offline) and
queries it offline each run.

Per the [official docs](https://docs.renovatebot.com/configuration-options/#osvvulnerabilityalerts),
coverage is limited to:

- **Direct dependencies only.** Transitive / `// indirect` entries in
  `go.mod` are not surfaced as vuln PRs (though `govulncheck` still
  catches reachable transitive CVEs at CI time).
- Datasources forwarded to OSV: `go`, `npm`, `maven`, `pypi`, `crate`,
  `hex`, `hackage`, `nuget`, `packagist`, `rubygems`. The Go module
  tree in this repo is fully covered.

### GHSA channel (optional upgrade)

Adds coverage for transitive dependencies and any GHSA-curated
advisories that OSV has not yet picked up. Also surfaces the repo's
vulnerabilities in the GitHub **Security** tab and sends maintainer
email alerts, independently of Renovate.

To enable (per
[Renovate docs](https://docs.renovatebot.com/configuration-options/#vulnerabilityalerts)):

1. Repo → **Settings → Code security** (formerly "Advanced Security"):
   - Enable **Dependency graph**.
   - Enable **Dependabot alerts**.
2. Add **Dependabot alerts: Read-only** to the `RENOVATE_TOKEN` PAT.
   For a Renovate GitHub App deployment, the equivalent permission is
   `vulnerability_alerts: read`.
3. Don't forget to also add the new permission to the PAT permission
   list at the top of this doc when you do this.

No change to `renovate.json` is needed — the existing `vulnerabilityAlerts`
overlay block at `renovate.json:107` already configures the output
side (labels, schedule bypass, release-age bypass); it only sits idle
today because Renovate cannot read GitHub's alert feed.

### Verifying it works

Trigger `Renovate` via **Actions → Renovate → Run workflow** with
`logLevel: debug`. In the log you should see entries like:

```
DEBUG: Matched OSV vulnerabilities for <package>
```

And once the GHSA channel is also enabled:

```
DEBUG: Found N vulnerability alerts
```

Any CVE-driven PR will carry the `security` label (set by the
`vulnerabilityAlerts` overlay at `renovate.json`). If `govulncheck`
reports a CVE in CI but no PR ever carries the `security` label after
the next Renovate run, the active channel is misconfigured.
