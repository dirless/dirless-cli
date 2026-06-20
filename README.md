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

On EC2, the tenant ID is derived automatically: the CLI fetches the AWS account ID from IMDS and computes `aws___HMAC-SHA256(token, account_id)`. This is the same derivation used by dirless-syncer, so both nodes share the same backend identity without manual coordination.

### Non-AWS environments

On non-EC2 hosts, pass the tenant ID explicitly:

```sh
dirless-cli enroll \
  --tenant-id <your-tenant-id> \
  --token <your-enrollment-token> \
  --server https://<your-subdomain>.dirless.com
```

### Re-enrollment (replacing a lost or rotated keypair)

```sh
dirless-cli enroll \
  --token <your-enrollment-token> \
  --server https://<your-subdomain>.dirless.com \
  --overwrite-existing
```

This generates a new age keypair and updates the backend. dirless-agent must be restarted with the new key afterwards.

## Files written to `/etc/dirless/`

| File         | Contents                                        |
|--------------|-------------------------------------------------|
| `ca.crt`     | CA certificate (PEM)                            |
| `ca.key`     | CA private key (PEM, 0600)                      |
| `client.crt` | Client certificate for mTLS (PEM)               |
| `client.key` | Client private key (PEM, 0600)                  |
| `age.key`    | age encryption private key (0600)               |
| `hmac.key`   | Enrollment token — do not share or delete (0600)|

## License

Apache 2.0 — see [LICENSE](LICENSE).