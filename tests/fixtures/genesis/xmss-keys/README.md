# Test-only XMSS fixtures

These two key pairs use LeanVM-B BLAKE2s XMSS, pinned by `external/c-leanvm`
to leanVM `022ec377a39de6c6982cb0d88799d54b05d5c981`. They cover slots
0 through 65535 inclusive. Public keys use SSZ; secret keys use the backend's
postcard encoding despite the historical `.ssz` filenames.

The secret keys are public test data. **Never use them on a live network.**
They are separate from the dummy public keys in the genesis YAML fixtures;
client-test helpers install the matching public keys into their test states.

To regenerate after changing the backend, from the Lantern repository root:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DLANTERN_BUILD_TESTS=ON
cmake --build build --target lantern_generate_xmss_fixtures --parallel
./build/lantern_generate_xmss_fixtures tests/fixtures/genesis/xmss-keys
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

Generation uses fresh randomness, so regenerating produces different bytes.
Commit both public and secret fixture files together. CI consumes these files;
it does not silently replace fixtures or skip tests on decode failures.
