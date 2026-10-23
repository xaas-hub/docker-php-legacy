# syntax=docker/dockerfile:1

# PHP images for the end-of-life branches (5.6 to 8.1), patched against
# php2shell, with the runtime layer of xaas-hub/docker-php: Composer, WP-CLI,
# msmtp, Supercronic and a set of extensions that are enabled through the
# environment instead of a rebuild.
#
# There are no official images to build on for these branches, so the php stage
# compiles PHP the way docker-library/php does, from the source pinned in
# versions.json. Everything after it is the docker-php Dockerfile.
#
# Targets: cli, cli-dev, fpm, fpm-dev (the default). The -dev targets add
# Xdebug. PHP_VARIANT must match the target: fpm for fpm and fpm-dev, cli for
# cli and cli-dev.

ARG PHP_VERSION=8.1
ARG PHP_VARIANT=fpm
ARG DEBIAN_CODENAME=bookworm
# CI passes the reference pinned to the digest it resolved, so the label below
# records exactly what the image was built from and the daily check in ci.yml
# can tell whether Debian has moved since.
ARG BASE_IMAGE=debian:${DEBIAN_CODENAME}-slim

# Floating tags on purpose: the weekly rebuild in ci.yml picks up their fixes
# without a commit. Composer 2.2 is the LTS line that still runs on PHP < 7.2.5.
FROM composer:2 AS composer
FROM composer:2.2 AS composer-lts
FROM mlocati/php-extension-installer:2 AS ipe

FROM ${BASE_IMAGE} AS php

ARG PHP_VERSION
ARG PHP_VARIANT

# https://github.com/openssl/openssl/releases. Only the branches before 8.1 use
# it: see build/build-php.sh.
ARG OPENSSL_VERSION=1.1.1w
ARG OPENSSL_SHA256=cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8

# https://github.com/pear/pearweb_phars, the files pear.php.net serves.
ARG PEAR_PHAR_COMMIT=72aa5f771f56aaf826641b21159453f993e44450
ARG PEAR_PHAR_SHA256=a71349da29f1a6e3f0792695b167e582375a93c70c0e9d35e7c4675697c5f039

# From here to the end of the stage: the official images, as of the last
# Dockerfile docker-library/php published for each branch.

# prevent Debian's PHP packages from being installed
# https://github.com/docker-library/php/pull/542
RUN set -eux; \
    { \
        echo 'Package: php*'; \
        echo 'Pin: release *'; \
        echo 'Pin-Priority: -1'; \
    } > /etc/apt/preferences.d/no-debian-php

# dependencies required for running "phpize"
ENV PHPIZE_DEPS="autoconf dpkg-dev file g++ gcc libc-dev make pkg-config re2c"

# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        $PHPIZE_DEPS \
        ca-certificates \
        curl \
        xz-utils \
    ; \
    rm -rf /var/lib/apt/lists/*

ENV PHP_INI_DIR=/usr/local/etc/php
RUN set -eux; \
    mkdir -p "$PHP_INI_DIR/conf.d"; \
# allow running as an arbitrary user (https://github.com/docker-library/php/issues/743)
    [ ! -d /var/www/html ]; \
    mkdir -p /var/www/html; \
    chown www-data:www-data /var/www/html; \
    chmod 1777 /var/www/html

# https://github.com/docker-library/php/issues/272
ENV PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"
ENV PHP_CPPFLAGS="$PHP_CFLAGS"
ENV PHP_LDFLAGS="-Wl,-O1 -pie"

# The helper scripts of docker-library/php as of October 2020 (38ac479): the
# last ones that write extension=<name>.so, which PHP < 7.2 needs.
COPY build/docker-library/docker-php-source build/docker-library/docker-php-ext-* /usr/local/bin/
COPY build/docker-library/docker-php-entrypoint-${PHP_VARIANT} /usr/local/bin/docker-php-entrypoint

# Build dependencies are removed in the same layer, keeping the libraries the
# installed binaries link against. The build inputs are bind mounts, so they
# do not end up in the image. No pipefail, as in the official images: ldd and
# dpkg-query fail on some of the files they are given, which is expected.
# hadolint ignore=DL3008,DL4006,SC2046,SC2086
RUN --mount=type=bind,source=versions.json,target=/usr/src/legacy/versions.json \
    --mount=type=bind,source=patches,target=/usr/src/legacy/patches \
    --mount=type=bind,source=build/build-php.sh,target=/usr/src/legacy/build-php.sh \
    set -eux; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends jq; \
    apt-get install -y --no-install-recommends $(/usr/src/legacy/build-php.sh deps /usr/src/legacy); \
    /usr/src/legacy/build-php.sh build /usr/src/legacy; \
    apt-mark auto '.*' > /dev/null; \
    [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
# the package build-php.sh registers for its OpenSSL 1.1, before 8.1
    if dpkg-query -W openssl1.1-local > /dev/null 2>&1; then apt-mark manual openssl1.1-local; fi; \
    find /usr/local -type f -executable -exec ldd '{}' ';' \
        | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
        | sort -u \
        | xargs -rt dpkg-query --search \
        | awk 'sub(":$", "", $1) { print $1 }' \
        | sort -u \
        | xargs -r apt-mark manual \
    ; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*; \
    php --version

WORKDIR /var/www/html

FROM php AS base

ARG BASE_IMAGE
ARG TARGETARCH

# Enabled in every container.
ARG PHP_EXTENSIONS_CORE="bcmath exif gd intl mysqli opcache pdo_mysql zip"
# Compiled in, enabled through PHP_EXTENSIONS at container start.
ARG PHP_EXTENSIONS_OPTIONAL="apcu bz2 calendar gettext gmp igbinary imagick ldap mcrypt memcached msgpack pcntl pdo_pgsql pgsql redis soap sockets tidy xsl"

# https://github.com/aptible/supercronic/releases
ARG SUPERCRONIC_VERSION=0.2.51
ARG SUPERCRONIC_SHA256_AMD64=cc232108374e8e2b537045f2d5eaa1229f619db314c3ba6a14d38b35dc0aa123
ARG SUPERCRONIC_SHA256_ARM64=4ae22576a78223d8ccdf5f3b3660a5cbb5288416bf0ca96afc4a36d195932b94

# https://github.com/wp-cli/wp-cli/releases. The profile command has to match
# it: profile-command 2.1.6 and later require wp-cli 2.13.
ARG WP_CLI_VERSION=2.12.0
ARG WP_CLI_SHA512=be928f6b8ca1e8dfb9d2f4b75a13aa4aee0896f8a9a0a1c45cd5d2c98605e6172e6d014dda2e27f88c98befc16c040cbb2bd1bfa121510ea5cdf5f6a30fe8832
ARG WP_CLI_PROFILE_VERSION=2.1.5
# The last one that still runs on PHP < 7.2.24: 2.1.5 raised the requirement.
ARG WP_CLI_PROFILE_VERSION_LEGACY=2.1.4

# Locales generated at build time, same syntax as the LOCALES variable. The
# only way to have extra locales in a rootless container.
ARG LOCALES=""

LABEL org.opencontainers.image.title="php-legacy" \
      org.opencontainers.image.description="End-of-life PHP (5.6 to 8.1) patched against php2shell, with Composer, WP-CLI, msmtp, Supercronic and extensions enabled through the environment" \
      org.opencontainers.image.source="https://github.com/xaas-hub/docker-php-legacy" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.base.name="${BASE_IMAGE}"

ENV WP_CLI_PACKAGES_DIR=/usr/local/share/wp-cli/packages

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# libfcgi-bin: cgi-fcgi for the FPM healthcheck.
# util-linux: setpriv, to drop privileges without gosu.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        less \
        libfcgi-bin \
        locales \
        msmtp \
        ncurses-bin \
        patch \
        tzdata \
        unzip \
        util-linux \
    && rm -rf /var/lib/apt/lists/* \
    && command -v setpriv

COPY --from=composer /usr/bin/composer /usr/local/bin/composer
COPY --from=composer-lts /usr/bin/composer /usr/local/bin/composer-lts
COPY --from=ipe /usr/bin/install-php-extensions /usr/local/bin/

RUN if php -r 'exit(PHP_VERSION_ID < 70205 ? 0 : 1);'; then \
        mv -f /usr/local/bin/composer-lts /usr/local/bin/composer; \
    else \
        rm /usr/local/bin/composer-lts; \
    fi

# freetype-config, which gd needs before 7.4 and FreeType no longer ships.
COPY build/compat/freetype-config /usr/local/bin/

# Optional extensions are installed like the core ones, then their ini files
# are moved out of conf.d: docker-php-init loads the requested ones at start,
# in the order of their file names, which install-php-extensions chose so that
# igbinary and msgpack come before redis and memcached.
# intl is left out before 7.4: its sources do not build against the ICU of
# bookworm (70 and later changed BreakIterator::operator==).
# hadolint ignore=SC2086
RUN core="${PHP_EXTENSIONS_CORE}" \
    && if php -r 'exit(PHP_VERSION_ID < 70400 ? 0 : 1);'; then \
        core="$(tr ' ' '\n' <<<"$core" | grep -vx intl | paste -sd ' ')"; \
    fi \
    && install-php-extensions ${core} ${PHP_EXTENSIONS_OPTIONAL} \
    && mkdir -p "${PHP_INI_DIR}/available" \
    && for ext in ${PHP_EXTENSIONS_OPTIONAL}; do \
        ini=("${PHP_INI_DIR}"/conf.d/*-php-ext-"${ext}".ini); \
        test -f "${ini[0]}" || { echo "no ini file for ${ext}" >&2; exit 1; }; \
        mv "${ini[0]}" "${PHP_INI_DIR}/available/"; \
    done

# The download URL takes the arch name Docker uses, but the checksum is pinned
# per arch: an unknown TARGETARCH fails here instead of shipping an unchecked
# binary.
RUN case "${TARGETARCH}" in \
        amd64) sha256="${SUPERCRONIC_SHA256_AMD64}" ;; \
        arm64) sha256="${SUPERCRONIC_SHA256_ARM64}" ;; \
        *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSLo /usr/local/bin/supercronic \
        "https://github.com/aptible/supercronic/releases/download/v${SUPERCRONIC_VERSION}/supercronic-linux-${TARGETARCH}" \
    && echo "${sha256}  /usr/local/bin/supercronic" | sha256sum -c - \
    && chmod +x /usr/local/bin/supercronic

# Packages go to WP_CLI_PACKAGES_DIR instead of root's home, so www-data finds
# them too. wp-cli's bundled Composer needs more than the 128M of
# php.ini-production to resolve the package.
# wp-cli registers the package as a GitHub VCS repository, which Composer
# resolves through the GitHub API: unauthenticated, the IPs shared by CI
# runners hit its rate limit. The token is optional, local builds work without.
# It goes in as http-basic with the x-oauth-basic password, which is how
# Composer stores github-oauth tokens internally: the github-oauth key itself
# is validated, and the Composer bundled in wp-cli rejects the dotted token
# format GitHub Actions issues.
RUN --mount=type=secret,id=github_token,required=false \
    curl -fsSLo /usr/local/bin/wp \
        "https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar" \
    && echo "${WP_CLI_SHA512}  /usr/local/bin/wp" | sha512sum -c - \
    && chmod +x /usr/local/bin/wp \
    && if [ -s /run/secrets/github_token ]; then \
        COMPOSER_AUTH="$(printf '{"http-basic":{"github.com":{"username":"%s","password":"x-oauth-basic"}}}' "$(cat /run/secrets/github_token)")"; \
        export COMPOSER_AUTH; \
    fi \
    && profile_version="${WP_CLI_PROFILE_VERSION}" \
    && if php -r 'exit(PHP_VERSION_ID < 70224 ? 0 : 1);'; then \
        profile_version="${WP_CLI_PROFILE_VERSION_LEGACY}"; \
    fi \
    && php -d memory_limit=512M /usr/local/bin/wp package install \
        "wp-cli/profile-command:${profile_version}" --allow-root \
    && rm -rf /root/.wp-cli /root/.composer

COPY rootfs/ /

# - php.ini-production as the base: development settings belong in the
#   per-environment .user.ini files or in PHP_INI_* variables.
# - www-data gets a real home outside /var/www: usermod -u, run when USER_ID
#   is set, re-owns the whole home directory, which must not be the document
#   root on a bind mount.
# - /run/docker-php holds what docker-php-init generates. Sticky and world
#   writable, because a rootless container may run under any uid; the files
#   themselves are written root-owned and read-only whenever the container
#   starts as root. The links point there whether or not the targets exist
#   yet: PHP skips a dangling file in conf.d, and msmtp is only used once
#   MSMTP_HOST has generated its configuration.
RUN cp "${PHP_INI_DIR}/php.ini-production" "${PHP_INI_DIR}/php.ini" \
    && usermod -d /home/www-data www-data \
    && install -d -o www-data -g www-data -m 0755 /home/www-data \
    && install -d -m 1777 /run/docker-php /run/docker-php/fpm.d \
    && ln -s /run/docker-php/php.ini "${PHP_INI_DIR}/conf.d/zz-docker-php-runtime.ini" \
    && ln -sf /run/docker-php/msmtprc /etc/msmtprc \
    && install -d -m 0755 /docker-entrypoint.d \
    && if [ -n "${LOCALES}" ]; then docker-php-locales "${LOCALES}"; fi

ENTRYPOINT ["docker-php-init"]

FROM base AS cli

# Commands run as www-data: files written to bind mounts get the host user's
# ids once USER_ID and GROUP_ID are set. EXEC_USER= runs them as root.
ENV EXEC_USER=www-data

CMD ["php", "-a"]

FROM cli AS cli-dev

ENV XDEBUG_MODE=off

RUN install-php-extensions xdebug

FROM base AS fpm-base

# The master process stays root and the pool switches to www-data, so
# EXEC_USER stays empty here.
#
# The runtime pool file is included last, after zz-docker.conf. A missing match
# is only a warning for FPM. Unlike docker-php, the ping requests stay in the
# access log: access.suppress_path arrived in FPM 8.2.
RUN printf '\ninclude=/run/docker-php/fpm.d/*.conf\n' >>"${PHP_INI_DIR%/php}/php-fpm.conf" \
    && printf '%s\n' \
        '[www]' \
        'ping.path = /ping' \
        >"${PHP_INI_DIR%/php}/php-fpm.d/zzz-docker-php.conf"

# https://github.com/php/php-src/blob/17baa87faddc2550def3ae7314236826bc1b1398/sapi/fpm/php-fpm.8.in#L163
STOPSIGNAL SIGQUIT

EXPOSE 9000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["php-fpm-healthcheck"]

CMD ["php-fpm"]

FROM fpm-base AS fpm-dev

ENV XDEBUG_MODE=off

RUN install-php-extensions xdebug

# Last stage: the default target.
FROM fpm-base AS fpm
