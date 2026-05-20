# syntax=docker/dockerfile:1.22@sha256:4a43a54dd1fedceb30ba47e76cfcf2b47304f4161c0caeac2db1c61804ea3c91
FROM alpine:3.21@sha256:48b0309ca019d89d40f670aa1bc06e426dc0931948452e8491e3d65087abc07d

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
