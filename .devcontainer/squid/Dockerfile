# syntax=docker/dockerfile:1.22
FROM ubuntu/squid:6.6-24.04_edge

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
      inotify-tools \
      curl \
      ca-certificates \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/squid-entrypoint.sh
RUN chmod +x /usr/local/bin/squid-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/squid-entrypoint.sh"]
