# dirless-cli

Command-line tool for enrolling Linux nodes with Dirless — maps AWS IAM Identity Center users and groups to native Linux identities without LDAP or a directory service.

## Installation

### RPM (RHEL / Amazon Linux 2023)

Packages are available for x86_64 and aarch64.

**Step 1 — add the Dirless repository:**

```sh
curl -fsSL https://dirless.com/rpm/dirless.repo \
  -o /etc/yum.repos.d/dirless.repo
```

**Step 2 — install:**

```sh
dnf install -y dirless-cli
```

### Binary

```sh
# x86_64
curl -fsSL https://github.com/dirless/dirless-cli/releases/latest/download/dirless-cli-x86_64 \
  -o /usr/local/bin/dirless-cli

# aarch64
curl -fsSL https://github.com/dirless/dirless-cli/releases/latest/download/dirless-cli-aarch64 \
  -o /usr/local/bin/dirless-cli

chmod +x /usr/local/bin/dirless-cli
```

## Usage

Your enrollment token and server address are available in the [Dirless portal](https://portal.dirless.com).

### Enroll a node

```sh
dirless-cli enroll \
  --token <your-enrollment-token> \
  --server https://<your-subdomain>.dirless.com
```

### Non-AWS environments

On EC2, the tenant ID is derived automatically from the instance identity. For
non-AWS hosts, pass it explicitly:

```sh
dirless-cli enroll \
  --tenant-id <your-tenant-id> \
  --token <your-enrollment-token> \
  --server https://<your-subdomain>.dirless.com
```

## Files written to `/etc/dirless/`

| File         | Contents                                        |
|--------------|-------------------------------------------------|
| `ca.crt`     | CA certificate (PEM)                            |
| `ca.key`     | CA private key (PEM, 0600)                      |
| `client.crt` | Client certificate for mTLS (PEM)               |
| `client.key` | Client private key (PEM, 0600)                  |
| `age.key`    | Encryption key (0600)                           |
| `hmac.key`   | Identity key — do not share or delete (0600)    |

## License

Apache 2.0 — see [LICENSE](LICENSE).
