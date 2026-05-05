# syntax=docker/dockerfile:1.7
FROM ubuntu:22.04 AS builder

# Use bash and enable pipefail
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ARG TARGETPLATFORM
ARG APT_MIRROR_AMD64="http://archive.ubuntu.com/ubuntu"
ARG APT_SECURITY_MIRROR_AMD64="http://security.ubuntu.com/ubuntu"
ARG APT_MIRROR_ARM64="http://ports.ubuntu.com/ubuntu-ports"

# Install build dependencies
# Note: Build with --network=host if you encounter GPG/network issues
RUN set -eux; \
    if [ "${TARGETPLATFORM}" = "linux/arm64" ]; then \
        sed -i "s|http://ports.ubuntu.com/ubuntu-ports|${APT_MIRROR_ARM64}|g" /etc/apt/sources.list; \
    else \
        sed -i "s|http://archive.ubuntu.com/ubuntu|${APT_MIRROR_AMD64}|g; s|http://security.ubuntu.com/ubuntu|${APT_SECURITY_MIRROR_AMD64}|g" /etc/apt/sources.list; \
    fi
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-cache-${TARGETPLATFORM} \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked,id=apt-lists-${TARGETPLATFORM} \
    apt-get update && apt-get install -y --no-install-recommends \
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
        ccache \
        libtommath-dev \
        libssl-dev \
        zlib1g-dev

# Install latest Rust toolchain via rustup
ENV CARGO_HOME=/root/.cargo
ENV RUSTUP_HOME=/root/.rustup
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal --default-toolchain stable \
    && . "$CARGO_HOME/env" \
    && rustup component add rustfmt clippy
ENV PATH="${CARGO_HOME}/bin:${PATH}"
ENV CCACHE_DIR=/root/.ccache
ENV CCACHE_MAXSIZE=2G

ARG GIT_COMMIT=unknown
ARG GIT_BRANCH=unknown
ARG LANTERN_RUST_PROFILE=0

WORKDIR /usr/src/lantern

COPY . .

RUN LANTERN_BOOTSTRAP_SKIP_SUBMODULE_SYNC=1 ./scripts/bootstrap.sh
RUN if [ "${LANTERN_RUST_PROFILE}" = "1" ]; then \
        printf '[target."cfg(target_arch = \\"x86_64\\")"]\nrustflags = ["-C", "target-cpu=x86-64-v3", "-C", "force-frame-pointers=yes", "-C", "debuginfo=2"]\n' > external/c-leanvm-xmss/.cargo/config.toml; \
    fi \
    && echo "LANTERN_RUST_PROFILE=${LANTERN_RUST_PROFILE}" \
    && cat external/c-leanvm-xmss/.cargo/config.toml

RUN --mount=type=cache,target=/root/.cargo/registry,sharing=locked,id=cargo-registry-${TARGETPLATFORM} \
    --mount=type=cache,target=/root/.cargo/git,sharing=locked,id=cargo-git-${TARGETPLATFORM} \
    --mount=type=cache,target=/usr/src/lantern/external/c-leanvm-xmss/target,sharing=locked,id=leanvm-xmss-target-${TARGETPLATFORM}-${LANTERN_RUST_PROFILE} \
    cd external/c-leanvm-xmss \
    && cargo build --release --locked \
    && find target/release -name '*.a' -exec ranlib {} \;

RUN --mount=type=cache,target=/root/.ccache,sharing=locked,id=ccache-${TARGETPLATFORM} \
    cmake -S external/c-libp2p/external/libtommath -B deps/libtommath -DBUILD_SHARED_LIBS=ON -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    && cmake --build deps/libtommath --parallel "$(nproc)" \
    && cmake --install deps/libtommath

RUN --mount=type=cache,target=/root/.ccache,sharing=locked,id=ccache-${TARGETPLATFORM} \
    cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache -DLANTERN_GIT_COMMIT="${GIT_COMMIT}" -DLANTERN_GIT_BRANCH="${GIT_BRANCH}"

ARG LANTERN_FORCE_REBUILD=0
RUN echo "LANTERN_FORCE_REBUILD=${LANTERN_FORCE_REBUILD}"
RUN --mount=type=cache,target=/root/.ccache,sharing=locked,id=ccache-${TARGETPLATFORM} \
    cmake --build build --target lantern_cli --parallel "$(nproc)"

RUN --mount=type=cache,target=/root/.ccache,sharing=locked,id=ccache-${TARGETPLATFORM} \
    cmake --build build --target lantern_client_test --parallel "$(nproc)" || true

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

# Preserve leanMultisig sources needed at runtime for XMSS aggregation.
# The runtime binary expects xmss_aggregate.lean_lang at the build-time cargo checkout path.
RUN --mount=type=cache,target=/root/.cargo/git,sharing=locked,id=cargo-git-${TARGETPLATFORM} \
    mkdir -p /opt/lantern/share/cargo-git-checkouts \
    && cp -a /root/.cargo/git/checkouts/leanmultisig-* /opt/lantern/share/cargo-git-checkouts/

FROM ubuntu:22.04

ARG GIT_COMMIT=unknown
ARG GIT_BRANCH=unknown
ARG TARGETPLATFORM
ARG APT_MIRROR_AMD64="http://archive.ubuntu.com/ubuntu"
ARG APT_SECURITY_MIRROR_AMD64="http://security.ubuntu.com/ubuntu"
ARG APT_MIRROR_ARM64="http://ports.ubuntu.com/ubuntu-ports"

LABEL org.opencontainers.image.revision=$GIT_COMMIT \
      org.opencontainers.image.ref.name=$GIT_BRANCH

ENV DEBIAN_FRONTEND=noninteractive

# Set to "true" to include gdb, perf, and valgrind for debugging/profiling
ARG INCLUDE_DEBUG_TOOLS=false
# Set to "true" to include heaptrack for heap profiling
ARG INCLUDE_HEAPTRACK=false

# Install runtime dependencies (and optionally profiling tools)
RUN set -eux; \
    if [ "${TARGETPLATFORM}" = "linux/arm64" ]; then \
        sed -i "s|http://ports.ubuntu.com/ubuntu-ports|${APT_MIRROR_ARM64}|g" /etc/apt/sources.list; \
    else \
        sed -i "s|http://archive.ubuntu.com/ubuntu|${APT_MIRROR_AMD64}|g; s|http://security.ubuntu.com/ubuntu|${APT_SECURITY_MIRROR_AMD64}|g" /etc/apt/sources.list; \
    fi
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-cache-${TARGETPLATFORM} \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked,id=apt-lists-${TARGETPLATFORM} \
    apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        libssl3 \
        libstdc++6 \
        zlib1g \
    && if [ "$INCLUDE_DEBUG_TOOLS" = "true" ]; then \
        apt-get install -y --no-install-recommends gdb linux-tools-generic valgrind \
        && ln -sf /usr/lib/linux-tools/*/perf /usr/local/bin/perf || true; \
    fi \
    && if [ "$INCLUDE_HEAPTRACK" = "true" ]; then \
        apt-get install -y --no-install-recommends heaptrack; \
    fi

COPY --from=builder /opt/lantern /opt/lantern
RUN mkdir -p /root/.cargo/git/checkouts
COPY --from=builder /opt/lantern/share/cargo-git-checkouts/ /root/.cargo/git/checkouts/
COPY docker/entrypoint.sh /usr/local/bin/lantern-entrypoint.sh
RUN chmod +x /usr/local/bin/lantern-entrypoint.sh

ENV PATH="/opt/lantern/bin:${PATH}"
ENV LD_LIBRARY_PATH="/opt/lantern/lib"

WORKDIR /data

ENTRYPOINT ["/usr/local/bin/lantern-entrypoint.sh"]
CMD []
