[![Docker Pulls](https://img.shields.io/docker/pulls/frugan/php-legacy)](https://hub.docker.com/r/frugan/php-legacy)
[![Build Status](https://github.com/xaas-hub/docker-php-legacy/actions/workflows/ci.yml/badge.svg)](https://github.com/xaas-hub/docker-php-legacy/actions/workflows/ci.yml)
[![GitHub Release](https://img.shields.io/github/v/release/xaas-hub/docker-php-legacy)](https://github.com/xaas-hub/docker-php-legacy/releases)
[![License](https://img.shields.io/github/license/xaas-hub/docker-php-legacy)](https://github.com/xaas-hub/docker-php-legacy/blob/main/LICENSE)

# PHP legacy

PHP 5.6 and 7.1 to 8.1, branches PHP no longer supports, patched against
php2shell ([CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w),
[CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp)),
with the same runtime as [frugan/php](https://github.com/xaas-hub/docker-php):
Composer, WP-CLI, msmtp for `mail()`, Supercronic, extra locales, and a set of
extensions you switch on with an environment variable.

> [!WARNING]
> These images are a way to keep legacy sites running while they are moved to
> a supported PHP, not a place to stay. Nobody audits these branches any more:
> the fixes below are the ones someone backported, and what nobody backported
> stays open. Anything that can run on PHP 8.2 or later belongs on
> [frugan/php](https://github.com/xaas-hub/docker-php).

---

## Where PHP comes from

There are no official images for these branches, so PHP is compiled here, the
way [docker-library/php](https://github.com/docker-library/php) compiles it,
on Debian bookworm. The source of each branch is pinned by commit in
[`versions.json`](versions.json):

| PHP | Source                                    | php2shell fix                                   | Upload progress | OpenSSL |
| --- | ----------------------------------------- | ----------------------------------------------- | --------------- | ------- |
| 8.1 | Remi Collet's security tree               | official, in the tree                           | disabled        | 3       |
| 8.0 | Remi Collet's security tree               | official, in the tree                           | disabled        | 1.1.1w  |
| 7.4 | Remi Collet's security tree               | official, in the tree                           | disabled        | 1.1.1w  |
| 7.3 | Remi Collet's security tree               | community patch (`enhanced-remicollet`)         | works           | 1.1.1w  |
| 7.2 | Remi Collet's security tree               | community patch (`enhanced-remicollet`)         | works           | 1.1.1w  |
| 7.1 | Remi Collet's security tree               | community patch (`enhanced-remicollet`)         | works           | 1.1.1w  |
| 5.6 | Remi Collet's security tree (OpenSSL 1.1) | community patch (`enhanced-remicollet`)         | works           | 1.1.1w  |

- **[remicollet/php-src-security](https://github.com/remicollet/php-src-security)**:
  the branches Remi Collet maintains for his RPM repository, with the security
  fixes of the supported branches backported to the end-of-life ones. For
  7.4, 8.0 and 8.1 it already contains the php2shell fix by Arnaud Le Blanc,
  the one of php-src's `PHP-*-CVE-2026-109618-109619` branches, adapted to the
  tree: those branches lack every other fix since the branch went end of
  life.
- **[Anton-Barinov/php2shell-patches](https://github.com/Anton-Barinov/php2shell-patches)**:
  community backports of the fix, for the branches that have no official one.
  [`patches/`](patches) holds verbatim copies, as of commit `20bbe5f`. They are
  not reviewed by the PHP Group.
- **php-src commits a branch never received**, in
  [`patches/compat/`](patches/compat), only where today's compilers need them:
  5.6 gets the arm64 fix of `ZEND_SIGNED_MULTIPLY_LONG` that 7.0 got in 2016.
- **7.0 is not built.** The only patch for it targets the 7.0.33 release,
  which lacks every fix since December 2018, and as of `20bbe5f` it crashes
  PHP when memory runs out: `zend_alloc.c` calls `zend_get_executed_filename_ex()`
  without including `zend_execute.h`, so the pointer it returns is truncated.
  It comes back once a patch for Remi's 7.0 tree exists.
- **OpenSSL 1.1.1w**: ext/openssl only builds against OpenSSL 3 from PHP 8.1,
  so the older branches link an OpenSSL 1.1.1w built here, which no longer
  gets public fixes either. The rest of the system (curl, libpq) uses Debian's
  OpenSSL 3.

### What the fix changes

All variants of the fix make PHP stop the process when it runs out of memory,
instead of unwinding the request:

- a request over `memory_limit` ends with the fatal error on stderr and the
  FPM worker exits: no shutdown functions, no destructors, no error page from
  the application. The web server answers 502, and FPM starts a new worker.
- on 7.4, 8.0 and 8.1 the official fix turns the session upload progress off
  (`session.upload_progress.enabled` has no effect); on the other branches the
  community patch fixes it and keeps it working.

Raise `memory_limit` where a site used to hit it.

## What is in the image

|                                                                  |                                                                    |
| ---------------------------------------------------------------- | ------------------------------------------------------------------ |
| [Composer](https://getcomposer.org)                              | `composer`: 2.2 LTS on PHP < 7.2.5, the latest 2.x from there      |
| [WP-CLI](https://wp-cli.org)                                     | `wp`, with [`wp profile`](https://developer.wordpress.org/cli/commands/profile/) preinstalled |
| [msmtp](https://marlam.de/msmtp/)                                | `sendmail_path`, configured from `MSMTP_*`                         |
| [Supercronic](https://github.com/aptible/supercronic)            | cron for containers                                                |
| [install-php-extensions](https://github.com/mlocati/docker-php-extension-installer) | for images built `FROM` this one                |
| git, unzip, patch, less, curl, tzdata, locales                   | what Composer and WP-CLI expect to find                            |

Extensions always enabled: bcmath, exif, gd, mysqli, opcache, pdo_mysql,
zip, plus sodium from 7.2 on, intl from 7.4 on, and those every build of PHP
has. intl is missing before 7.4 because its sources do not build against the
ICU of bookworm.

Optional, enabled with `PHP_EXTENSIONS`: apcu, bz2, calendar, gettext, gmp,
igbinary, imagick, ldap, mcrypt, memcached, msgpack, pcntl, pdo_pgsql, pgsql,
redis, soap, sockets, tidy, xsl, each in the last release that supports the
branch. The `-dev` images add Xdebug: 3.x, loaded with `XDEBUG_MODE=off`,
from 7.2 on; 2.x before, where `XDEBUG_MODE` has no effect.

`php.ini` is `php.ini-production`, with `expose_php = Off`.

## Available tags

The same images, with the same tags, are published to two registries: use
either.

| Registry        | Image                                                                                                   |
| --------------- | ------------------------------------------------------------------------------------------------------- |
| Docker Hub      | [`frugan/php-legacy`](https://hub.docker.com/r/frugan/php-legacy)                                       |
| GitHub Packages | [`ghcr.io/xaas-hub/php-legacy`](https://github.com/orgs/xaas-hub/packages/container/package/php-legacy) |

```text
frugan/php-legacy:<php>-<variant>[-dev][-v<release>]
ghcr.io/xaas-hub/php-legacy:<same>
```

| Tag                | Content                                                       |
| ------------------ | ------------------------------------------------------------- |
| `7.4-fpm`          | PHP 7.4, latest release of this image: updated daily          |
| `7.4.33-fpm`       | the same image: these branches get no new PHP releases        |
| `7.4-fpm-v1.2.3`   | the image as of release 1.2.3, never rebuilt                  |
| `7.4-fpm-dev`      | the same three forms, with Xdebug                             |

PHP: `5.6`, `7.1`, `7.2`, `7.3`, `7.4`, `8.0`, `8.1`. Variants: `fpm`,
`cli`. Platforms: `linux/amd64`, `linux/arm64`. There is no `latest`.

The rolling tags are the ones to run: a Debian security update reaches them
within a day, and a new backport as soon as a release of this repository
picks it up.

## Quick start

```yaml
services:
  php:
    image: frugan/php-legacy:7.4-fpm
    init: true
    environment:
      APP_ENV: production
      USER_ID: 1000          # your uid on the host: files written by PHP are yours
      GROUP_ID: 1000
      PHP_EXTENSIONS: apcu,imagick,redis
      PHP_INI_MEMORY_LIMIT: 256M
      PHP_INI_UPLOAD_MAX_FILESIZE: 64M
      PHP_INI_POST_MAX_SIZE: 64M
      FPM_POOL_PM__MAX_CHILDREN: 20
      MSMTP_HOST: smtp.example.com
      MSMTP_USER: noreply@example.com
      MSMTP_PASSWORD_FILE: /run/secrets/smtp_password
    secrets:
      - smtp_password
    volumes:
      - ./html:/var/www/html

secrets:
  smtp_password:
    file: ./secrets/smtp_password
```

FPM listens on port 9000, like the official images: point nginx, Caddy or
Traefik there.

Commands inside a running container:

```bash
docker compose exec -u www-data php wp plugin list
docker compose exec -u www-data php composer install
```

`-u www-data` matters: `docker exec` does not go through the entry point and
runs as root otherwise.

## Configuration

Everything is read at container start: change the environment and recreate
the container. The variables are those of
[frugan/php](https://github.com/xaas-hub/docker-php#configuration), with the
differences noted below.

### Extensions

| Variable         | Default |                                                        |
| ---------------- | ------- | ------------------------------------------------------ |
| `PHP_EXTENSIONS` |         | optional extensions, separated by commas or spaces     |

`redis` and `memcached` bring `igbinary` and `msgpack` with them. An extension
that is not in the image stops the container with the list of the available
ones. For anything else, build on top of this image:

```dockerfile
FROM frugan/php-legacy:7.4-fpm
RUN install-php-extensions mongodb
```

### php.ini and FPM pool

| Variable          |                                                               |
| ----------------- | ------------------------------------------------------------- |
| `PHP_INI_<NAME>`  | any php.ini directive                                         |
| `FPM_POOL_<NAME>` | any directive of the `www` pool (fpm images)                  |

`<NAME>` is the directive in upper case, with `__` for the dot:

```text
PHP_INI_MEMORY_LIMIT=256M                 memory_limit = "256M"
PHP_INI_DATE__TIMEZONE=Europe/Rome        date.timezone = "Europe/Rome"
FPM_POOL_PM=static                        pm = "static"
FPM_POOL_PM__MAX_CHILDREN=20              pm.max_children = "20"
```

Values may not contain double quotes or newlines. `PHP_INI_DIR` and
`PHP_INI_SCAN_DIR` are not directives. Array directives such as
`php_admin_value[...]` have no variable form: mount a file in
`/usr/local/etc/php-fpm.d/` or `/usr/local/etc/php/conf.d/`. A directive the
branch does not know is an error for FPM and is ignored by PHP.

A `PHP_INI_*` or `FPM_POOL_*` variable set to an empty value is written too,
as `directive = ""`: that is how a directive is cleared
(`PHP_INI_DISABLE_FUNCTIONS=`). In a compose file, `${MEMORY_LIMIT}` left
unset therefore clears `memory_limit` instead of keeping the default: write
`${MEMORY_LIMIT:-128M}`.

### Environments and .user.ini

| Variable  | Default      |                                                     |
| --------- | ------------ | --------------------------------------------------- |
| `APP_ENV` | `production` | `production`, `staging`, `develop`, anything else   |

In production PHP reads the standard `.user.ini` (cached for 300 seconds). In
any other environment it reads `.user-<APP_ENV>.ini` instead, with
`user_ini.cache_ttl = 0` so that edits apply on the next request; set
`PHP_INI_USER_INI__CACHE_TTL` for another value.

The image never sets `APP_ENV` in the environment itself: Laravel's `.env`
keeps working when the variable is not passed. When it is, FPM hands it to the
workers like every other variable (`clear_env = no`, as in the official
images).

### Users and permissions

| Variable              | Default                     |                                       |
| --------------------- | --------------------------- | ------------------------------------- |
| `USER_ID`, `GROUP_ID` |                             | ids www-data takes at start           |
| `EXEC_USER`           | `www-data` (cli), empty (fpm) | user the command runs as            |

**Default: remapping.** The container starts as root, gives `www-data` the
ids in `USER_ID` and `GROUP_ID`, and FPM runs its workers as `www-data`: what
PHP writes on a bind mount belongs to your user on the host. The cli images
also run their command as `www-data`; `EXEC_USER=` runs it as root.

**Alternative: rootless.** Start the container with `user: "1000:1000"` (or
`--user`): nothing runs as root, the ids are the container's own, and
`USER_ID`, `GROUP_ID`, `EXEC_USER` and `LOCALES` are ignored. With
`read_only: true`, give it a writable `/run/docker-php`:

```yaml
    user: "1000:1000"
    read_only: true
    tmpfs:
      - /run/docker-php
      - /tmp
```

### Mail (msmtp)

| Variable              | Default         |                                                   |
| --------------------- | --------------- | ------------------------------------------------- |
| `MSMTP_HOST`          |                 | SMTP server; nothing is generated without it      |
| `MSMTP_PORT`          | `587`           |                                                   |
| `MSMTP_TLS`           | `starttls`      | `starttls`, `on` (implicit, default on port 465), `off` |
| `MSMTP_TLS_CERTCHECK` | `on`            |                                                   |
| `MSMTP_USER`          |                 | enables authentication                            |
| `MSMTP_PASSWORD_FILE` |                 | file holding the password, e.g. a Docker secret   |
| `MSMTP_PASSWORD`      |                 | the password itself, when a file is not an option |
| `MSMTP_FROM`          |                 | envelope sender, when PHP does not pass one       |
| `MSMTP_LOGFILE`       |                 | `-` logs every message to the container output    |

`sendmail_path` is `/usr/bin/msmtp -t`, which reads `/etc/msmtprc`. The
generated file is readable by root and `www-data` only, and `MSMTP_PASSWORD`
is removed from the environment before PHP starts.

### Cron (Supercronic)

| Variable              | Default        |                                          |
| --------------------- | -------------- | ---------------------------------------- |
| `SUPERCRONIC_ENABLED` |                | start Supercronic next to the command    |
| `SUPERCRONIC_CRONTAB` | `/etc/crontab` |                                          |
| `SUPERCRONIC_FLAGS`   |                | e.g. `-json`, `-split-logs`, `-overlapping` |

Jobs run as `www-data`. As in frugan/php, a separate container from the cli
image is the cleaner setup:

```yaml
  cron:
    image: frugan/php-legacy:7.4-cli
    init: true
    restart: unless-stopped
    command: ["supercronic", "/etc/crontab"]
    environment:
      USER_ID: 1000
      GROUP_ID: 1000
    volumes:
      - ./html:/var/www/html
      - ./crontab:/etc/crontab:ro
```

### Locales

| Variable  |                                                                  |
| --------- | ---------------------------------------------------------------- |
| `LOCALES` | `it_IT.UTF-8, de_DE.UTF-8`, full lines such as `en_US ISO-8859-1`, or `all` |

Generated at start, only when the list changes. Rootless containers cannot
generate them: build them in with `--build-arg LOCALES="it_IT.UTF-8"`.

### Hooks

Files `/docker-entrypoint.d/*.sh` are sourced in order after the steps above
and before the command, as root unless the container is rootless.

### Healthcheck

The fpm images ship a `HEALTHCHECK` that asks the pool for `/ping` over
FastCGI, at the address in `FPM_POOL_LISTEN` (9000 by default). Unlike
frugan/php, the ping requests show up in the access log: FPM has no setting to
leave them out before 8.2.

## Building

```bash
docker build --build-arg PHP_VERSION=5.6 --build-arg PHP_VARIANT=cli \
  --target cli-dev -t php-legacy:5.6-cli-dev .
```

| Argument                  | Default                                  |
| ------------------------- | ---------------------------------------- |
| `PHP_VERSION`             | `8.1`; a key of `versions.json`          |
| `PHP_VARIANT`             | `fpm`; must match the target             |
| `BASE_IMAGE`              | `debian:bookworm-slim`                   |
| `PHP_EXTENSIONS_CORE`     | the always enabled extensions            |
| `PHP_EXTENSIONS_OPTIONAL` | the ones `PHP_EXTENSIONS` enables        |
| `LOCALES`                 | locales generated at build time          |

Targets: `fpm` (default), `fpm-dev`, `cli`, `cli-dev`. Compiling PHP takes
several minutes per branch and architecture. The end-to-end test runs against
any of them, and checks that the php2shell fix is in:

```bash
tests/smoke.sh php-legacy:5.6-cli-dev cli-dev
```

## Release and publishing

Every merge to `main` goes through semantic-release: the commit types decide
the version (see [CONTRIBUTING](.github/CONTRIBUTING.md)), and the release
publishes all images with their `-v` tags and refreshes the rolling ones.

A fix to PHP reaches the images through a commit that moves a pin in
`versions.json` or updates a file in `patches/`, and the release that
follows. Every day the Debian base image is checked, and when it moved all
images are rebuilt from the latest release, tested and republished. Once a
week everything is rebuilt anyway, for Composer, install-php-extensions and
the PECL extensions.

## Contributing

For your contributions please use:

- [Conventional Commits](https://www.conventionalcommits.org)
- [Pull request workflow](https://docs.github.com/en/get-started/exploring-projects-on-github/contributing-to-a-project)

See [CONTRIBUTING](.github/CONTRIBUTING.md) for detailed guidelines.

## Sponsor

[<img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" width="200" alt="Buy Me A Coffee">](https://buymeacoff.ee/frugan)

## License

Copyright (c) 2026 [Frugan](https://frugan.it). [MIT](https://choosealicense.com/licenses/mit/),
see the [LICENSE](LICENSE) file.

The files in `patches/` derive from php-src and are under the
[PHP License 3.01](https://www.php.net/license/3_01.txt); those in
`build/docker-library/` come from docker-library/php, under its
[MIT license](build/docker-library/LICENSE). PHP, OpenSSL, Composer, WP-CLI,
msmtp, Supercronic and the bundled extensions keep their own licenses.
