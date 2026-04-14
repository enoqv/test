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
2. Add it as a repository secret named `RENOVATE_TOKEN`.
3. The workflow then runs every 6 hours (at 00:00 / 06:00 / 12:00 / 18:00 UTC)
   and can also be triggered manually via the Actions tab, with an optional
   dry-run toggle.

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
