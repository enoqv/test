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

## Devcontainer (Claude Code sandbox)

The `.devcontainer/` directory provides a sandboxed development container
modelled on the [official Claude Code reference devcontainer](https://code.claude.com/docs/en/devcontainer)
so you can safely run `claude --dangerously-skip-permissions`.

Differences vs. the reference setup:

- **Squid proxy for domain filtering** instead of the `init-firewall.sh`
  iptables/ipset allowlist. The `dev` service is attached to an `internal:
  true` Docker network with **no route to the internet**; the `squid`
  service is the sole egress and enforces a domain allowlist.
- **Dynamic allowlist**: edit
  [`.devcontainer/squid/allowed-domains.txt`](.devcontainer/squid/allowed-domains.txt)
  and squid auto-reloads via an inotify watcher (no container restart).
  Force a reload with `sudo reload-squid.sh` from inside the dev container.
- **`tmux` + `zellij`** are both preinstalled so detached Claude sessions
  survive terminal disconnects inside the sandbox. Zellij ships with the
  [shared config](.devcontainer/zellij/config.kdl) (catppuccin-mocha theme,
  Vim-style keybinds, session serialization).
- **Native Claude Code installer** — the image runs
  `curl -fsSL https://claude.ai/install.sh | bash`, so there's no Node.js
  base image or npm plumbing. Go toolchain version is derived from
  `go.mod`.
- **Pre-installed plugins** — `postCreateCommand` runs
  [`.devcontainer/claude-setup.sh`](.devcontainer/claude-setup.sh), which
  installs `context7@claude-plugins-official` and
  `superpowers@claude-plugins-official` by default. Add or remove entries
  in [`.devcontainer/claude/plugins.txt`](.devcontainer/claude/plugins.txt),
  [`.devcontainer/claude/marketplaces.txt`](.devcontainer/claude/marketplaces.txt),
  [`.devcontainer/claude/mcp-servers.json`](.devcontainer/claude/mcp-servers.json),
  or drop skills under `.devcontainer/claude/skills/`.

### Usage

#### VS Code

1. Install VS Code + the Dev Containers extension.
2. Open the repo and choose **Reopen in Container**.
3. Once the container is built, open a terminal and run `claude` to log in.

#### `devcontainer` CLI (no VS Code)

Install the [`@devcontainers/cli`](https://github.com/devcontainers/cli)
(`npm i -g @devcontainers/cli`), then from the repo root:

```sh
# Build and start (or rebuild from scratch) the devcontainer stack.
devcontainer up --remove-existing-container --workspace-folder .

# Drop into the container as the `dever` user.
devcontainer exec --workspace-folder . bash

# Inside the container, start Zellij (or tmux) and then Claude.
zellij            # preinstalled with the shared config
claude            # auto-login flow
```

#### Managing the allowlist

To allow a new domain: edit
`.devcontainer/squid/allowed-domains.txt`, save, wait ~1s
(or run `sudo reload-squid.sh`), and retry the request.

## Repo setup & governance

One-time setup docs (moved out of this README to keep it focused on
day-to-day development):

- [`docs/renovate.md`](docs/renovate.md) — self-hosted Renovate workflow,
  `RENOVATE_TOKEN` PAT permissions, and the two vulnerability-alert
  channels (GitHub Dependabot alerts + OSV).
- [`docs/branch-protection.md`](docs/branch-protection.md) — required
  status checks for `main`, including the `renovate/stability-days`
  gate that enforces `minimumReleaseAge`.
