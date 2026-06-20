SHELL   := /bin/bash
BINARY  := dirless-cli
SRC     := src/dirless_cli.cr

DOCKER        := docker
DOCKER_IMAGE  := dirless-cli-builder

.PHONY: all build build-release docker-build clean test lint

all: build

# Local build — requires Crystal on PATH and libage.so / libx509.so installed
build:
	@echo "==> Building $(BINARY) (local)..."
	shards install
	crystal build $(SRC) -o $(BINARY)
	@echo "==> Done: $(BINARY)"

# Release build (optimised)
build-release:
	@echo "==> Building $(BINARY) (release)..."
	shards install
	crystal build $(SRC) -o $(BINARY) --release
	@echo "==> Done: $(BINARY)"

# AL2023 build — fully self-contained, clones and builds all deps inside the container
docker-build:
	@echo "==> Building $(BINARY) inside Amazon Linux 2023..."
	@mkdir -p dist
	$(DOCKER) build \
		--build-arg GO_VERSION=1.21.13 \
		--build-arg CRYSTAL_VERSION=1.11.2 \
		-t $(DOCKER_IMAGE) \
		-f Dockerfile.build \
		.
	$(DOCKER) run --rm \
		-v "$(CURDIR)/dist":/output \
		$(DOCKER_IMAGE) \
		cp /build/$(BINARY) /output/$(BINARY)
	@echo "==> Done: dist/$(BINARY)"

test:
	@echo "==> Running Crystal specs..."
	crystal spec

lint:
	@echo "==> Running ameba..."
	bin/ameba src/

clean:
	rm -f $(BINARY)
	rm -rf dist/