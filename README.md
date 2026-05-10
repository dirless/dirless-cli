# dirless-cli

Command-line tool for enrolling Linux nodes with Dirless — maps AWS IAM Identity Center users and groups to native Linux identities without LDAP or a directory service.

## Installation

### RPM (RHEL / Amazon Linux 2023)

```sh
curl -fsSL https://dirless.com/rpm/dirless.repo \
  -o /etc/yum.repos.d/dirless.repo
dnf install -y dirless-cli
```

### Binary (Linux x86_64)

```sh
curl -fsSL https://github.com/dirless/dirless-cli/releases/latest/download/dirless-cli-x86_64 \
  -o /usr/local/bin/dirless-cli
chmod +x /usr/local/bin/dirless-cli
```

### Binary (Linux aarch64)

```sh
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

### Re-enroll (rotate certificates, keep identity)

```sh
dirless-cli enroll \
  --token <your-enrollment-token> \
  --server https://<your-subdomain>.dirless.com \
  --overwrite-existing
```

### Re-enroll with a new identity (destructive)

```sh
dirless-cli enroll \
  --token <your-enrollment-token> \
  --server https://<your-subdomain>.dirless.com \
  --overwrite-existing \
  --regenerate-hmac
```

> ⚠️ `--regenerate-hmac` assigns this node a new identity. All existing backend
> data under the previous identity will be orphaned. You will be prompted to
> confirm before proceeding.

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
