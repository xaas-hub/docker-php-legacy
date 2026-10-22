# Security Policy

## Supported Versions

Only the latest release of this image is maintained. Its rolling tags
(`7.4-fpm`, `7.4.33-fpm`...) are rebuilt within a day of every update of the
Debian base image. Fixes to PHP itself arrive with a release, when a pin in
`versions.json` or a file in `patches/` moves. The `-vX.Y.Z` tags are never
rebuilt.

Every branch here is end of life: PHP publishes no fixes for it. What these
images carry is what Remi Collet backported to his security tree and the
php2shell fix described in the README; anything else stays open. Move to a
supported branch, [frugan/php](https://github.com/xaas-hub/docker-php), as
soon as the application allows.

| PHP branch | Images             | Fixes                                              |
|------------|--------------------|----------------------------------------------------|
| 5.6, 7.1 – 8.1 | :warning:      | Remi Collet's backports, php2shell                 |
| 7.0        | :x: not built      | no working php2shell patch yet                     |
| 8.2 – 8.5  | :x: not here       | official images: [frugan/php](https://github.com/xaas-hub/docker-php) |

## Reporting a Vulnerability

We take security seriously. If you discover a security vulnerability, please report it responsibly.

### How to Report

**Please DO NOT file a public issue for security vulnerabilities.**

Instead, please send an email to: **<dev@frugan.it>**

Include the following information:

- Description of the vulnerability
- Steps to reproduce the issue
- Potential impact assessment
- Any suggested fixes (if available)

A vulnerability that also affects a supported PHP branch goes to the
[PHP security team](https://www.php.net/manual/en/security.php). For the
end-of-life branches, report problems with the backports to
[remicollet/php-src-security](https://github.com/remicollet/php-src-security)
or [Anton-Barinov/php2shell-patches](https://github.com/Anton-Barinov/php2shell-patches),
and those of the build here to us.

### What to Expect

1. **Acknowledgment**: We will acknowledge receipt within 48 hours
2. **Assessment**: We will assess the vulnerability within 5 business days
3. **Resolution**: We will work to resolve critical issues within 30 days
4. **Disclosure**: We will coordinate with you on responsible disclosure

### Responsible Disclosure

We believe in responsible disclosure. We ask that you:

- Give us reasonable time to investigate and fix the issue
- Do not publicly disclose the vulnerability until we've had a chance to fix it
- Do not exploit the vulnerability for malicious purposes

### Security Best Practices

When running these images:

1. **Rolling tags**: run `7.4-fpm`, not a `-v` tag, and pull regularly
   (`docker compose pull && docker compose up -d`): a new backport is only
   applied once the container is recreated
2. **Exposure**: keep these containers behind a reverse proxy, with upload
   limits at the proxy, and away from anything that can run on a supported
   branch
3. **Secrets**: pass the SMTP password through `MSMTP_PASSWORD_FILE` and a
   Docker secret. With `clear_env = no`, every other variable of the container
   is visible to PHP code, `phpinfo()` included
4. **Privileges**: the FPM workers run as `www-data`. For containers that need
   no root at all, run them rootless (`user:`), optionally with
   `read_only: true`
5. **Development images**: never run the `-dev` tags in production

## Security Contact

For security-related questions or concerns:

- Email: <dev@frugan.it>
- GitHub: [@frugan-dev](https://github.com/frugan-dev)

## Acknowledgments

We appreciate the security research community's efforts in responsibly disclosing vulnerabilities. Security researchers who help us improve this project will be acknowledged in our security advisories (with their permission).
