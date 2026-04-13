# syntax=docker/dockerfile:1.7

# ---- Build stage ----
FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS builder

ARG TARGETOS
ARG TARGETARCH

WORKDIR /src

# Cache go modules
COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags="-s -w" -o /out/server ./cmd/server

# ---- Runtime stage ----
FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /app
COPY --from=builder /out/server /app/server
COPY --from=builder /src/web /app/web

ENV WEB_DIR=/app/web

USER nonroot:nonroot
EXPOSE 8080

ENTRYPOINT ["/app/server"]
