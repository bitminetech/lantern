FROM ubuntu:22.04 AS builder

# Use bash and enable pipefail
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
# Note: Build with --network=host if you encounter GPG/network issues
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        bison \
        ca-certificates \
        cmake \
        git \
        ninja-build \
        pkg-config \
        flex \
        python3 \
        python3-pip \
        curl \
        libtommath-dev \
        libssl-dev \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Install latest Rust toolchain via rustup
ENV CARGO_HOME=/root/.cargo
ENV RUSTUP_HOME=/root/.rustup
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal --default-toolchain stable \
    && . "$CARGO_HOME/env" \
    && rustup component add rustfmt clippy
ENV PATH="${CARGO_HOME}/bin:${PATH}"

WORKDIR /usr/src/lantern

COPY . .

RUN LANTERN_BOOTSTRAP_SKIP_SUBMODULE_SYNC=1 ./scripts/bootstrap.sh

# Build the hash-sig bindings (cargo archive needs ranlib'd index on linux)
RUN cd external/c-hash-sig \
    && cargo build --release \
    && find target/release -name '*.a' -exec ranlib {} \;

RUN cmake -S external/c-libp2p/external/libtommath -B deps/libtommath -DBUILD_SHARED_LIBS=ON \
    && cmake --build deps/libtommath --parallel "$(nproc)" \
    && cmake --install deps/libtommath

RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo

ARG LANTERN_FORCE_REBUILD=0
RUN echo "LANTERN_FORCE_REBUILD=${LANTERN_FORCE_REBUILD}"
RUN cmake --build build --target lantern_cli --parallel "$(nproc)"

RUN cmake --build build --target lantern_client_test --parallel "$(nproc)" || true

RUN mkdir -p /opt/lantern/bin \
    && cp build/lantern_cli /opt/lantern/bin/lantern \
    && mkdir -p /opt/lantern/lib \
    && find build -maxdepth 2 -type f -name "*.so*" -exec cp {} /opt/lantern/lib/ \; \
    && python3 - <<'PY'
import os
import pathlib
libdir = pathlib.Path("/opt/lantern/lib")
for path in libdir.glob("*.so.*"):
    name = path.name
    stem, _, suffix = name.partition(".so.")
    if not suffix:
        continue
    major = suffix.split(".", 1)[0]
    target = libdir / name
    for link_name in {f"{stem}.so", f"{stem}.so.{major}"}:
        link_path = libdir / link_name
        try:
            if link_path.is_symlink() or link_path.exists():
                link_path.unlink()
            link_path.symlink_to(target.name)
        except FileExistsError:
            pass
PY

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Set to "true" to include gdb and perf for debugging/profiling
ARG INCLUDE_DEBUG_TOOLS=false

# Install runtime dependencies (and optionally profiling tools)
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        libssl3 \
        libstdc++6 \
        zlib1g \
    && if [ "$INCLUDE_DEBUG_TOOLS" = "true" ]; then \
        apt-get install -y --no-install-recommends gdb linux-tools-generic \
        && ln -sf /usr/lib/linux-tools/*/perf /usr/local/bin/perf || true; \
    fi \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/lantern /opt/lantern
COPY docker/entrypoint.sh /usr/local/bin/lantern-entrypoint.sh

ENV PATH="/opt/lantern/bin:${PATH}"
ENV LD_LIBRARY_PATH="/opt/lantern/lib"

WORKDIR /data

ENTRYPOINT ["/usr/local/bin/lantern-entrypoint.sh"]
CMD []
