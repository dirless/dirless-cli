# dirless-cli build automation
# https://github.com/cbea.ms/just

# Default command
default := build

# Build commands
build:
    echo "==> Building dirless-cli (local)..."
    shards install
    crystal build src/dirless_cli.cr -o dirless-cli
    echo "==> Done: dirless-cli"

build-release:
    echo "==> Building dirless-cli (release)..."
    shards install
    crystal build src/dirless_cli.cr -o dirless-cli --release
    echo "==> Done: dirless-cli"

docker-build:
    echo "==> Building dirless-cli inside Amazon Linux 2023..."
    mkdir -p dist
    docker build \
        --build-arg GO_VERSION=1.21.13 \
        --build-arg CRYSTAL_VERSION=1.11.2 \
        -t dirless-cli-builder \
        -f Dockerfile.build \
        .
    docker run --rm \
        -v "{{cwd}}/dist:/output" \
        dirless-cli-builder \
        cp /build/dirless-cli /output/dirless-cli
    echo "==> Done: dist/dirless-cli"

# Testing
test:
    echo "==> Running Crystal specs..."
    crystal spec

# Linting
lint:
    echo "==> Running ameba..."
    bin/ameba src/

# Cleanup
clean:
    rm -f dirless-cli
    rm -rf dist/