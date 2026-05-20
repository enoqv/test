# Dependency updates (Renovate)

Renovate runs from `.github/workflows/renovate.yml` (self-hosted via
GitHub Actions, not the Mend GitHub App). Configuration lives in
`renovate.json`.

## Authentication

Renovate authenticates as a **GitHub App** that you create and install
on this repo. The installation token is minted fresh at workflow
runtime (every cron tick) by `actions/create-github-app-token` from
the App's private key — no long-lived PAT.

### One-time App setup (UI)

1. Go to <https://github.com/settings/apps/new> and create a new
   GitHub App.

   - **Name**: anything; suggested `renovate-self-host-<owner>`
   - **Homepage URL**: link to this repo
   - **Webhook → Active**: **uncheck**. We don't process webhooks.

2. **Repository permissions**:

   | Permission | Access | Reason |
   |---|---|---|
   | Contents | Read & write | Create branches, push commits. |
   | Pull requests | Read & write | Open / update / close PRs. |
   | Workflows | Read & write | Edit `.github/workflows/*.yml`; `GITHUB_TOKEN` cannot. |
   | Issues | Read & write | Maintain the Dependency Dashboard issue (otherwise runs log `Could not ensure issue ... 403`). |
   | Commit statuses | Read & write | Set the `renovate/stability-days` status that tracks `minimumReleaseAge` (otherwise runs abort with a misleading "Repository has changed during renovation" error). |
   | Metadata | Read | Required for any App; granted automatically. |

   All other permissions: leave at **No access**.

3. **Where can this GitHub App be installed?**: select
   **Only on this account**.

4. Click **Create GitHub App**.

5. On the App's settings page:

   - **App ID**: visible at the top. Note it down.
   - **Private keys** → **Generate a private key**. Downloads a `.pem`
     file. Treat it as a secret; it cannot be re-downloaded.

6. **Install** the App: in the left sidebar click **Install App**,
   pick your account, and choose **Only select repositories** →
   `<owner>/<repo>` (this repo only).

### Store credentials in this repo

Settings → **Secrets and variables → Actions**:

- **Variables tab → New repository variable**
  - Name: `RENOVATE_APP_ID`
  - Value: the App ID from step 5.
- **Secrets tab → New repository secret**
  - Name: `RENOVATE_APP_PRIVATE_KEY`
  - Value: **entire contents** of the downloaded `.pem` file
    (including the `-----BEGIN ... PRIVATE KEY-----` lines).

App ID is stored as a Variable (not a secret) because it is not
sensitive on its own; the private key is the gating credential.

### Retiring the previous PAT

Earlier revisions of this repo authenticated Renovate via a
fine-grained PAT stored as `secrets.RENOVATE_TOKEN`. After the first
successful App-token run lands a PR, delete the PAT:

1. Settings → Secrets and variables → Actions → `RENOVATE_TOKEN` →
   **Remove**.
2. Either delete the PAT itself at
   <https://github.com/settings/tokens?type=beta>, or rotate it out
   of any other place it might be reused.

## Schedule

- Workflow cron: every 6 hours (`0 */6 * * *`).
- `renovate.json` does **not** set a `schedule` field, so Renovate can
  open PRs whenever the workflow runs.
- `vulnerabilityAlerts` in `renovate.json` bypasses all scheduling, so
  CVE-driven PRs go out as soon as the next cron tick picks them up.

## Vulnerability-driven PRs

Renovate has **two independent vulnerability channels**. They use
different data sources and have different setup costs. This repo
currently enables **only the OSV channel** (the zero-setup one); the
GHSA channel is documented below as an optional upgrade.

| Channel                   | Data source                           | Status          | Setup                                                      |
| ------------------------- | ------------------------------------- | --------------- | ---------------------------------------------------------- |
| `osvVulnerabilityAlerts`  | **[OSV.dev](https://osv.dev/)**       | **enabled**     | `"osvVulnerabilityAlerts": true` in `renovate.json`        |
| `vulnerabilityAlerts`     | **GitHub Dependabot alerts** (GHSA)   | not enabled     | GitHub repo settings + App permission (see *Optional* below) |

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
No GitHub setting needed. No App permission needed. Renovate downloads
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

1. Repo → **Settings → Code security**:
   - Enable **Dependency graph**.
   - Enable **Dependabot alerts**.
2. On the Renovate GitHub App created above, add the permission
   **Dependabot alerts: Read-only** (API name `vulnerability_alerts:
   read`). After changing permissions, GitHub will prompt the
   installation owner to **accept the new permissions** before they
   take effect.

No change to `renovate.json` is needed — the existing
`vulnerabilityAlerts` overlay block in `renovate.json` already
configures the output side (labels, schedule bypass, release-age
bypass); it only sits idle today because Renovate cannot read
GitHub's alert feed.

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

## Manual run / dry run

`renovate.yml` exposes `workflow_dispatch` with two inputs:

- `logLevel`: `info` (default) or `debug`.
- `dryRun`: `false` (default) or `true` — Renovate logs what it would
  do without creating any branches or PRs.

Use **Actions → Renovate → Run workflow** to trigger an out-of-band
run.
