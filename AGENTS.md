# AGENTS.md

Instructions for AI agents working on this repository. Everything a human
contributor needs is in [CONTRIBUTING](.github/CONTRIBUTING.md): read it, this
file does not repeat it.

This repository is the end-of-life sibling of
[xaas-hub/docker-php](https://github.com/xaas-hub/docker-php): same runtime
layer, same tags, but PHP is compiled here because no official image exists
for these branches.

## Hard rules

- **No PHP code of our own.** PHP comes from the commit pinned in
  `versions.json`, plus at most one file from `patches/`. A fix that is not
  in Remi Collet's security tree or in Anton-Barinov/php2shell-patches does
  not belong here: say so instead of writing it.
- **`patches/` are verbatim copies** of Anton-Barinov/php2shell-patches, at
  the commit named in the README. Never edit one: update it from upstream, and
  check that it still applies with `--fuzz=0`.
- **Sources are pinned by full commit SHA**, never by branch or tag, and every
  download carries a checksum.
- **The runtime layer follows docker-php.** `rootfs/`, the stages from `base`
  on and `tests/smoke.sh` stay as close to docker-php as the old branches
  allow: a difference needs a version check and a comment saying why.
- **Every init step must work as root and rootless**, and be idempotent: it
  runs at every start, also of a restarted container. Root-only work (user
  remapping, locales) must degrade to a log line without root, never fail.
- **Secrets never reach PHP or the logs.** `MSMTP_PASSWORD` is unset in
  `50-msmtp.sh`; any new secret variable needs the same treatment and a
  `_FILE` variant.
- **Do not set `APP_ENV` in the image**: Laravel's `.env` must keep winning
  when the variable is not passed.
- **Never read `.env`.** Only `.env.dist` is tracked.
- **Do not edit `CHANGELOG.md`.** semantic-release writes it from the commit
  log.
- Renaming or removing an environment variable, a tag, a build argument or a
  PHP branch is a breaking change: say so in the commit footer.

## Commands

Everything runs in Docker. If you cannot run it, say which commands have to be
run and what output to look for.

```bash
docker build --build-arg PHP_VERSION=7.4 --build-arg PHP_VARIANT=fpm --target fpm -t php-legacy:local .
tests/smoke.sh php-legacy:local fpm
```

Lint as described in the header of `.megalinter.yml`, which mirrors `ci.yml`.

## Conventions

- Code, comments and commit messages in English. Comments explain why, not
  what.
- Conventional Commits, plus the `deps` type: the type decides the release
  (see CONTRIBUTING). Body lines up to 150 characters.
- Shell scripts are bash, must pass `shellcheck -x` and are indented with
  tabs, like the existing ones.
- A difference between PHP branches is a version check (`php_at_least` in
  `build/build-php.sh`, `PHP_VERSION_ID` elsewhere), never a file per branch.
- Environment variables: features use their own prefix (`MSMTP_`,
  `SUPERCRONIC_`), directives go through the generic `PHP_INI_` and
  `FPM_POOL_` mapping in `env_to_ini`. Do not add a dedicated variable for a
  single php.ini directive.
- A new variable or behaviour comes with an assertion in `tests/smoke.sh` and
  a line in the README tables.
- A new optional extension is a word in `PHP_EXTENSIONS_OPTIONAL` and must
  install on every branch; if it is compiled against igbinary or msgpack, add
  it to `PHP_EXTENSION_DEPS` in `init.d/30-php.sh`.
- Pinned downloads (OpenSSL, the PEAR installer, Supercronic, WP-CLI) carry
  their checksum: bump both.

## Private notes

`agents/` is gitignored. If your checkout has it, it holds the maintainer's
notes: read what is relevant to the task, never reference it from versioned
files.
