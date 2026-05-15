# syntax=docker/dockerfile:1.23@sha256:2780b5c3bab67f1f76c781860de469442999ed1a0d7992a5efdf2cffc0e3d769
FROM alpine:3.21

RUN apk add --no-cache \
      squid \
      inotify-tools \
      curl \
      ca-certificates \
      bash \
      netcat-openbsd

# Ensure runtime directories exist and are owned by the squid user that
# the `squid` package creates. On Alpine the effective user is `squid`
# (not `proxy` as on Debian).
RUN mkdir -p /var/log/squid /var/spool/squid /var/cache/squid /run/squid && \
    chown -R squid:squid /var/log/squid /var/spool/squid /var/cache/squid /run/squid

COPY entrypoint.sh /usr/local/bin/squid-entrypoint.sh
RUN chmod +x /usr/local/bin/squid-entrypoint.sh

EXPOSE 3128
ENTRYPOINT ["/usr/local/bin/squid-entrypoint.sh"]
