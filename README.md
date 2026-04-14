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
   - **Commit statuses**: Read and write  (required — Renovate writes a
     `renovate/stability-days` commit status to track the `minimumReleaseAge`
     window; without this the run aborts with a misleading "Repository has
     changed during renovation" error)
2. Add it as a repository secret named `RENOVATE_TOKEN`.
3. The workflow then runs every 6 hours (at 00:00 / 06:00 / 12:00 / 18:00 UTC)
   and can also be triggered manually via the Actions tab, with an optional
   dry-run toggle.
