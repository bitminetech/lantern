cmake_minimum_required(VERSION 3.20)

project(lantern VERSION 0.1.0 LANGUAGES C)

set(CMAKE_POLICY_VERSION_MINIMUM 3.5)

if(APPLE)
    set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "Target architecture for macOS builds" FORCE)
endif()

set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

include(cmake/Dependencies.cmake)

set(SECP256K1_DISABLE_SHARED ON CACHE BOOL "" FORCE)
set(SECP256K1_INSTALL OFF CACHE BOOL "" FORCE)
set(SECP256K1_BUILD_BENCHMARK OFF CACHE BOOL "" FORCE)
set(SECP256K1_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(SECP256K1_BUILD_EXHAUSTIVE_TESTS OFF CACHE BOOL "" FORCE)
set(SECP256K1_BUILD_CTIME_TESTS OFF CACHE BOOL "" FORCE)
set(SECP256K1_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)

find_package(Threads REQUIRED)


add_library(lantern STATIC
    src/consensus/containers.c
    src/consensus/duties.c
    src/consensus/fork_choice.c
    src/consensus/hash.c
    src/consensus/runtime.c
    src/consensus/slot_clock.c
    src/consensus/signature.c
    src/consensus/state.c
    src/consensus/ssz.c
    src/core/client.c
    src/core/client_debug.c
    src/core/client_http.c
    src/core/client_init.c
    src/core/client_keys.c
    src/core/client_network.c
    src/core/client_peers.c
    src/core/client_pending.c
    src/core/client_reqresp.c
    src/core/client_reqresp_blocks.c
    src/core/client_reqresp_stream.c
    src/core/client_sync.c
    src/core/client_sync_blocks.c
    src/core/client_sync_votes.c
	    src/core/client_utils.c
		    src/core/client_validator.c
		    src/genesis/genesis.c
		    src/genesis/genesis_parse.c
		    src/genesis/genesis_parse_registry.c
		    src/genesis/genesis_validator_config.c
		    src/encoding/snappy.c
	    src/networking/enr.c
    src/networking/gossip.c
    src/networking/gossipsub_service.c
    src/networking/gossip_payloads.c
    src/networking/libp2p.c
    src/networking/reqresp_service.c
    src/networking/messages.c
    src/encoding/rlp.c
    src/metrics/lean_metrics.c
    src/http/common.c
    src/http/metrics.c
    src/http/server.c
    src/storage/storage.c
    src/support/log.c
    src/support/string_list.c
    src/support/strings.c
    src/support/time.c
    src/support/secure_mem.c
    src/crypto/hash_sig.c
    src/internal/yaml_parser.c
    external/c-libp2p/src/multiformats/multibase/encoding/base64_url.c
    external/c-libp2p/external/wjcryptlib/lib/WjCryptLib_Sha256.c
)

target_include_directories(lantern
    PUBLIC
        ${PROJECT_SOURCE_DIR}/include
    PRIVATE
        ${PROJECT_SOURCE_DIR}/src
        ${PROJECT_SOURCE_DIR}/external/jsmn
        ${PROJECT_SOURCE_DIR}/external/c-hash-sig
        ${PROJECT_SOURCE_DIR}/external/c-libp2p/external/secp256k1/include
        ${PROJECT_SOURCE_DIR}/external/c-libp2p/external/libtomcrypt/src/headers
        ${PROJECT_SOURCE_DIR}/external/c-libp2p/external/wjcryptlib/lib
)
target_compile_definitions(lantern
    PRIVATE
        _DEFAULT_SOURCE
        _POSIX_C_SOURCE=200809L
)

lantern_configure_dependencies(lantern)
target_link_libraries(lantern PRIVATE secp256k1 libtomcrypt Threads::Threads)

add_executable(lantern_cli src/core/main.c)
target_link_libraries(lantern_cli PRIVATE lantern Threads::Threads)
target_compile_definitions(lantern_cli
    PRIVATE
        _DEFAULT_SOURCE
        _POSIX_C_SOURCE=200809L
)

add_executable(lantern_repro_transition tools/debug/repro_transition.c)
add_executable(lantern_repro_genesis_transition tools/debug/repro_genesis_transition.c)
target_link_libraries(lantern_repro_transition PRIVATE lantern)
target_link_libraries(lantern_repro_genesis_transition PRIVATE lantern)

add_executable(lantern_inspect_block tools/debug/inspect_block.c)
target_link_libraries(lantern_inspect_block PRIVATE lantern)

add_executable(lantern_inspect_genesis tools/debug/inspect_genesis.c)
target_link_libraries(lantern_inspect_genesis PRIVATE lantern)

add_executable(lantern_fix_genesis_state tools/debug/fix_genesis_state.c)
target_link_libraries(lantern_fix_genesis_state PRIVATE lantern)

add_executable(lantern_generate_gossip_snappy tools/debug/generate_gossip_snappy.c)
target_link_libraries(lantern_generate_gossip_snappy PRIVATE lantern)

add_executable(lantern_regenerate_networking_fixtures tools/debug/regenerate_networking_fixtures.c)
target_link_libraries(lantern_regenerate_networking_fixtures PRIVATE lantern)

option(LANTERN_BUILD_TESTS "Build lantern unit tests" ON)
if(LANTERN_BUILD_TESTS)
    enable_testing()
    add_executable(lantern_client_vote_test
        tests/unit/test_client_vote.c
        tests/unit/client_test_helpers.c
    )
    target_link_libraries(lantern_client_vote_test PRIVATE lantern)
    target_include_directories(
        lantern_client_vote_test
        PRIVATE
            ${PROJECT_SOURCE_DIR}/tests/unit
    )
    target_compile_definitions(
        lantern_client_vote_test
        PRIVATE
            LANTERN_TEST_FIXTURE_DIR="${PROJECT_SOURCE_DIR}/tests/fixtures"
    )
    add_test(NAME lantern_client_vote COMMAND lantern_client_vote_test)

    add_executable(lantern_client_pending_test
        tests/unit/test_client_pending.c
        tests/unit/client_test_helpers.c
    )
    target_link_libraries(lantern_client_pending_test PRIVATE lantern)
    target_include_directories(
        lantern_client_pending_test
        PRIVATE
            ${PROJECT_SOURCE_DIR}/tests/unit
    )
    target_compile_definitions(
        lantern_client_pending_test
        PRIVATE
            LANTERN_TEST_FIXTURE_DIR="${PROJECT_SOURCE_DIR}/tests/fixtures"
    )
    add_test(NAME lantern_client_pending COMMAND lantern_client_pending_test)

    add_executable(lantern_genesis_bootstrap_test tests/unit/test_genesis_bootstrap.c)
    target_link_libraries(lantern_genesis_bootstrap_test PRIVATE lantern)
    target_compile_definitions(
        lantern_genesis_bootstrap_test
        PRIVATE
            LANTERN_TEST_FIXTURE_DIR="${PROJECT_SOURCE_DIR}/tests/fixtures"
    )
    add_test(NAME lantern_genesis_bootstrap COMMAND lantern_genesis_bootstrap_test)

    add_executable(lantern_validator_selection_test tests/unit/test_validator_selection.c)
    target_link_libraries(lantern_validator_selection_test PRIVATE lantern)
    target_compile_definitions(
        lantern_validator_selection_test
        PRIVATE
            LANTERN_TEST_FIXTURE_DIR="${PROJECT_SOURCE_DIR}/tests/fixtures"
    )
    add_test(NAME lantern_validator_selection COMMAND lantern_validator_selection_test)

    add_executable(lantern_rlp_test tests/unit/test_rlp.c)
    target_link_libraries(lantern_rlp_test PRIVATE lantern)
    add_test(NAME lantern_rlp COMMAND lantern_rlp_test)

    add_executable(lantern_enr_test tests/unit/test_enr.c)
    target_link_libraries(lantern_enr_test PRIVATE lantern)
    add_test(NAME lantern_enr COMMAND lantern_enr_test)

    add_executable(lantern_ssz_test tests/unit/test_ssz.c)
    target_link_libraries(lantern_ssz_test PRIVATE lantern)
    add_test(NAME lantern_ssz COMMAND lantern_ssz_test)

    add_executable(lantern_duties_test tests/unit/test_duties.c)
    target_link_libraries(lantern_duties_test PRIVATE lantern)
    add_test(NAME lantern_duties COMMAND lantern_duties_test)

    add_executable(lantern_signature_test tests/unit/test_signature.c)
    target_link_libraries(lantern_signature_test PRIVATE lantern)
    target_include_directories(
        lantern_signature_test
        PRIVATE
            ${PROJECT_SOURCE_DIR}/external/c-hash-sig/include
    )
    add_test(NAME lantern_signature COMMAND lantern_signature_test)
    set_tests_properties(lantern_signature PROPERTIES TIMEOUT 3600)

    add_executable(lantern_consensus_runtime_test tests/unit/test_consensus_runtime.c)
    target_link_libraries(lantern_consensus_runtime_test PRIVATE lantern)
    add_test(NAME lantern_consensus_runtime COMMAND lantern_consensus_runtime_test)

    add_executable(lantern_state_test tests/unit/test_state.c)
    target_link_libraries(lantern_state_test PRIVATE lantern)
    add_test(NAME lantern_state COMMAND lantern_state_test)

    add_executable(lantern_slot_clock_test tests/unit/test_slot_clock.c)
    target_link_libraries(lantern_slot_clock_test PRIVATE lantern)
    add_test(NAME lantern_slot_clock COMMAND lantern_slot_clock_test)

    add_executable(lantern_snappy_test tests/unit/test_snappy.c)
    target_link_libraries(lantern_snappy_test PRIVATE lantern)
    add_test(NAME lantern_snappy COMMAND lantern_snappy_test)

    add_executable(lantern_networking_messages_test
        tests/unit/test_networking_messages.c
        tests/support/fixture_loader.c
    )
    target_link_libraries(lantern_networking_messages_test PRIVATE lantern)
    target_include_directories(
        lantern_networking_messages_test
        PRIVATE
            ${PROJECT_SOURCE_DIR}
            ${PROJECT_SOURCE_DIR}/external/jsmn
    )
    target_compile_definitions(
        lantern_networking_messages_test
        PRIVATE
            LANTERN_TEST_FIXTURE_DIR="${PROJECT_SOURCE_DIR}/tests/fixtures"
    )
    add_test(NAME lantern_networking_messages COMMAND lantern_networking_messages_test)

    add_executable(lantern_libp2p_test tests/unit/test_libp2p.c)
    target_link_libraries(lantern_libp2p_test PRIVATE lantern)
    add_test(NAME lantern_libp2p COMMAND lantern_libp2p_test)

    add_executable(lantern_fork_choice_test tests/unit/test_fork_choice.c)
    target_link_libraries(lantern_fork_choice_test PRIVATE lantern)
    add_test(NAME lantern_fork_choice COMMAND lantern_fork_choice_test)

    add_executable(lantern_storage_test tests/unit/test_storage.c)
    target_link_libraries(lantern_storage_test PRIVATE lantern)
    add_test(NAME lantern_storage COMMAND lantern_storage_test)

    add_executable(lantern_metrics_test tests/unit/test_metrics.c)
    target_link_libraries(lantern_metrics_test PRIVATE lantern)
    add_test(NAME lantern_metrics COMMAND lantern_metrics_test)

    add_executable(lantern_validator_duties_integration_test tests/integration/test_validator_duties.c)
    target_link_libraries(lantern_validator_duties_integration_test PRIVATE lantern)
    add_test(NAME lantern_validator_duties_integration COMMAND lantern_validator_duties_integration_test)

    add_executable(lantern_consensus_vectors_test
        tests/integration/test_consensus_vectors.c
        tests/integration/consensus_fixture_runner.c
        tests/support/fixture_loader.c
    )
    target_link_libraries(lantern_consensus_vectors_test PRIVATE lantern)
    target_include_directories(
        lantern_consensus_vectors_test
        PRIVATE
            ${PROJECT_SOURCE_DIR}
            ${PROJECT_SOURCE_DIR}/external/jsmn
    )
    target_compile_definitions(
        lantern_consensus_vectors_test
        PRIVATE
            LANTERN_TEST_FIXTURE_DIR="${PROJECT_SOURCE_DIR}/tests/fixtures"
    )
    add_test(NAME lantern_consensus_vectors COMMAND lantern_consensus_vectors_test)
    # Consensus fixtures iterate over dozens of LeanSpec transitions and need a longer timeout.
    set_tests_properties(lantern_consensus_vectors PROPERTIES TIMEOUT 300)

    add_executable(lantern_genesis_vectors_test
        tests/integration/test_genesis_vectors.c
        tests/integration/consensus_fixture_runner.c
        tests/support/fixture_loader.c
    )
    target_link_libraries(lantern_genesis_vectors_test PRIVATE lantern)
    target_include_directories(
        lantern_genesis_vectors_test
        PRIVATE
            ${PROJECT_SOURCE_DIR}
            ${PROJECT_SOURCE_DIR}/external/jsmn
    )
    target_compile_definitions(
        lantern_genesis_vectors_test
        PRIVATE
            LANTERN_TEST_FIXTURE_DIR="${PROJECT_SOURCE_DIR}/tests/fixtures"
    )
    add_test(NAME lantern_genesis_vectors COMMAND lantern_genesis_vectors_test)
    set_tests_properties(lantern_genesis_vectors PROPERTIES TIMEOUT 120)

    # Mirror libp2p dependency test names into CTestCustom so top-level `ctest`
    # ignores them (they are dependency-only suites we do not build/run).
    set(_lantern_libp2p_binary_dir ${CMAKE_BINARY_DIR}/c-libp2p)
    if(EXISTS "${_lantern_libp2p_binary_dir}")
        get_property(_lantern_libp2p_tests
            DIRECTORY "${_lantern_libp2p_binary_dir}"
            PROPERTY TESTS)
        if(_lantern_libp2p_tests)
            set(_lantern_ctest_custom "${CMAKE_BINARY_DIR}/CTestCustom.cmake")
            file(WRITE "${_lantern_ctest_custom}"
"# Auto-generated by lantern/CMakeLists.txt – skip c-libp2p dependency tests.\n"
"set(CTEST_CUSTOM_TESTS_IGNORE\n")
            foreach(_lantern_test_name IN LISTS _lantern_libp2p_tests)
                file(APPEND "${_lantern_ctest_custom}" "    ${_lantern_test_name}\n")
            endforeach()
            file(APPEND "${_lantern_ctest_custom}" ")\n")
        endif()
    endif()

    set(_lantern_ctest_targets
        lantern_client_vote
        lantern_client_pending
        lantern_genesis_bootstrap
        lantern_validator_selection
        lantern_rlp
        lantern_enr
        lantern_ssz
        lantern_duties
        lantern_consensus_runtime
        lantern_state
        lantern_slot_clock
        lantern_snappy
        lantern_networking_messages
        lantern_libp2p
        lantern_fork_choice
        lantern_storage
        lantern_metrics
        lantern_validator_duties_integration
    )
    set_property(TEST ${_lantern_ctest_targets} PROPERTY TIMEOUT 30)
    set_tests_properties(lantern_client_vote PROPERTIES TIMEOUT 300)

endif()
