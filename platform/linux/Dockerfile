# Build and Linux test image for lantern.
#
# It holds the pinned build tools from the README (LLVM 23.1.5 and llvm-mingw
# 20261104), QEMU user mode for the Linux ISAs that are not native, and the
# C libraries that the test runner links against for each Linux ISA.
# It builds lantern for every target, and runs the Linux tests.
FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2

ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl xz-utils zstd python3 qemu-user \
        libc6-dev libgcc-14-dev \
        libc6-dev-amd64-cross libgcc-14-dev-amd64-cross \
        libc6-dev-arm64-cross libgcc-14-dev-arm64-cross \
        libc6-dev-riscv64-cross libgcc-14-dev-riscv64-cross \
    && rm -rf /var/lib/apt/lists/*

# LLVM 23.1.5, official release build, checked against the GitHub release digest.
RUN set -eu; \
    case "$TARGETARCH" in \
      arm64) f=LLVM-23.1.5-Linux-ARM64.tar.zst; s=830ceb70edf63849ce66e97bf85310a3bf2bdd04c860a9f2fa4ef1560e290cef ;; \
      amd64) f=LLVM-23.1.5-Linux-X64.tar.zst;   s=c3107384835f788768f614db610e87fba7077f125ca950eb02a78bab0a308065 ;; \
      *) echo "unsupported build host $TARGETARCH"; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/llvm.tar.zst "https://github.com/llvm/llvm-project/releases/download/llvmorg-23.1.5/$f"; \
    echo "$s  /tmp/llvm.tar.zst" | sha256sum -c -

# The archive uses a 1 GiB zstd window, so zstd needs --long=30.
RUN set -eu; \
    mkdir -p /opt/llvm; \
    tar -I 'zstd -d --long=30' -xf /tmp/llvm.tar.zst -C /opt/llvm --strip-components=1 --wildcards \
        '*/bin/clang' '*/bin/clang-23' '*/bin/lld' '*/bin/ld.lld' '*/bin/ld64.lld' '*/bin/lld-link' \
        '*/bin/llvm-ar' '*/bin/llvm-nm' '*/bin/llvm-objcopy' '*/bin/llvm-objdump' '*/bin/llvm-readobj' \
        '*/lib/clang/23/include/*'; \
    /opt/llvm/bin/clang --version

# llvm-mingw 20261104 (LLVM 23.1.5), for the Windows test runner.
RUN set -eu; \
    case "$TARGETARCH" in \
      arm64) f=llvm-mingw-20261104-ucrt-ubuntu-22.04-aarch64.tar.xz; s=595e95bdffabfc62559fe26e30bdfbccf277cbaed4902793555015ee47306b94 ;; \
      amd64) f=llvm-mingw-20261104-ucrt-ubuntu-22.04-x86_64.tar.xz;  s=919380403de87dca3c581c2053230cd298af5e891286628ba0613b7fed370926 ;; \
    esac; \
    curl -fsSL -o /tmp/mingw.tar.xz "https://github.com/mstorsjo/llvm-mingw/releases/download/20261104/$f"; \
    echo "$s  /tmp/mingw.tar.xz" | sha256sum -c -; \
    mkdir -p /opt/llvm-mingw; \
    tar -xJf /tmp/mingw.tar.xz -C /opt/llvm-mingw --strip-components=1; \
    rm /tmp/mingw.tar.xz; \
    /opt/llvm-mingw/bin/x86_64-w64-mingw32-clang --version

ENV PATH=/opt/llvm/bin:$PATH
WORKDIR /src

# Vector generation: git fetches the pinned consensus spec and the dependencies, and a
# virtual environment holds the Python packages of tests/generator/requirements.txt.
RUN apt-get update && apt-get install -y --no-install-recommends git python3-venv \
    && rm -rf /var/lib/apt/lists/*
