# dirless-cli

Crystal CLI tool for enrolling Linux nodes into the Dirless identity platform. Run once per host. Generates an age keypair and writes it to `/etc/dirless/`.

## What it does

1. Derives the tenant ID (from AWS IMDSv2 + HMAC, or explicit `--tenant-id`)
2. Generates an age keypair (`age-crystal`)
3. Generates an HMAC secret (or reuses existing one)
4. Writes all material to `/etc/dirless/`
5. POSTs the enrollment payload to the Dirless backend

## Language / stack

- Crystal >= 1.9.0
- `age-crystal` (age keypair generation)
- AWS IMDSv2 for tenant ID on EC2 instances
- RPM packaging via `.spec` in `packaging/`

## Key entry points

| File | Purpose |
|------|---------|
| `src/dirless_cli.cr` | Entry point — CLI arg parsing, command dispatch |
| `src/commands/enroll.cr` | `enroll` command implementation |
| `src/providers/aws.cr` | AWS IMDS v2 — fetches EC2 identity document for account ID |
| `src/hmac_key.cr` | HMAC secret generation and tenant ID derivation |
| `src/config.cr` | CLI config handling |

## Files written to `/etc/dirless/`

| File | Contents |
|------|---------|
| `age.key` | age secret key (0600) |
| `hmac.key` | HMAC secret for tenant ID derivation (0600) |

## Build & test

```sh
shards install
make build          # → ./dirless-cli
make docker-build   # → dist/dirless-cli (AL2023-compatible via Docker)
make test
make lint
```

## Tenant ID derivation (AWS)

```
tenant_id = "aws___" + HMAC-SHA256(hmac_secret, aws_account_id)
```

The `hmac.key` is generated once and reused across rotations to keep the tenant identity stable. Use `--regenerate-hmac` only when intentionally rotating to a new identity (destructive — orphans all backend data).
