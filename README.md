# dirless-cli

Command-line tool for enrolling and managing Dirless identity nodes.

## Requirements

- Crystal >= 1.9.0
- `libage.so` — from [age-crystal](https://github.com/dirless/age-crystal)
- `libx509.so` — from [x509-crystal](https://github.com/dirless/x509-crystal)

Both `.so` files must be on the library path (e.g. `/usr/lib/`) before building or running.

## Installation

```sh
shards install
make build
# → ./dirless-cli
```

For an AL2023-compatible binary (RPM targets):

```sh
make docker-build
# → dist/dirless-cli
```

## Usage

### Enroll

Enrolls this node with the Dirless backend. Generates an age keypair, an X.509
certificate bundle, and an HMAC secret, writes them to `/etc/dirless/`, then
POSTs to the backend enrollment endpoint.

**Self-signed mode (dev/testing):**

```sh
dirless-cli enroll \
  --token <your-bearer-token> \
  --server https://enroll.dirless.io
```

**CA-signed mode (production):**

```sh
dirless-cli enroll \
  --token <your-bearer-token> \
  --server https://enroll.dirless.io \
  --ca-cert /path/to/ca.crt \
  --ca-key  /path/to/ca.key
```

**Explicit tenant ID (non-AWS / local dev):**

```sh
dirless-cli enroll \
  --tenant-id my-tenant-123 \
  --token <your-bearer-token> \
  --server https://enroll.dirless.io
```

**Re-enrollment (rotate certs, keep identity):**

```sh
dirless-cli enroll \
  --token <your-bearer-token> \
  --server https://enroll.dirless.io \
  --overwrite-existing
```

**Re-enrollment with new identity (destructive):**

```sh
dirless-cli enroll \
  --token <your-bearer-token> \
  --server https://enroll.dirless.io \
  --overwrite-existing \
  --regenerate-hmac
```

> ⚠️  `--regenerate-hmac` produces a new tenant identity. All existing backend
> data under the previous identity will be orphaned. You will be prompted to
> confirm before proceeding.

### Files written to `/etc/dirless/`

| File         | Contents                                      |
|--------------|-----------------------------------------------|
| `ca.crt`     | CA certificate (PEM)                          |
| `ca.key`     | CA private key (PEM, 0600)                    |
| `client.crt` | Client certificate for mTLS (PEM)             |
| `client.key` | Client private key (PEM, 0600)                |
| `age.key`    | Age secret key for envelope encryption (0600) |
| `hmac.key`   | HMAC secret used to derive tenant ID (0600)   |

## Tenant ID derivation

On AWS, the tenant ID is derived automatically from the EC2 instance identity
document via IMDSv2:

```
tenant_id = "aws___" + HMAC-SHA256(hmac_secret, aws_account_id)
```

The `hmac.key` file is generated once on first enrollment and reused on
subsequent runs, keeping the tenant identity stable across cert rotations.

Pass `--tenant-id` to skip IMDS and use an explicit value instead (useful for
local development or non-AWS environments).

## Development

```sh
# Run specs
make test

# Lint
make lint
```
