# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0](https://github.com/xaas-hub/docker-php-legacy/compare/v0.3.0...v0.4.0) (2026-11-03)

### Features

* add PHP 7.0 ([98f23dc](https://github.com/xaas-hub/docker-php-legacy/commit/98f23dc47b46dded8380ba0f32e3f04b8402eb36))

### Bug Fixes

* pick up Remi's latest backports for 7.4, 8.0 and 8.1 ([ac3fe49](https://github.com/xaas-hub/docker-php-legacy/commit/ac3fe491c4ba82bf808423a9dd91f294cf216a4b))
* use the official php2shell fix of Remi's tree on 7.2 and 7.3 ([bef8cc4](https://github.com/xaas-hub/docker-php-legacy/commit/bef8cc4b62d6e9a8c5eb92c023eb73504895bdb2))

### Documentation

* mount the crontab directory for Supercronic ([d155c8a](https://github.com/xaas-hub/docker-php-legacy/commit/d155c8adefb4ea3f4fdb4aa00cb6017795d64c75))

## [0.3.0](https://github.com/xaas-hub/docker-php-legacy/compare/v0.2.1...v0.3.0) (2026-10-30)

### Features

* add procps for signalling Supercronic ([3c473e9](https://github.com/xaas-hub/docker-php-legacy/commit/3c473e9fceabb871c3a863a1402a346df596dc58))

## [0.2.1](https://github.com/xaas-hub/docker-php-legacy/compare/v0.2.0...v0.2.1) (2026-10-23)

### Documentation

* **readme:** update the php2shell-patches notes to 41fa62f ([4a39d4d](https://github.com/xaas-hub/docker-php-legacy/commit/4a39d4d560c4805c3110fd619e7b6dce6cd5406b))

## [0.2.0](https://github.com/xaas-hub/docker-php-legacy/compare/v0.1.4...v0.2.0) (2026-10-23)

### Features

* add the optional extensions of docker-php, plus mcrypt ([adf8b79](https://github.com/xaas-hub/docker-php-legacy/commit/adf8b79b37c93db299724c5001a20f61fffbd337))

### Bug Fixes

* **php:** turn session upload progress off by default ([e4e2766](https://github.com/xaas-hub/docker-php-legacy/commit/e4e2766ead1c8612580fdb89ea18d4d59f71559b))

## [0.1.4](https://github.com/xaas-hub/docker-php-legacy/compare/v0.1.3...v0.1.4) (2026-10-22)

### Bug Fixes

* publish the images of every branch ([5114b64](https://github.com/xaas-hub/docker-php-legacy/commit/5114b64b9931f85aaf40640634b0eeae4524963f))

## [0.1.3](https://github.com/xaas-hub/docker-php-legacy/compare/v0.1.2...v0.1.3) (2026-10-22)

### Bug Fixes

* **build:** install profile-command 2.1.4 on PHP < 7.2.24 ([f4c302f](https://github.com/xaas-hub/docker-php-legacy/commit/f4c302f729275b91a590ad90936159b5e943e17d))

## [0.1.2](https://github.com/xaas-hub/docker-php-legacy/compare/v0.1.1...v0.1.2) (2026-10-22)

### Bug Fixes

* **php-5.6:** build on arm64 with php-src d6d4f2a ([ef65531](https://github.com/xaas-hub/docker-php-legacy/commit/ef655310bcd6d7d35ac71f40d769d032d002eb12))

## [0.1.1](https://github.com/xaas-hub/docker-php-legacy/compare/v0.1.0...v0.1.1) (2026-10-22)

### Bug Fixes

* **build:** provide libssl1.1 for install-php-extensions on PHP < 8.1 ([174ee0b](https://github.com/xaas-hub/docker-php-legacy/commit/174ee0be63ddb49ae288d396b962973a55e59b46))

## [0.1.0](https://github.com/xaas-hub/docker-php-legacy/compare/v0.0.0...v0.1.0) (2026-10-22)

### Features

* initial release ([bdd5fb6](https://github.com/xaas-hub/docker-php-legacy/commit/bdd5fb6ab0fb564103c0dbcb9f526d25e94f75d6))
