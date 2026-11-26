#!/bin/sh
# Pin the dependencies, fetch them into build/deps/, and name the functions
# this repo calls in them (ARCHITECTURE.md section 5).
# Runs inside the image from platform/linux/Dockerfile, from the repo root.
# Every library goes into one binary, so each library's own pins of the others
# must be the pins here.
#
# The functions this repo calls in each dependency. platform/check.py rejects
# a call to any other function.
# uses asm-ssz: ssz_hash_tree_root
# uses asm-crypto: crypto_sha256 crypto_hmac_sha256 crypto_bls_verify crypto_bls_fast_aggregate_verify crypto_bls_fast_aggregate_verify_cached crypto_bls_eth_fast_aggregate_verify crypto_bls_eth_aggregate_pubkeys crypto_bls_g1_decode crypto_bls_g1_neg crypto_bls_g1_add crypto_bls_g1_compress crypto_kzg_verify_blob_kzg_proof crypto_kzg_verify_blob_kzg_proof_batch crypto_kzg_verify_cell_kzg_proof_batch crypto_kzg_recover_cells_and_kzg_proofs
# uses asm-snappy: snappy_get_uncompressed_length snappy_uncompress snappy_frame_compress snappy_frame_uncompress
# uses asm-libp2p: libp2p_step
# uses asm-quic (through asm-libp2p): quic_state_size quic_init quic_step
# uses asm-discv5: discv5_init discv5_step discv5_enr_decode
# uses asm-rlp (through asm-discv5): rlp_decode

set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
fetch() {
    dir=$root/build/deps/$1
    if [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" != "$2" ]; then
        rm -rf "$dir"
        git init -q "$dir"
        git -C "$dir" fetch -q --depth 1 "https://github.com/bitminetech/$1" "$2"
        git -C "$dir" checkout -q FETCH_HEAD
    fi
}
fetch asm-ssz 3b48c1ce630eff7286f2caff9e0bb55e792ab7ea
fetch asm-crypto a364b8c3c06b55607834f93cda7b7e315323b3b8
fetch asm-snappy b84f65a17f51dead69d22a7f6c5a16f7b2975d2a
fetch asm-libp2p 05350fee83505b184bdaf3ec019a0bada1afe4b6
fetch asm-quic 8ce353c1df72f835a234118c7f8f022118d5dac0
fetch asm-discv5 ce98c4091f41479c6ed1de27aa984f2cedc80be5
fetch asm-rlp 40cca377a1621ed660a73724192a4a0b2c059a84

# Each library's pin of another must match ours.
check() {
    theirs=$(sed -n "s/^.*fetch $2 \([0-9a-f]\{40\}\).*/\1/p; s/^$3=\([0-9a-f]\{40\}\).*/\1/p" \
        "$root/build/deps/$1/platform/deps.sh" | head -n 1)
    ours=$(sed -n "s/^fetch $2 \([0-9a-f]\{40\}\).*/\1/p" "$root/platform/deps.sh")
    if [ "$theirs" != "$ours" ]; then
        echo "deps.sh: $1 pins $2 at $theirs, lantern pins $ours" >&2
        exit 1
    fi
}
check asm-ssz asm-crypto commit
check asm-libp2p asm-crypto crypto
check asm-libp2p asm-quic quic
check asm-quic asm-crypto crypto
check asm-discv5 asm-crypto commit
check asm-discv5 asm-rlp commit
