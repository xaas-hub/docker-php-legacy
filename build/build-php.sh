#!/usr/bin/env bash
#
# Builds PHP from the source pinned in versions.json the way the official images
# build it (docker-library/php), into /usr/local: docker-php-ext-*,
# install-php-extensions and the runtime layer rely on that layout.
#
#   build-php.sh deps  <context>   prints the Debian packages the build needs
#   build-php.sh build <context>   fetches, patches, compiles and installs PHP
#
# <context> holds versions.json and patches/. PHP_VERSION is the branch (5.6,
# 7.4...), PHP_VARIANT is cli or fpm. PHP_INI_DIR, PHP_CFLAGS, PHP_CPPFLAGS and
# PHP_LDFLAGS come from the Dockerfile, as in the official images, and so do the
# OPENSSL_* and PEAR_* pins.

set -Eeuo pipefail

readonly OPENSSL_PREFIX=/usr/local/openssl

die() {
	printf 'build-php: %s\n' "$*" >&2
	exit 1
}

# 7.3 -> 703, so that branches compare as numbers.
version_id() {
	echo $((${1%%.*} * 100 + ${1#*.}))
}

php_at_least() {
	[ "$(version_id "$PHP_VERSION")" -ge "$(version_id "$1")" ]
}

config() {
	jq -r --arg v "$PHP_VERSION" ".[\$v]$1 // empty" "${context}/versions.json"
}

deps() {
	local -a pkgs=(bison git patch libcurl4-openssl-dev libsqlite3-dev libxml2-dev zlib1g-dev)

	if php_at_least 7.3; then pkgs+=(libreadline-dev); else pkgs+=(libedit-dev); fi
	if php_at_least 7.2; then pkgs+=(libargon2-dev libsodium-dev); fi
	# 7.4 dropped the oniguruma bundled with mbstring.
	if php_at_least 7.4; then pkgs+=(libonig-dev); fi
	case "$(config .openssl)" in
	system) pkgs+=(libssl-dev) ;;
	# OpenSSL's Configure needs more of perl than perl-base.
	1.1) pkgs+=(perl) ;;
	*) die "${PHP_VERSION}: openssl must be system or 1.1" ;;
	esac

	printf '%s\n' "${pkgs[@]}"
}

# ext/openssl calls APIs that OpenSSL 3 removed until PHP 8.1, so the older
# branches get their own OpenSSL 1.1, next to the system one. Both libraries
# version their symbols, which is what lets PHP (1.1) and libcurl or libpq (3)
# share a process.
build_openssl() {
	local dir libdir

	# The libdir PHP is configured with, which is where PHP < 7.4 looks for
	# the libraries.
	libdir="lib/$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"

	dir="$(mktemp -d)"
	curl -fsSLo "${dir}/openssl.tar.gz" \
		"https://github.com/openssl/openssl/releases/download/OpenSSL_${OPENSSL_VERSION//./_}/openssl-${OPENSSL_VERSION}.tar.gz"
	echo "${OPENSSL_SHA256} *${dir}/openssl.tar.gz" | sha256sum -c -
	tar -xzf "${dir}/openssl.tar.gz" -C "$dir" --strip-components=1
	(
		cd "$dir"
		./config --prefix="$OPENSSL_PREFIX" --openssldir="${OPENSSL_PREFIX}/ssl" --libdir="$libdir" shared no-tests
		make -j "$(nproc)"
		make install_sw install_ssldirs
	)
	rm -rf "$dir" "${OPENSSL_PREFIX}/${libdir}"/*.a "${OPENSSL_PREFIX}/ssl/certs"
	# The CA certificates of the system, which ca-certificates keeps current.
	ln -s /etc/ssl/certs "${OPENSSL_PREFIX}/ssl/certs"
	ln -s /etc/ssl/certs/ca-certificates.crt "${OPENSSL_PREFIX}/ssl/cert.pem"
	echo "${OPENSSL_PREFIX}/${libdir}" >/etc/ld.so.conf.d/openssl-1.1.conf
	ldconfig
}

# Leaves /usr/src/php.tar.xz, the layout docker-php-source expects: a top
# directory and a tree ready for configure, as in a release tarball.
prepare_source() {
	local repository commit patch src=/usr/src/php-src

	repository="$(config .source.repository)"
	commit="$(config .source.commit)"
	patch="$(config .patch)"

	rm -rf "$src"
	git init -q "$src"
	git -C "$src" fetch -q --depth=1 "$repository" "$commit"
	git -C "$src" -c advice.detachedHead=false checkout -q FETCH_HEAD
	[ "$(git -C "$src" rev-parse HEAD)" = "$commit" ] || die "fetched commit does not match ${commit}"

	if [ -n "$patch" ]; then
		patch -d "$src" -p1 --forward --batch --fuzz=0 <"${context}/patches/${patch}"
	fi

	# Release tarballs ship the PEAR installer; without it, make install
	# downloads it, from plain http on the 5.x branches.
	curl -fsSLo "${src}/pear/install-pear-nozlib.phar" \
		"https://raw.githubusercontent.com/pear/pearweb_phars/${PEAR_PHAR_COMMIT}/install-pear-nozlib.phar"
	echo "${PEAR_PHAR_SHA256} *${src}/pear/install-pear-nozlib.phar" | sha256sum -c -

	(cd "$src" && ./buildconf --force)
	rm -rf "${src}/.git" "${src}/autom4te.cache"
	tar -cJf /usr/src/php.tar.xz -C /usr/src php-src
	rm -rf "$src"
}

compile() {
	local gnu_arch deb_multiarch
	local -a args

	gnu_arch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"
	deb_multiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"

	# Every option is one the official images passed for that branch.
	args=(
		--build="$gnu_arch"
		--sysconfdir="${PHP_INI_DIR%/php}"
		--with-config-file-path="$PHP_INI_DIR"
		--with-config-file-scan-dir="${PHP_INI_DIR}/conf.d"
		--enable-option-checking=fatal
		--with-mhash
		--enable-ftp
		--enable-mbstring
		--enable-mysqlnd
		--with-curl
		--with-zlib
		--with-libdir="lib/${deb_multiarch}"
		--disable-cgi
	)
	if php_at_least 7.1; then args+=(--with-pdo-sqlite=/usr --with-sqlite3=/usr); fi
	if php_at_least 7.2; then args+=(--with-pic --with-password-argon2 --with-sodium=shared); fi
	if php_at_least 7.3; then
		args+=(--with-iconv --with-readline --disable-phpdbg)
	else
		args+=(--with-libedit)
	fi
	if php_at_least 7.4; then args+=(--with-pear); fi
	if [ "$(config .openssl)" = system ]; then
		args+=(--with-openssl)
	elif php_at_least 7.4; then
		# 7.4 finds OpenSSL through pkg-config only.
		args+=(--with-openssl)
		export PKG_CONFIG_PATH="${OPENSSL_PREFIX}/lib/${deb_multiarch}/pkgconfig"
	else
		args+=(--with-openssl="$OPENSSL_PREFIX")
	fi
	if [ "$PHP_VARIANT" = fpm ]; then
		args+=(--enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data)
	fi

	export \
		CFLAGS="$PHP_CFLAGS" \
		CPPFLAGS="$PHP_CPPFLAGS" \
		LDFLAGS="$PHP_LDFLAGS" \
		PHP_BUILD_PROVIDER='https://github.com/xaas-hub/docker-php-legacy' \
		PHP_UNAME='Linux - Docker'

	docker-php-source extract
	(
		cd /usr/src/php
		# https://bugs.php.net/bug.php?id=74125
		if [ ! -d /usr/include/curl ]; then
			ln -sT "/usr/include/${deb_multiarch}/curl" /usr/local/include/curl
		fi
		./configure "${args[@]}"
		make -j "$(nproc)"
		find . -type f -name '*.a' -delete
		make install
		find /usr/local -type f -perm '/0111' -exec sh -c 'strip --strip-all "$@" || :' -- '{}' +
		make clean
		cp -v php.ini-* "${PHP_INI_DIR}/"
	)
	docker-php-source delete

	# https://github.com/docker-library/php/issues/443
	pecl update-channels
	rm -rf /tmp/pear ~/.pearrc

	# Built shared, like the official images, so that it can be replaced.
	if php_at_least 7.2; then
		docker-php-ext-enable sodium
	fi
}

# The FPM configuration of the official images. The directives they added in
# 7.3 are left out before it, where FPM refuses unknown ones.
configure_fpm() {
	cd "${PHP_INI_DIR%/php}"
	if [ -d php-fpm.d ]; then
		sed 's!=NONE/!=!g' php-fpm.conf.default >php-fpm.conf
		cp php-fpm.d/www.conf.default php-fpm.d/www.conf
	else
		# 5.6 has a single file: split it the way 7.0 does.
		mkdir php-fpm.d
		cp php-fpm.conf.default php-fpm.d/www.conf
		printf '[global]\ninclude=%s/php-fpm.d/*.conf\n' "${PHP_INI_DIR%/php}" >php-fpm.conf
	fi
	{
		echo '[global]'
		echo 'error_log = /proc/self/fd/2'
		if php_at_least 7.3; then
			echo 'log_limit = 8192'
		fi
		echo
		echo '[www]'
		echo 'access.log = /proc/self/fd/2'
		echo 'clear_env = no'
		echo 'catch_workers_output = yes'
		if php_at_least 7.3; then
			echo 'decorate_workers_output = no'
		fi
	} >php-fpm.d/docker.conf
	{
		echo '[global]'
		echo 'daemonize = no'
		echo
		echo '[www]'
		echo 'listen = 9000'
	} >php-fpm.d/zz-docker.conf
	echo 'fastcgi.logging = Off' >"${PHP_INI_DIR}/conf.d/docker-fpm.ini"
}

command="${1:?usage: build-php.sh deps|build <context>}"
context="${2:?usage: build-php.sh deps|build <context>}"
: "${PHP_VERSION:?}" "${PHP_VARIANT:?}"
[ -n "$(config .source.commit)" ] || die "${PHP_VERSION} is not in versions.json"

case "$command" in
deps) deps ;;
build)
	: "${PHP_INI_DIR:?}" "${PHP_CFLAGS:?}" "${PHP_CPPFLAGS:?}" "${PHP_LDFLAGS:?}" \
		"${OPENSSL_VERSION:?}" "${OPENSSL_SHA256:?}" "${PEAR_PHAR_COMMIT:?}" "${PEAR_PHAR_SHA256:?}"
	if [ "$(config .openssl)" = 1.1 ]; then
		build_openssl
	fi
	prepare_source
	compile
	if [ "$PHP_VARIANT" = fpm ]; then
		configure_fpm
	fi
	php --version
	;;
*) die "unknown command: ${command}" ;;
esac
