# test

A simple Go member-system backend.

## Stack

- **Go 1.22** with [chi](https://github.com/go-chi/chi) router
- **PostgreSQL** as primary data store (via `pgx/v5`)
- **Redis** as cache (via `go-redis/v9`)
- **JWT** for session tokens (`golang-jwt/v5`)
- **bcrypt** for password hashing

## Layout

```
cmd/server       # entrypoint
internal/config  # env-based configuration
internal/model   # domain types
internal/repository  # Postgres data access
internal/cache       # Redis + in-memory cache
internal/service     # business logic
internal/handler     # HTTP handlers / routing
migrations           # SQL schema
```

## Test UI

A static web page is served at **`/`** (from the `web/` directory) with forms
for register / login / `/api/me` / `/api/members/{id}` / `/healthz`.
The JWT returned by login is stored in `localStorage` and reused for authenticated calls.

## Endpoints

| Method | Path                | Auth  | Description          |
| ------ | ------------------- | ----- | -------------------- |
| GET    | `/healthz`          | no    | Liveness probe       |
| POST   | `/api/register`     | no    | Register a member    |
| POST   | `/api/login`        | no    | Obtain a JWT         |
| GET    | `/api/me`           | yes   | Current member       |
| GET    | `/api/members/{id}` | yes   | Fetch member by ID   |

## Configuration (env vars)

| Name | Default |
| --- | --- |
| `HTTP_ADDR` | `:8080` |
| `DATABASE_URL` | `postgres://postgres:postgres@localhost:5432/members?sslmode=disable` |
| `REDIS_ADDR` | `localhost:6379` |
| `REDIS_PASSWORD` | *(empty)* |
| `REDIS_DB` | `0` |
| `JWT_SECRET` | `change-me-in-production` |
| `JWT_EXPIRATION` | `24h` |
| `CACHE_TTL` | `5m` |

## Local development

```sh
docker compose up --build
```

## Tests

```sh
go test ./...
```

## Docker image

Multi-arch images (amd64 + arm64) are built via GitHub Actions and pushed to
`ghcr.io/<owner>/<repo>` on every push to `main` and feature branches.

## Dependency updates (Renovate)

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

### Vulnerability-driven PRs

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

## Branch protection (recommended)

`renovate.json` uses `internalChecksFilter: "flexible"` together with
`minimumReleaseAge: "15 days"`. This combination means:

- If a **matured older version** (≥ 15 days old) exists, Renovate opens a PR
  for that version and waits for the newest release to mature.
- If **no matured version** exists (e.g. a brand-new major that skipped
  patch releases), Renovate still opens a PR for the latest version, but
  posts a **`renovate/stability-days`** commit status of **`pending`** until
  the release ages past the window.

The "pending" status only *blocks merges* if branch protection is configured
to require it. Otherwise a maintainer could click "Merge" on a not-yet-matured
PR by mistake. To enforce the stability window:

1. Go to **Settings → Branches → Branch protection rules → Add rule**
   (or edit the existing rule for `main`).
2. Set **Branch name pattern** to `main`.
3. Enable **Require a pull request before merging**.
4. Enable **Require status checks to pass before merging** and then
   **Require branches to be up to date before merging**.
5. In the status-check search box, add (each appears in the list after it has
   run on at least one PR):
   - `Lint (hadolint)`
   - `Test`
   - `Govulncheck (Go vulnerability reachability)`
   - `Verify base image signatures`
   - `Trivy CVE scan`
   - `renovate/stability-days`  ← **this is what enforces `minimumReleaseAge`**
6. (Optional, recommended) Enable **Require signed commits** and
   **Do not allow bypassing the above settings**.
7. Click **Create** / **Save changes**.

Once `renovate/stability-days` is a required check, any Renovate PR whose
release has not yet matured will be un-mergeable (even by a human clicking
the button) until the age window elapses and Renovate flips the status to
`success` on its next run.

> Tip: status checks only appear in the search box after they have run at
> least once on a PR targeting `main`. If you can't find one, open a
> throwaway PR that touches the relevant workflow, let CI run, then come
> back and add it.
