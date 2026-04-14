# syntax=docker/dockerfile:1.7@sha256:a57df69d0ea827fb7266491f2813635de6f17269be881f696fbfdf2d83dda33e

# ---- Build stage ----
FROM --platform=$BUILDPLATFORM golang:1.22-alpine@sha256:1699c10032ca2582ec89a24a1312d986a3f094aed3d5c1147b19880afe40e052 AS builder

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
FROM gcr.io/distroless/static-debian12:nonroot@sha256:a9329520abc449e3b14d5bc3a6ffae065bdde0f02667fa10880c49b35c109fd1

WORKDIR /app
COPY --from=builder /out/server /app/server
COPY --from=builder /src/web /app/web

ENV WEB_DIR=/app/web

USER nonroot:nonroot
EXPOSE 8080

ENTRYPOINT ["/app/server"]
