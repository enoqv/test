# syntax=docker/dockerfile:1.22
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      squid \
      squidclient \
      inotify-tools \
      curl \
      ca-certificates \
      netcat-openbsd \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# The ubuntu `squid` package ships a default squid.conf that we replace
# via a bind-mount at runtime. Make sure the runtime directories exist.
RUN mkdir -p /var/log/squid /var/spool/squid /var/cache/squid /run/squid && \
    chown -R proxy:proxy /var/log/squid /var/spool/squid /var/cache/squid /run/squid

COPY entrypoint.sh /usr/local/bin/squid-entrypoint.sh
RUN chmod +x /usr/local/bin/squid-entrypoint.sh

EXPOSE 3128
ENTRYPOINT ["/usr/local/bin/squid-entrypoint.sh"]
