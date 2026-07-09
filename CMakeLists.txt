cmake_minimum_required(VERSION 3.20)

project(lantern VERSION 0.1.0 LANGUAGES C)

set(CMAKE_POLICY_VERSION_MINIMUM 3.5)

if(APPLE)
    set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "Target architecture for macOS builds" FORCE)
    add_compile_definitions(_DARWIN_C_SOURCE)
    add_compile_definitions(PATH_MAX=4096)
    add_compile_definitions(NAME_MAX=255)
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

set(LANTERN_LIBRARY_SOURCES
    src/consensus/containers.c
    src/consensus/duties.c
    src/consensus/fork_choice.c
    src/consensus/hash.c
    src/consensus/runtime.c
    src/consensus/shadow_cost.c
    src/consensus/slot_clock.c
    src/consensus/signature.c
    src/consensus/state.c
    src/consensus/store.c
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
		    src/genesis/genesis_parse_helpers.c
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
    src/metrics/server.c
    src/http/client.c
    src/http/core.c
    src/http/server.c
    src/test_driver/driver.c
    src/storage/storage.c
    src/support/log.c
    src/support/string_list.c
    src/support/strings.c
    src/support/time.c
    src/support/secure_mem.c
    src/crypto/xmss.c
    src/internal/yaml_parser.c
    tests/support/fixture_loader.c
    tests/support/state_store_adapter.c
)

function(lantern_define_library target_name wrapper_target)
    add_library(${target_name} STATIC ${LANTERN_LIBRARY_SOURCES})
    target_include_directories(${target_name}
        PUBLIC
            ${PROJECT_SOURCE_DIR}/include
        PRIVATE
            ${PROJECT_SOURCE_DIR}
            ${PROJECT_SOURCE_DIR}/src
            ${PROJECT_SOURCE_DIR}/external/jsmn
    )
    target_compile_definitions(${target_name}
        PRIVATE
            _DEFAULT_SOURCE
            _POSIX_C_SOURCE=200809L
    )
    lantern_configure_dependencies(${target_name} ${wrapper_target})
    target_link_libraries(${target_name} PRIVATE Threads::Threads)
endfunction()

lantern_define_library(lantern lantern_c_leanvm_xmss)

set(LANTERN_FIXTURE_GENERATOR_DIR
    "${PROJECT_SOURCE_DIR}/tools/leanSpec")
find_program(LANTERN_UV_EXECUTABLE uv)
if(NOT LANTERN_UV_EXECUTABLE)
    set(LANTERN_UV_EXECUTABLE uv)
endif()

add_custom_target(fixtures
    COMMAND "${CMAKE_COMMAND}" -E chdir "${LANTERN_FIXTURE_GENERATOR_DIR}" "${LANTERN_UV_EXECUTABLE}" python install 3.12
    COMMAND "${CMAKE_COMMAND}" -E chdir "${LANTERN_FIXTURE_GENERATOR_DIR}" "${LANTERN_UV_EXECUTABLE}" sync
    COMMAND "${CMAKE_COMMAND}" -E chdir "${LANTERN_FIXTURE_GENERATOR_DIR}" "${LANTERN_UV_EXECUTABLE}" run fill --fork=Lstar --clean -n auto
    USES_TERMINAL
    COMMENT "Generating leanSpec consensus fixtures"
    VERBATIM
)

add_executable(lantern_cli src/core/main.c)
target_link_libraries(lantern_cli PRIVATE lantern Threads::Threads)
if(NOT DEFINED LANTERN_GIT_COMMIT OR LANTERN_GIT_COMMIT STREQUAL "")
    execute_process(
        COMMAND git rev-parse --short HEAD
        WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
        OUTPUT_VARIABLE LANTERN_GIT_COMMIT
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
        RESULT_VARIABLE _git_commit_result
    )
    if(NOT _git_commit_result EQUAL 0)
        set(LANTERN_GIT_COMMIT "unknown")
    endif()
endif()

if(NOT DEFINED LANTERN_GIT_BRANCH OR LANTERN_GIT_BRANCH STREQUAL "")
    execute_process(
        COMMAND git rev-parse --abbrev-ref HEAD
        WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
        OUTPUT_VARIABLE LANTERN_GIT_BRANCH
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
        RESULT_VARIABLE _git_branch_result
    )
    if(NOT _git_branch_result EQUAL 0)
        set(LANTERN_GIT_BRANCH "unknown")
    endif()
endif()

target_compile_definitions(lantern_cli
    PRIVATE
        _DEFAULT_SOURCE
        _POSIX_C_SOURCE=200809L
        LANTERN_GIT_COMMIT="${LANTERN_GIT_COMMIT}"
        LANTERN_GIT_BRANCH="${LANTERN_GIT_BRANCH}"
)

set(LANTERN_CONSENSUS_FIXTURE_DIR
    "${PROJECT_SOURCE_DIR}/tools/leanSpec/fixtures/consensus"
    CACHE PATH
    "Path to generated leanSpec consensus fixtures root")

option(LANTERN_BUILD_TESTS "Build lantern unit tests" ON)
if(LANTERN_BUILD_TESTS)
    enable_testing()
    lantern_define_library(lantern_test lantern_c_leanvm_xmss_test)
    set(LANTERN_TEST_LINK_LIB lantern_test)

    set(_lantern_state_transition_fixture_dir
        "${LANTERN_CONSENSUS_FIXTURE_DIR}/state_transition/lstar/state_transition")
    set(_lantern_fork_choice_fixture_dir
        "${LANTERN_CONSENSUS_FIXTURE_DIR}/fork_choice/lstar/fc")
    set(_lantern_verify_signatures_fixture_dir
        "${LANTERN_CONSENSUS_FIXTURE_DIR}/verify_signatures/lstar/verify_signatures")
    set(_lantern_ssz_fixture_dir
        "${LANTERN_CONSENSUS_FIXTURE_DIR}/ssz/lstar/ssz")
    set(_lantern_networking_codec_fixture_dir
        "${LANTERN_CONSENSUS_FIXTURE_DIR}/networking_codec/lstar/networking")
    set(_lantern_ssz_fixture_dir
        "${LANTERN_CONSENSUS_FIXTURE_DIR}/ssz/lstar/ssz")
    set(_lantern_networking_codec_fixture_dir
        "${LANTERN_CONSENSUS_FIXTURE_DIR}/networking_codec/lstar/networking")

    add_executable(lantern_client_vote_test
        tests/unit/test_client_vote.c
        tests/unit/client_test_helpers.c
    )
    target_link_libraries(lantern_client_vote_test PRIVATE ${LANTERN_TEST_LINK_LIB})
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
    target_link_libraries(lantern_client_pending_test PRIVATE ${LANTERN_TEST_LINK_LIB})
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

    add_executable(lantern_client_gossip_test
        tests/unit/test_client_gossip.c
        tests/unit/client_test_helpers.c
    )
    target_link_libraries(lantern_client_gossip_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    target_include_directories(
        lantern_client_gossip_test
        PRIVATE
            ${PROJECT_SOURCE_DIR}/tests/unit
    )
    target_compile_definitions(
        lantern_client_gossip_test
        PRIVATE
            LANTERN_TEST_FIXTURE_DIR="${PROJECT_SOURCE_DIR}/tests/fixtures"
    )
    add_test(NAME lantern_client_gossip COMMAND lantern_client_gossip_test)

    add_executable(lantern_client_state_staleness_test tests/unit/test_client_state_staleness.c)
    target_link_libraries(lantern_client_state_staleness_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    add_test(NAME lantern_client_state_staleness COMMAND lantern_client_state_staleness_test)

    add_executable(lantern_genesis_anchor_test
        tests/unit/test_genesis_anchor.c
        tests/unit/client_test_helpers.c
    )
    target_link_libraries(lantern_genesis_anchor_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    target_include_directories(
        lantern_genesis_anchor_test
        PRIVATE
            ${PROJECT_SOURCE_DIR}/tests/unit
    )
    target_compile_definitions(
        lantern_genesis_anchor_test
        PRIVATE
            LANTERN_TEST_FIXTURE_DIR="${PROJECT_SOURCE_DIR}/tests/fixtures"
    )
    add_test(NAME lantern_genesis_anchor COMMAND lantern_genesis_anchor_test)

    add_executable(lantern_genesis_bootstrap_test tests/unit/test_genesis_bootstrap.c)
    target_link_libraries(lantern_genesis_bootstrap_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    target_compile_definitions(
        lantern_genesis_bootstrap_test
        PRIVATE
            LANTERN_TEST_FIXTURE_DIR="${PROJECT_SOURCE_DIR}/tests/fixtures"
    )
    add_test(NAME lantern_genesis_bootstrap COMMAND lantern_genesis_bootstrap_test)

    add_executable(lantern_validator_selection_test tests/unit/test_validator_selection.c)
    target_link_libraries(lantern_validator_selection_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    target_compile_definitions(
        lantern_validator_selection_test
        PRIVATE
            LANTERN_TEST_FIXTURE_DIR="${PROJECT_SOURCE_DIR}/tests/fixtures"
    )
    add_test(NAME lantern_validator_selection COMMAND lantern_validator_selection_test)

    add_executable(lantern_rlp_test tests/unit/test_rlp.c)
    target_link_libraries(lantern_rlp_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    add_test(NAME lantern_rlp COMMAND lantern_rlp_test)


    add_executable(lantern_enr_test tests/unit/test_enr.c)
    target_link_libraries(lantern_enr_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    add_test(NAME lantern_enr COMMAND lantern_enr_test)

    add_executable(lantern_ssz_test tests/unit/test_ssz.c)
    target_link_libraries(lantern_ssz_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    add_test(NAME lantern_ssz COMMAND lantern_ssz_test)

    add_executable(lantern_duties_test tests/unit/test_duties.c)
    target_link_libraries(lantern_duties_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    add_test(NAME lantern_duties COMMAND lantern_duties_test)

    add_executable(lantern_signature_test tests/unit/test_signature.c)
    target_link_libraries(lantern_signature_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    add_test(NAME lantern_signature COMMAND lantern_signature_test)
    set_tests_properties(lantern_signature PROPERTIES TIMEOUT 3600)

    add_executable(lantern_fixture_loader_test tests/unit/test_fixture_loader.c)
    target_link_libraries(lantern_fixture_loader_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    target_include_directories(
        lantern_fixture_loader_test
        PRIVATE
            ${PROJECT_SOURCE_DIR}
            ${PROJECT_SOURCE_DIR}/external/jsmn
    )
    add_test(NAME lantern_fixture_loader COMMAND lantern_fixture_loader_test)

    add_executable(lantern_consensus_runtime_test tests/unit/test_consensus_runtime.c)
    target_link_libraries(lantern_consensus_runtime_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    add_test(NAME lantern_consensus_runtime COMMAND lantern_consensus_runtime_test)

    add_executable(lantern_state_test tests/unit/test_state.c)
    target_link_libraries(lantern_state_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    add_test(NAME lantern_state COMMAND lantern_state_test)

    add_executable(lantern_off_head_replay_test tests/unit/test_off_head_replay.c)
    target_link_libraries(lantern_off_head_replay_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    add_test(NAME lantern_off_head_replay COMMAND lantern_off_head_replay_test)
    set_tests_properties(lantern_off_head_replay PROPERTIES TIMEOUT 120)

    add_executable(lantern_slot_clock_test tests/unit/test_slot_clock.c)
    target_link_libraries(lantern_slot_clock_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    add_test(NAME lantern_slot_clock COMMAND lantern_slot_clock_test)

    add_executable(lantern_snappy_test tests/unit/test_snappy.c)
    target_link_libraries(lantern_snappy_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    add_test(NAME lantern_snappy COMMAND lantern_snappy_test)


    add_executable(lantern_networking_messages_test
        tests/unit/test_networking_messages.c
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
            LANTERN_CONSENSUS_FIXTURE_DIR="${LANTERN_CONSENSUS_FIXTURE_DIR}"
    )
    add_test(NAME lantern_networking_messages COMMAND lantern_networking_messages_test)

    add_executable(lantern_reqresp_service_test tests/unit/test_reqresp_service.c)
    target_link_libraries(lantern_reqresp_service_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    target_include_directories(
        lantern_reqresp_service_test
        PRIVATE
            ${PROJECT_SOURCE_DIR}
            ${PROJECT_SOURCE_DIR}/src
            ${PROJECT_SOURCE_DIR}/external/jsmn
    )
    add_test(NAME lantern_reqresp_service COMMAND lantern_reqresp_service_test)

    add_executable(lantern_gossip_block_dump_decode
        tests/unit/test_gossip_block_dump_decode.c
    )
    target_link_libraries(lantern_gossip_block_dump_decode PRIVATE ${LANTERN_TEST_LINK_LIB})
    target_compile_definitions(
        lantern_gossip_block_dump_decode
        PRIVATE
            LANTERN_PROJECT_SOURCE_DIR="${PROJECT_SOURCE_DIR}"
    )

    add_executable(lantern_libp2p_test tests/unit/test_libp2p.c)
    target_link_libraries(lantern_libp2p_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    add_test(NAME lantern_libp2p COMMAND lantern_libp2p_test)

    add_executable(lantern_fork_choice_test tests/unit/test_fork_choice.c)
    target_link_libraries(lantern_fork_choice_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    add_test(NAME lantern_fork_choice COMMAND lantern_fork_choice_test)

    add_executable(lantern_storage_test tests/unit/test_storage.c)
    target_link_libraries(lantern_storage_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    add_test(NAME lantern_storage COMMAND lantern_storage_test)

    add_executable(lantern_metrics_test tests/unit/test_metrics.c)
    target_link_libraries(lantern_metrics_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    add_test(NAME lantern_metrics COMMAND lantern_metrics_test)

    add_executable(lantern_checkpoint_sync_test tests/unit/test_checkpoint_sync_api.c)
    target_link_libraries(lantern_checkpoint_sync_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    add_test(NAME lantern_checkpoint_sync COMMAND lantern_checkpoint_sync_test)

    add_executable(lantern_validator_duties_integration_test tests/integration/test_validator_duties.c)
    target_link_libraries(lantern_validator_duties_integration_test PRIVATE ${LANTERN_TEST_LINK_LIB})
    add_test(NAME lantern_validator_duties_integration COMMAND lantern_validator_duties_integration_test)

    if(EXISTS "${_lantern_state_transition_fixture_dir}" AND EXISTS "${_lantern_fork_choice_fixture_dir}")
        message(STATUS
            "Consensus fixtures found at ${LANTERN_CONSENSUS_FIXTURE_DIR} "
            "— registering lantern_consensus_vectors")
        add_executable(lantern_consensus_vectors_test
            tests/integration/test_consensus_vectors.c
            tests/integration/consensus_fixture_runner.c
        )
        target_link_libraries(lantern_consensus_vectors_test PRIVATE ${LANTERN_TEST_LINK_LIB})
        target_include_directories(
            lantern_consensus_vectors_test
            PRIVATE
                ${PROJECT_SOURCE_DIR}
                ${PROJECT_SOURCE_DIR}/external/jsmn
        )
        target_compile_definitions(
            lantern_consensus_vectors_test
            PRIVATE
                LANTERN_CONSENSUS_FIXTURE_DIR="${LANTERN_CONSENSUS_FIXTURE_DIR}"
        )
        add_test(NAME lantern_consensus_vectors COMMAND lantern_consensus_vectors_test)
        # Consensus fixtures iterate over dozens of LeanSpec transitions and need a longer timeout.
        set_tests_properties(lantern_consensus_vectors PROPERTIES TIMEOUT 300)
    else()
        message(STATUS
            "Consensus state-transition/fork-choice fixtures not found at ${LANTERN_CONSENSUS_FIXTURE_DIR} "
            "— skipping lantern_consensus_vectors")
    endif()

    if(EXISTS "${_lantern_verify_signatures_fixture_dir}")
        message(STATUS
            "Verify-signatures fixtures found at ${LANTERN_CONSENSUS_FIXTURE_DIR} "
            "— registering lantern_verify_signatures_vectors")
        add_executable(lantern_verify_signatures_vectors_test
            tests/integration/test_verify_signatures_vectors.c
        )
        target_link_libraries(lantern_verify_signatures_vectors_test PRIVATE ${LANTERN_TEST_LINK_LIB})
        target_include_directories(
            lantern_verify_signatures_vectors_test
            PRIVATE
                ${PROJECT_SOURCE_DIR}
                ${PROJECT_SOURCE_DIR}/external/jsmn
        )
        target_compile_definitions(
            lantern_verify_signatures_vectors_test
            PRIVATE
                LANTERN_CONSENSUS_FIXTURE_DIR="${LANTERN_CONSENSUS_FIXTURE_DIR}"
        )
        add_test(NAME lantern_verify_signatures_vectors COMMAND lantern_verify_signatures_vectors_test)
        set_tests_properties(lantern_verify_signatures_vectors PROPERTIES TIMEOUT 120)
    else()
        message(STATUS
            "Verify-signatures fixtures not found at ${LANTERN_CONSENSUS_FIXTURE_DIR} "
            "— skipping lantern_verify_signatures_vectors")
    endif()

    if(EXISTS "${_lantern_state_transition_fixture_dir}")
        message(STATUS
            "State-transition fixtures found at ${LANTERN_CONSENSUS_FIXTURE_DIR} "
            "— registering lantern_genesis_vectors")
        add_executable(lantern_genesis_vectors_test
            tests/integration/test_genesis_vectors.c
            tests/integration/consensus_fixture_runner.c
        )
        target_link_libraries(lantern_genesis_vectors_test PRIVATE ${LANTERN_TEST_LINK_LIB})
        target_include_directories(
            lantern_genesis_vectors_test
            PRIVATE
                ${PROJECT_SOURCE_DIR}
                ${PROJECT_SOURCE_DIR}/external/jsmn
        )
        target_compile_definitions(
            lantern_genesis_vectors_test
            PRIVATE
                LANTERN_CONSENSUS_FIXTURE_DIR="${LANTERN_CONSENSUS_FIXTURE_DIR}"
        )
        add_test(NAME lantern_genesis_vectors COMMAND lantern_genesis_vectors_test)
        set_tests_properties(lantern_genesis_vectors PROPERTIES TIMEOUT 120)
    else()
        message(STATUS
            "State-transition fixtures not found at ${LANTERN_CONSENSUS_FIXTURE_DIR} "
            "— skipping lantern_genesis_vectors")
    endif()

    if(EXISTS "${_lantern_ssz_fixture_dir}")
        message(STATUS
            "SSZ fixtures found at ${LANTERN_CONSENSUS_FIXTURE_DIR} "
            "— registering lantern_ssz_vectors")
        add_executable(lantern_ssz_vectors_test
            tests/integration/test_ssz_vectors.c
        )
        target_link_libraries(lantern_ssz_vectors_test PRIVATE ${LANTERN_TEST_LINK_LIB})
        target_include_directories(
            lantern_ssz_vectors_test
            PRIVATE
                ${PROJECT_SOURCE_DIR}
                ${PROJECT_SOURCE_DIR}/external/jsmn
        )
        target_compile_definitions(
            lantern_ssz_vectors_test
            PRIVATE
                LANTERN_CONSENSUS_FIXTURE_DIR="${LANTERN_CONSENSUS_FIXTURE_DIR}"
        )
        add_test(NAME lantern_ssz_vectors COMMAND lantern_ssz_vectors_test)
        set_tests_properties(lantern_ssz_vectors PROPERTIES TIMEOUT 180)
    else()
        message(STATUS
            "SSZ fixtures not found at ${LANTERN_CONSENSUS_FIXTURE_DIR} "
            "— skipping lantern_ssz_vectors")
    endif()

    if(EXISTS "${_lantern_networking_codec_fixture_dir}")
        message(STATUS
            "Networking-codec fixtures found at ${LANTERN_CONSENSUS_FIXTURE_DIR} "
            "— registering lantern_networking_codec_vectors")
        add_executable(lantern_networking_codec_vectors_test
            tests/integration/test_networking_codec_vectors.c
        )
        target_link_libraries(lantern_networking_codec_vectors_test PRIVATE ${LANTERN_TEST_LINK_LIB})
        target_include_directories(
            lantern_networking_codec_vectors_test
            PRIVATE
                ${PROJECT_SOURCE_DIR}
                ${PROJECT_SOURCE_DIR}/external/jsmn
        )
        target_compile_definitions(
            lantern_networking_codec_vectors_test
            PRIVATE
                LANTERN_CONSENSUS_FIXTURE_DIR="${LANTERN_CONSENSUS_FIXTURE_DIR}"
        )
        add_test(NAME lantern_networking_codec_vectors COMMAND lantern_networking_codec_vectors_test)
        set_tests_properties(lantern_networking_codec_vectors PROPERTIES TIMEOUT 180)
    else()
        message(STATUS
            "Networking-codec fixtures not found at ${LANTERN_CONSENSUS_FIXTURE_DIR} "
            "— skipping lantern_networking_codec_vectors")
    endif()

    set(_lantern_ctest_targets
        lantern_client_vote
        lantern_client_pending
        lantern_client_state_staleness
        lantern_genesis_anchor
        lantern_genesis_bootstrap
        lantern_validator_selection
        lantern_rlp
        lantern_enr
        lantern_ssz
        lantern_duties
        lantern_consensus_runtime
        lantern_state
        lantern_off_head_replay
        lantern_slot_clock
        lantern_snappy
        lantern_networking_messages
        lantern_reqresp_service
        lantern_libp2p
        lantern_fork_choice
        lantern_storage
        lantern_metrics
        lantern_validator_duties_integration
    )
    set_property(TEST ${_lantern_ctest_targets} PROPERTY TIMEOUT 30)
    set_tests_properties(lantern_client_pending PROPERTIES TIMEOUT 90)
    set_tests_properties(lantern_client_vote PROPERTIES TIMEOUT 300)
    set_tests_properties(lantern_state PROPERTIES TIMEOUT 300)

    get_property(_lantern_build_targets DIRECTORY PROPERTY BUILDSYSTEM_TARGETS)
    foreach(_lantern_target IN LISTS _lantern_build_targets)
        if(_lantern_target MATCHES "^lantern_.*_test$")
            target_compile_options(
                ${_lantern_target}
                PRIVATE
                    $<$<COMPILE_LANG_AND_ID:C,AppleClang,Clang,GNU>:-UNDEBUG>
            )
        endif()
    endforeach()

endif()
