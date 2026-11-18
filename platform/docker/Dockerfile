# The image of the lantern binary: the static Linux binaries of both presets, and nothing else.
# Build it from a directory that holds linux-<ISA>/lantern-mainnet and lantern-minimal of
# platform/linux/build.sh for each ISA of the image (x86_64 for amd64, arm64, riscv64):
#   docker buildx build --platform linux/amd64,linux/arm64,linux/riscv64 -f platform/docker/Dockerfile build/
# /lantern runs the mainnet preset, /lantern-minimal the minimal preset.
ARG TARGETARCH
FROM scratch AS amd64
COPY linux-x86_64/lantern-mainnet /lantern
COPY linux-x86_64/lantern-minimal /lantern-minimal
FROM scratch AS arm64
COPY linux-arm64/lantern-mainnet /lantern
COPY linux-arm64/lantern-minimal /lantern-minimal
FROM scratch AS riscv64
COPY linux-riscv64/lantern-mainnet /lantern
COPY linux-riscv64/lantern-minimal /lantern-minimal
FROM ${TARGETARCH}
ENTRYPOINT ["/lantern"]
