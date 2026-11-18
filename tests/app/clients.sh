# The images of the clients that the tests of the binary run beside lantern (tests/app/interop.sh,
# tests/app/devnet.sh), each the latest release pinned by digest. Sourced:
# client_image CLIENT and validator_image CLIENT print an image, or nothing for an unknown client.

geth_image=ethereum/client-go:v1.17.10@sha256:5015dcab74ec5c9ef6584ada930ea353264a1c4e72383f256802e3178e10918c

client_image() {
    case $1 in
      lighthouse) echo sigp/lighthouse:v8.3.3@sha256:53f9063d98c3d3a2d290207873f019ea2298cfc02f8cd58d87c33b04aab856d1 ;;
      prysm) echo offchainlabs/prysm-beacon-chain:v7.3.1@sha256:ad79198a2968b2442c80b7279f2613b61d882913ed372feb057ea624ba205e29 ;;
      teku) echo consensys/teku:26.10.3@sha256:4560398cf9a0b208a4a4a12ebc2051d820b67df51092a54154031dacc57f2ac6 ;;
      nimbus) echo statusim/nimbus-eth2:multiarch-v26.10.2@sha256:53a51bf89ce48e0b615c90726e018ad96ed242001d7d8cbc8aa33ff25188845a ;;
      lodestar) echo chainsafe/lodestar:v1.51.0@sha256:88e897f8adf1ec9ea8dcaed8178db9170ea9d0dff82d218b707af9bc0a8a5974 ;;
      grandine) echo sifrai/grandine:2.0.6@sha256:9373496ebecc42e67c754c18eb762d73f48539af978de83ef59709da3375cd57 ;;
    esac
}

# The validator client: the beacon node's image, but prysm's and nimbus's own.
validator_image() {
    case $1 in
      prysm) echo offchainlabs/prysm-validator:v7.3.1@sha256:8d018a6205108354f46da67f2d8cae5f28822a85e1f225c4cc93f389c8ca024a ;;
      nimbus) echo statusim/nimbus-validator-client:multiarch-v26.10.2@sha256:738e8830d7dcf5a3f8d91112e11cb9475757ca60888f5aef464a9c62dccb1d41 ;;
      *) client_image "$1" ;;
    esac
}
