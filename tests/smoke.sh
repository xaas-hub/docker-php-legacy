#!/usr/bin/env bash
#
# End-to-end check of a built image, run by ci.yml on both architectures and
# usable locally:
#
#   tests/smoke.sh <image> <target>
#   tests/smoke.sh php:local fpm
#
# <target> is the build target the image comes from: cli, cli-dev, fpm or
# fpm-dev. Needs nothing but Docker: no network, no fixtures.

set -euo pipefail

image="${1:?usage: smoke.sh <image> <target>}"
target="${2:?usage: smoke.sh <image> <target>}"

case "$target" in
cli | cli-dev | fpm | fpm-dev) ;;
*) echo "unknown target: ${target}" >&2 && exit 2 ;;
esac

tmp="$(mktemp -d)"
containers=()
cleanup() {
	if [ "${#containers[@]}" -gt 0 ]; then
		docker rm -f "${containers[@]}" >/dev/null 2>&1 || true
	fi
	rm -rf "$tmp"
}
trap cleanup EXIT

fail() {
	echo "SMOKE FAILED: $*" >&2
	exit 1
}

pass() {
	echo "ok - $*"
}

# run [docker run options] -- command...
run() {
	local -a opts=()
	while [ "$1" != -- ]; do
		opts+=("$1")
		shift
	done
	shift
	docker run --rm "${opts[@]}" "$image" "$@"
}

expect() {
	local description="$1" expected="$2" actual="$3"
	[ "$actual" = "$expected" ] || fail "${description}: expected '${expected}', got '${actual}'"
	pass "$description"
}

expect_failure() {
	local description="$1"
	shift
	if run "$@" >/dev/null 2>&1; then
		fail "${description}: the container started"
	fi
	pass "$description"
}

has_module() {
	grep -qx "$1" <<<"$2"
}

wait_healthy() {
	local cid="$1" i
	for i in $(seq 30); do
		if docker exec "$cid" php-fpm-healthcheck >/dev/null 2>&1; then
			return 0
		fi
		sleep 1
	done
	docker logs "$cid" >&2 || true
	fail "FPM did not answer the healthcheck within ${i}s"
}

# --- PHP and extensions ------------------------------------------------------

version="$(run -- php -r 'echo PHP_VERSION;')"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || fail "unexpected PHP_VERSION: ${version}"
pass "PHP ${version}"
version_id="$(run -- php -r 'echo PHP_VERSION_ID;')"

core=(bcmath exif gd mysqli pdo_mysql zip "Zend OPcache")
# Bundled from 7.2 on.
if [ "$version_id" -ge 70200 ]; then
	core+=(sodium)
fi
# Older sources do not build against the ICU of the base image.
if [ "$version_id" -ge 70400 ]; then
	core+=(intl)
fi
modules="$(run -- php -m 2>&1)"
for module in "${core[@]}"; do
	has_module "$module" "$modules" || fail "core extension ${module} not loaded"
done
pass "core extensions loaded"
for module in apcu bz2 calendar gettext gmp igbinary imagick ldap mcrypt memcached msgpack pcntl pdo_pgsql pgsql redis soap sockets tidy xsl; do
	has_module "$module" "$modules" && fail "optional extension ${module} loaded by default"
done
pass "optional extensions off by default"

case "$target" in
*-dev) has_module xdebug "$modules" || fail "xdebug not loaded in ${target}" ;;
*) has_module xdebug "$modules" && fail "xdebug loaded in ${target}" ;;
esac
pass "xdebug only in the dev targets"

# Mixed separators on purpose. redis and memcached must pull in their
# serializers, or PHP warns that it cannot load them.
modules="$(run -e "PHP_EXTENSIONS=apcu, bz2 calendar;gettext gmp, imagick;ldap mcrypt memcached pcntl pdo_pgsql,pgsql,REDIS soap sockets,tidy xsl" -- php -m 2>&1)"
grep -qi warning <<<"$modules" && fail "warnings while loading extensions: ${modules}"
for module in apcu bz2 calendar gettext gmp igbinary imagick ldap mcrypt memcached msgpack pcntl pdo_pgsql pgsql redis soap sockets tidy xsl; do
	has_module "$module" "$modules" || fail "PHP_EXTENSIONS: ${module} not loaded"
done
pass "PHP_EXTENSIONS enables the optional extensions and their dependencies"

run -e PHP_EXTENSIONS=gd -- php -v >/dev/null 2>&1 || fail "PHP_EXTENSIONS=gd (a core one) must be accepted"
pass "PHP_EXTENSIONS accepts core extensions"
expect_failure "PHP_EXTENSIONS rejects an unknown extension" -e PHP_EXTENSIONS=nope -- php -v

# --- php2shell ------------------------------------------------------------------

# Every fix of CVE-2026-109618 makes running out of memory end the process
# instead of unwinding the request: without it the shutdown function runs.
oom="$(run -- php -d memory_limit=8M -r \
	'register_shutdown_function(function () { echo "shutdown ran"; }); str_repeat("x", 16 * 1024 * 1024);' 2>&1)" || true
grep -q 'Allowed memory size' <<<"$oom" || fail "php2shell: no out-of-memory error: ${oom}"
grep -q 'shutdown ran' <<<"$oom" && fail "php2shell: the request survived out of memory, the fix is missing"
pass "php2shell: out of memory ends the process"

# --- php.ini from the environment ----------------------------------------------

expect "PHP_INI_* sets directives" "321M 1" \
	"$(run -e PHP_INI_MEMORY_LIMIT=321M -e PHP_INI_OPCACHE__ENABLE_CLI=1 -- \
		php -r 'echo ini_get("memory_limit"), " ", ini_get("opcache.enable_cli");')"
expect_failure "PHP_INI_* rejects double quotes" -e 'PHP_INI_MEMORY_LIMIT=1"x' -- php -v
expect "sendmail_path points to msmtp" "/usr/bin/msmtp -t" \
	"$(run -- php -r 'echo ini_get("sendmail_path");')"
# var_export, not var_dump: Xdebug 2 (the -dev images before 7.2) prefixes
# var_dump output with the file and line.
expect "expose_php is off" "false" \
	"$(run -- php -r 'var_export((bool) ini_get("expose_php"));')"
expect "session upload progress is off" "false" \
	"$(run -- php -r 'var_export((bool) ini_get("session.upload_progress.enabled"));')"

user_ini='echo ini_get("user_ini.filename"), "|", ini_get("user_ini.cache_ttl");'
expect "production keeps .user.ini" ".user.ini|300" "$(run -- php -r "$user_ini")"
expect "APP_ENV selects .user-<env>.ini" ".user-develop.ini|0" \
	"$(run -e APP_ENV=develop -- php -r "$user_ini")"
expect "PHP_INI_USER_INI__CACHE_TTL overrides the default" ".user-staging.ini|60" \
	"$(run -e APP_ENV=staging -e PHP_INI_USER_INI__CACHE_TTL=60 -- php -r "$user_ini")"
expect_failure "APP_ENV rejects path characters" -e APP_ENV=../x -- php -v

# --- Tools ---------------------------------------------------------------------

run -e EXEC_USER=www-data -- composer --version >/dev/null || fail "composer"
pass "composer"
run -e EXEC_USER=www-data -- wp --version >/dev/null || fail "wp"
# `wp cli has-command` loads WordPress to resolve package commands: list the
# installed packages instead, which needs no installation.
run -e EXEC_USER=www-data -- wp package list --fields=name --format=csv | grep -qx wp-cli/profile-command ||
	fail "wp profile command missing"
pass "wp-cli with the profile command"

printf '* * * * * true\n' >"${tmp}/crontab"
chmod 0644 "${tmp}/crontab"
run -v "${tmp}/crontab:/tmp/crontab:ro" -- supercronic -test /tmp/crontab >/dev/null 2>&1 ||
	fail "supercronic -test"
pass "supercronic"

# The comm of the background process, owned by www-data.
# shellcheck disable=SC2016 # expanded in the container
supercronic_owner="$(run -v "${tmp}/crontab:/etc/crontab:ro" -e SUPERCRONIC_ENABLED=true -e EXEC_USER= -- \
	sh -c 'sleep 2; for p in /proc/[0-9]*; do [ "$(cat "$p/comm" 2>/dev/null)" = supercronic ] && stat -c %U "$p"; done')"
expect "SUPERCRONIC_ENABLED starts it as www-data" "www-data" "$supercronic_owner"
expect_failure "SUPERCRONIC_ENABLED without a crontab" -e SUPERCRONIC_ENABLED=true -e SUPERCRONIC_CRONTAB=/missing -- php -v

# --- msmtp -----------------------------------------------------------------------

msmtp_env=(-e MSMTP_HOST=smtp.example.com -e MSMTP_USER=me -e 'MSMTP_PASSWORD=p"w\x' -e MSMTP_FROM=me@example.com)
pretend="$(run "${msmtp_env[@]}" -e EXEC_USER=www-data -- msmtp --pretend 2>&1)" ||
	fail "msmtp --pretend as www-data: ${pretend}"
grep -q 'smtp.example.com' <<<"$pretend" || fail "msmtp does not use MSMTP_HOST: ${pretend}"
grep -Eq 'tls_starttls *= *on' <<<"$pretend" || fail "msmtp does not default to STARTTLS on 587: ${pretend}"
pass "MSMTP_* generates a configuration www-data can read"
expect "msmtprc is private to root and www-data" "root:www-data 640" \
	"$(run "${msmtp_env[@]}" -e EXEC_USER= -- stat -Lc '%U:%G %a' /etc/msmtprc)"
expect "MSMTP_PASSWORD does not reach PHP" "false" \
	"$(run "${msmtp_env[@]}" -- php -r 'var_export(getenv("MSMTP_PASSWORD"));')"

# --- Locales -------------------------------------------------------------------

locales="$(run -e "LOCALES=it_IT.UTF-8, de_DE.UTF-8 UTF-8" -e EXEC_USER= -- locale -a)"
if ! grep -qx it_IT.utf8 <<<"$locales" || ! grep -qx de_DE.utf8 <<<"$locales"; then
	fail "LOCALES: got ${locales}"
fi
pass "LOCALES"
expect_failure "LOCALES rejects an unsupported locale" -e LOCALES=xx_XX.UTF-8 -- php -v

# --- Users -----------------------------------------------------------------------

# shellcheck disable=SC2016 # expanded in the container
expect "USER_ID and GROUP_ID remap www-data" "4321:4322 4321:4322" \
	"$(run -e USER_ID=4321 -e GROUP_ID=4322 -e EXEC_USER=www-data -- \
		sh -c 'echo "$(id -u):$(id -g) $(stat -c %u:%g "$HOME")"')"

expect "rootless: configuration still applied" "111M redis" \
	"$(run --user 4321:4321 -e PHP_INI_MEMORY_LIMIT=111M -e PHP_EXTENSIONS=redis -- \
		php -r 'echo ini_get("memory_limit"), extension_loaded("redis") ? " redis" : "";')"
run --user 4321:4321 -e MSMTP_HOST=smtp.example.com -- msmtp --pretend >/dev/null 2>&1 ||
	fail "rootless: msmtp cannot read its configuration"
pass "rootless: msmtp"

cat >"${tmp}/hook.sh" <<'SH'
export HOOK_RAN=yes
SH
chmod 0644 "${tmp}/hook.sh"
# shellcheck disable=SC2016 # expanded in the container
expect "hooks in /docker-entrypoint.d are sourced" "yes" \
	"$(run -v "${tmp}/hook.sh:/docker-entrypoint.d/10-hook.sh:ro" -- sh -c 'echo "$HOOK_RAN"')"

# --- FPM -------------------------------------------------------------------------

case "$target" in
fpm*)
	run -- php-fpm -t >/dev/null 2>&1 || fail "php-fpm -t"
	pass "php-fpm -t"

	cid="$(docker run -d -e APP_ENV=staging -e FPM_POOL_PM__MAX_CHILDREN=3 \
		-e MSMTP_HOST=smtp.example.com -e MSMTP_PASSWORD=secret "$image")"
	containers+=("$cid")
	wait_healthy "$cid"
	pass "FPM healthcheck"

	# Captured first: grep -q exits on the first match, and with pipefail the
	# SIGPIPE that hits the still-writing docker exec would fail the check.
	fpm_config="$(docker exec "$cid" php-fpm -tt 2>&1)"
	grep -q 'pm.max_children = 3' <<<"$fpm_config" ||
		fail "FPM_POOL_PM__MAX_CHILDREN not applied"
	pass "FPM_POOL_* sets pool directives"

	# Through FastCGI, so the worker's view: APP_ENV passed through, the msmtp
	# password not, the per-environment .user.ini in place.
	# cgi-fcgi forwards its own environment as FastCGI parameters, and getenv()
	# looks there first: it must run with nothing but the request variables, or
	# the container environment of `docker exec` would answer instead of the worker.
	docker exec -i "$cid" sh -c 'cat >/var/www/html/smoke.php' <<'PHP'
<?php
echo getenv('APP_ENV'), '|', var_export(getenv('MSMTP_PASSWORD'), true), '|', ini_get('user_ini.filename');
PHP
	response="$(docker exec "$cid" env -i SCRIPT_FILENAME=/var/www/html/smoke.php REQUEST_METHOD=GET \
		/usr/bin/cgi-fcgi -bind -connect 127.0.0.1:9000)"
	grep -q 'staging|false|.user-staging.ini' <<<"$response" || fail "FPM worker environment: ${response}"
	pass "FPM workers see APP_ENV but not MSMTP_PASSWORD"

	cid="$(docker run -d --user 4321:4321 "$image")"
	containers+=("$cid")
	wait_healthy "$cid"
	pass "rootless FPM"
	;;
esac

echo "all smoke tests passed for ${image} (${target})"
