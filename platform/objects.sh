# Assemble the lantern objects and the dependency objects for one target.
# Sourced by platform/<OS>/build.sh, which defines as() with the target flags
# and sets isa and root. build_objects OS OUT_DIR leaves the dependency objects
# in $deps (and in $deps_off for the signatures-off runner), and liblantern-mainnet.a
# and liblantern-minimal.a in OUT_DIR.

# The asm-crypto objects lantern calls, and those that its dependencies call.
CRYPTO_OBJECTS="sha256 hmac bls12381"

# The forks that lantern's core has an object for (include/forks.inc).
FORKS="phase0 altair bellatrix capella deneb electra fulu"
fork_number() {
    case $1 in
      phase0) echo 0 ;; altair) echo 1 ;; bellatrix) echo 2 ;; capella) echo 3 ;;
      deneb) echo 4 ;; electra) echo 5 ;; fulu) echo 6 ;;
      *) echo "unknown fork $1" >&2; exit 2 ;;
    esac
}

build_objects() {
    os=$1
    out=$2
    dep=$root/build/deps
    plat=$root/platform/$os
    mkdir -p "$out/deps"

    deps=""
    for name in $CRYPTO_OBJECTS; do
        as -I"$dep/asm-crypto/include" -I"$dep/asm-crypto/platform/$os" \
            -c "$dep/asm-crypto/asm/core/$isa/$name.s" -o "$out/deps/crypto-$name.o"
        deps="$deps $out/deps/crypto-$name.o"
    done
    as -I"$dep/asm-ssz/include" -I"$dep/asm-ssz/platform/$os" \
        -c "$dep/asm-ssz/asm/core/$isa/ssz.s" -o "$out/deps/ssz.o"
    deps="$deps $out/deps/ssz.o"
    as -I"$dep/asm-snappy/include" -I"$dep/asm-snappy/platform/$os" \
        -c "$dep/asm-snappy/asm/core/$isa/snappy.s" -o "$out/deps/snappy.o"
    deps="$deps $out/deps/snappy.o"

    # The signatures-off test runner (tests/runner/bls_off.c) links a copy of the
    # BLS object whose three signature checks are renamed, so that the stand-ins
    # of bls_off.c take their names. $deps_off is $deps with that copy.
    prefix=""
    [ "$os" = macos ] && prefix=_
    renames=""
    for fn in crypto_bls_verify crypto_bls_fast_aggregate_verify crypto_bls_eth_fast_aggregate_verify; do
        renames="$renames --redefine-sym $prefix$fn=$prefix${fn}_real"
    done
    llvm-objcopy $renames "$out/deps/crypto-bls12381.o" "$out/deps/crypto-bls12381-off.o"
    deps_off=$(echo "$deps" | sed 's#crypto-bls12381\.o#crypto-bls12381-off.o#')

    # One archive per preset. The core files include preset.inc from the
    # preset's folder in include/.
    for preset in mainnet minimal; do
        objects=""
        mkdir -p "$out/$preset"
        # The core (include/forks.inc): asm/core/<ISA>/common.s once, and
        # asm/core/<ISA>/lantern.s once for each fork in $FORKS, with FORK set.
        core="-I$root/include/$preset -I$root/include -I$plat -I$root/asm/core/$isa -I$dep/asm-ssz/include -I$dep/asm-crypto/include"
        as $core -c "$root/asm/core/$isa/common.s" -o "$out/$preset/common.o"
        objects="$objects $out/$preset/common.o"
        for fork in $FORKS; do
            as $core -Wa,-defsym,FORK=$(fork_number $fork) -c "$root/asm/core/$isa/lantern.s" -o "$out/$preset/$fork.o"
            objects="$objects $out/$preset/$fork.o"
        done
        # A name the assembler does not know becomes an undefined symbol, not an error:
        # the core objects may only call asm-ssz, asm-crypto, asm-snappy and the common object.
        unknown=$(llvm-nm -u $out/$preset/*.o | sed 's/^ *U //; s/^_//' | grep -v '^\(crypto_\|ssz_\|snappy_\|lantern_store_\|lantern_seen_\)' | grep -v ':$' | grep . || true)
        if [ -n "$unknown" ]; then
            echo "objects.sh: undefined symbols in the core of $os $isa $preset: $unknown" >&2
            exit 1
        fi
        shell=$root/asm/shell/$os/$isa/shell.s
        if [ -e "$shell" ]; then
            as -I"$root/include/$preset" -I"$root/include" -I"$plat" -I"$root/asm/shell/$os/$isa" \
                -c "$shell" -o "$out/$preset/shell.o"
            objects="$objects $out/$preset/shell.o"
        fi
        rm -f "$out/liblantern-$preset.a"
        if [ "$os" = macos ]; then
            llvm-ar --format=darwin rcs "$out/liblantern-$preset.a" $objects
        else
            llvm-ar rcs "$out/liblantern-$preset.a" $objects
        fi
    done
}
