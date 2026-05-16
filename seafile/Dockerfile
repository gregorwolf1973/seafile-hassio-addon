ARG BUILD_FROM
FROM seafileltd/seafile-mc:latest

# Install MariaDB server and helper tools
RUN apt-get update && apt-get install -y --no-install-recommends \
        mariadb-server \
        curl \
        jq \
        ca-certificates \
        openssl \
    && rm -rf /var/lib/apt/lists/*

# Install bashio for HA config access
ARG BASHIO_VERSION=0.16.2
RUN mkdir -p /tmp/bashio \
    && curl -J -L -o /tmp/bashio.tar.gz \
        "https://github.com/hassio-addons/bashio/archive/v${BASHIO_VERSION}.tar.gz" \
    && tar zxvf /tmp/bashio.tar.gz --strip 1 -C /tmp/bashio \
    && mv /tmp/bashio/lib /usr/lib/bashio \
    && ln -s /usr/lib/bashio/bashio /usr/bin/bashio \
    && rm -rf /tmp/bashio /tmp/bashio.tar.gz

# Ensure MariaDB runtime directories exist with correct ownership
RUN mkdir -p /var/run/mysqld /var/lib/mysql \
    && chown -R mysql:mysql /var/run/mysqld /var/lib/mysql

COPY run.sh /run.sh
COPY start-mariadb.sh /start-mariadb.sh
RUN chmod +x /run.sh /start-mariadb.sh

EXPOSE 80

CMD ["/run.sh"]
