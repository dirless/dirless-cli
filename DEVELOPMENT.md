# Development

## Requirements

- Crystal >= 1.20.0
- `libage.so` — from [age-crystal](https://github.com/dirless/age-crystal)
- `libx509.so` — from [x509-crystal](https://github.com/dirless/x509-crystal)

Both `.so` files must be on the library path (e.g. `/usr/lib/`) before building or running.

## Building from source

```sh
shards install
make build
# → ./dirless-cli
```

For an AL2023-compatible static binary (RPM targets):

```sh
make docker-build
# → dist/dirless-cli
```

## Testing

```sh
make test
```

## Linting

```sh
make lint
```

## Releases

Releases are tagged as `vX.Y.Z`. Pushing a tag triggers the GitHub Actions
release workflow, which builds static binaries and RPMs for x86_64 and
aarch64, publishes them as GitHub release assets, and updates the RPM
repository at [dirless.com/rpm](https://dirless.com/rpm).
