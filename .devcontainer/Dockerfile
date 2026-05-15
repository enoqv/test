# syntax=docker/dockerfile:1.23@sha256:2780b5c3bab67f1f76c781860de469442999ed1a0d7992a5efdf2cffc0e3d769
# Modeled on https://github.com/anthropics/claude-code/blob/main/.devcontainer/Dockerfile
# but rebased on debian:bookworm-slim — Claude Code now ships as a native
# binary (https://code.claude.com/docs/en/installation), so the Node.js
# base image that the reference uses is no longer needed.
FROM debian:bookworm-slim

ARG TZ
ENV TZ="$TZ"
ENV DEBIAN_FRONTEND=noninteractive

# Install basic development tools.
# tmux/zellij are included so `claude --dangerously-skip-permissions`
# sessions can be detached/reattached safely inside the sandboxed
# devcontainer.
#
# debian:*-slim strips `/usr/share/doc/*` via a `path-exclude` drop-in
# at /etc/dpkg/dpkg.cfg.d/docker, which would delete fzf's shell
# integration scripts (key-bindings.zsh, completion.zsh) and cause zsh
# to log "no such file or directory" warnings on every login. dpkg
# reads these drop-ins in lexical order and `path-include` only
# overrides a prior `path-exclude`, so the filename has to sort AFTER
# the base image's `docker` file.
RUN echo 'path-include=/usr/share/doc/fzf/examples/*' \
      > /etc/dpkg/dpkg.cfg.d/zz-fzf-examples && \
    apt-get update && apt-get install -y --no-install-recommends \
    less \
    git \
    openssh-client \
    procps \
    sudo \
    fzf \
    zsh \
    man-db \
    unzip \
    gnupg2 \
    iptables \
    ipset \
    iproute2 \
    dnsutils \
    aggregate \
    jq \
    nano \
    vim \
    tmux \
    ca-certificates \
    curl \
    wget \
    locales \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Generate the en_US.UTF-8 locale so shells don't spit
# `setlocale: LC_ALL: cannot change locale (en_US.UTF-8)` warnings.
RUN sed -i 's/^# *\(en_US\.UTF-8\)/\1/' /etc/locale.gen && \
    locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Create the unprivileged `dever` user that Claude Code / the devcontainer
# runs as. Provisioned manually because we're on a plain debian base.
ARG USERNAME=dever
ARG USER_UID=1000
ARG USER_GID=${USER_UID}
RUN groupadd --gid ${USER_GID} ${USERNAME} && \
    useradd --uid ${USER_UID} --gid ${USER_GID} -m --shell /bin/zsh ${USERNAME} && \
    echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} && \
    chmod 0440 /etc/sudoers.d/${USERNAME}

# Node.js — many Claude Code plugins, MCP servers, and dev tools ship
# as npm packages and need `node` / `npx` on PATH. Pulled straight from
# the official https://nodejs.org/dist/ binary tarballs (the same source
# that fnm, nvm, and NodeSource all mirror). Pin a full semver so the
# image is reproducible; Renovate can bump this ARG.
ARG NODE_VERSION=24.15.0
RUN ARCH=$(dpkg --print-architecture) && \
    case "${ARCH}" in \
      amd64) NODE_ARCH=x64 ;; \
      arm64) NODE_ARCH=arm64 ;; \
      *) echo "unsupported architecture for Node.js: ${ARCH}" >&2; exit 1 ;; \
    esac && \
    wget -qO /tmp/node.tar.gz "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.gz" && \
    tar -xzf /tmp/node.tar.gz -C /usr/local --strip-components=1 \
      --exclude='*/LICENSE' --exclude='*/README.md' --exclude='*/CHANGELOG.md' && \
    rm /tmp/node.tar.gz && \
    node --version && npm --version

# Go toolchain for this project. The version is derived from go.mod so the
# devcontainer stays in sync with the project's declared Go version.
COPY go.mod /tmp/go.mod
RUN ARCH=$(dpkg --print-architecture) && \
    GO_VERSION="$(awk '/^go [0-9]+\.[0-9]+/ {print $2; exit}' /tmp/go.mod)" && \
    [ -n "${GO_VERSION}" ] || { echo "failed to read go version from go.mod" >&2; exit 1; } && \
    echo "installing Go ${GO_VERSION} for ${ARCH}" && \
    wget -qO /tmp/go.tar.gz "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm /tmp/go.tar.gz /tmp/go.mod
ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOPATH=/home/dever/go
ENV GOCACHE=/home/dever/.cache/go-build

# Persist bash history.
RUN mkdir /commandhistory && \
    touch /commandhistory/.bash_history && \
    chown -R ${USERNAME}:${USERNAME} /commandhistory

# Create workspace and config directories and set permissions
RUN mkdir -p /workspace /home/dever/.claude /home/dever/.local/bin /home/dever/go /home/dever/.cache/go-build /home/dever/.npm-global && \
    chown -R ${USERNAME}:${USERNAME} /workspace /home/dever/.claude /home/dever/.local /home/dever/go /home/dever/.cache /home/dever/.npm-global

WORKDIR /workspace

ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
    wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
    dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
    rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# zellij terminal multiplexer (modern alternative to tmux). Upstream
# ships static musl binaries, so there's no apt package to track.
ARG ZELLIJ_VERSION=0.43.1
RUN ARCH=$(dpkg --print-architecture) && \
    case "${ARCH}" in \
      amd64) ZELLIJ_ARCH=x86_64-unknown-linux-musl ;; \
      arm64) ZELLIJ_ARCH=aarch64-unknown-linux-musl ;; \
      *) echo "unsupported architecture for zellij: ${ARCH}" >&2; exit 1 ;; \
    esac && \
    wget -qO /tmp/zellij.tar.gz "https://github.com/zellij-org/zellij/releases/download/v${ZELLIJ_VERSION}/zellij-${ZELLIJ_ARCH}.tar.gz" && \
    tar -xzf /tmp/zellij.tar.gz -C /usr/local/bin zellij && \
    chmod +x /usr/local/bin/zellij && \
    rm /tmp/zellij.tar.gz

# Zellij default config for the `dever` user. Mirrors
# ~/.config/zellij/config.kdl so a fresh container has Vim-style
# keybinds, catppuccin-mocha theme, session serialization, etc.
# Source: https://gist.github.com/enoqv/707aafdcacc2a80f4b9b7e891a5760c5
RUN mkdir -p /home/dever/.config/zellij && \
    chown -R ${USERNAME}:${USERNAME} /home/dever/.config
COPY --chown=${USERNAME}:${USERNAME} .devcontainer/zellij/config.kdl /home/dever/.config/zellij/config.kdl

# Switch to the unprivileged user for per-user installs.
USER ${USERNAME}

# The Claude Code native installer drops the binary in ~/.local/bin.
# npm is configured to install -g packages into ~/.npm-global so the
# `dever` user doesn't need sudo for `npm i -g <pkg>`.
ENV NPM_CONFIG_PREFIX=/home/dever/.npm-global
ENV PATH=/home/dever/.local/bin:/home/dever/.npm-global/bin:${PATH}:/home/dever/go/bin

# Default shell + editors.
ENV SHELL=/bin/zsh
ENV EDITOR=nano
ENV VISUAL=nano

# zsh-in-docker: powerline10k theme + fzf keybindings + persistent history.
# The fzf source lines are guarded with `[ -r ... ]` so the zshrc stays
# quiet if the examples directory is ever missing (e.g. debian-slim's
# `path-exclude=/usr/share/doc/*` stripping them before our
# path-include whitelist takes effect in a stale image).
ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
    -p git \
    -p fzf \
    -a "[ -r /usr/share/doc/fzf/examples/key-bindings.zsh ] && source /usr/share/doc/fzf/examples/key-bindings.zsh" \
    -a "[ -r /usr/share/doc/fzf/examples/completion.zsh ] && source /usr/share/doc/fzf/examples/completion.zsh" \
    -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
    -x

# Claude Code — native installer (per
# https://code.claude.com/docs/en/installation). The installer writes the
# binary to /home/dever/.local/bin/claude and auto-updates in the
# background at runtime, so we don't pin a version here.
RUN curl -fsSL https://claude.ai/install.sh | bash && \
    /home/dever/.local/bin/claude --version

# Copy proxy init + squid reload helpers. Replaces the reference
# init-firewall.sh domain-filtering approach with Squid-based filtering.
# Paths are relative to the build context (repo root).
USER root
COPY .devcontainer/init-proxy.sh /usr/local/bin/init-proxy.sh
COPY .devcontainer/reload-squid.sh /usr/local/bin/reload-squid.sh
RUN chmod +x /usr/local/bin/init-proxy.sh /usr/local/bin/reload-squid.sh && \
    printf '%s\n' \
      "${USERNAME} ALL=(root) NOPASSWD: /usr/local/bin/init-proxy.sh" \
      "${USERNAME} ALL=(root) NOPASSWD: /usr/local/bin/reload-squid.sh" \
      > /etc/sudoers.d/${USERNAME}-proxy && \
    chmod 0440 /etc/sudoers.d/${USERNAME}-proxy

ENV DEVCONTAINER=true

USER ${USERNAME}
