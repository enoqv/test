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
