function(_lantern_define_interface target_name source_dir)
    if(NOT TARGET ${target_name})
        add_library(${target_name} INTERFACE)
    endif()

    if(EXISTS ${source_dir}/include)
        target_include_directories(${target_name} INTERFACE ${source_dir}/include)
    elseif(EXISTS ${source_dir})
        message(WARNING "${target_name} has no include directory at ${source_dir}/include")
    else()
        message(WARNING "Missing dependency sources at ${source_dir}. Run scripts/bootstrap.sh to fetch git submodules.")
    endif()
endfunction()

function(_lantern_define_static target_name source_dir)
    if(NOT TARGET ${target_name})
        add_library(${target_name} STATIC
            ${source_dir}/src/ssz_constants.c
            ${source_dir}/src/ssz_deserialize.c
            ${source_dir}/src/ssz_merkle.c
            ${source_dir}/src/ssz_serialize.c
            ${source_dir}/src/ssz_utils.c
            ${source_dir}/lib/mincrypt/sha256.c
        )
        target_include_directories(${target_name}
            PUBLIC
                ${source_dir}/include
                ${source_dir}/lib
        )
        # Ensure POSIX-sized types (e.g., ssize_t) are available without editing the submodule.
        target_compile_options(${target_name}
            PRIVATE
                -include sys/types.h
        )
    endif()
endfunction()

find_program(CARGO_EXECUTABLE cargo)
if(NOT CARGO_EXECUTABLE)
    message(FATAL_ERROR "cargo is required to build post-quantum signature bindings. Install Rust (https://rustup.rs/) and ensure cargo is on PATH.")
endif()

function(_lantern_define_snappy target_name source_dir)
    if(NOT TARGET ${target_name})
        add_library(${target_name} STATIC
            ${source_dir}/snappy.c
        )
        target_include_directories(${target_name}
            PUBLIC
                ${source_dir}
        )
        target_compile_definitions(${target_name}
            PUBLIC
                NDEBUG=1
                _DEFAULT_SOURCE
            PRIVATE
                typeof=__typeof__
        )
    endif()
endfunction()

function(_lantern_define_c_leanvm_xmss_variant target_name source_dir cargo_target_dir header_dir)
    set(options TEST_CONFIG)
    cmake_parse_arguments(C_XMSS "${options}" "" "" ${ARGN})

    if(TARGET ${target_name})
        return()
    endif()

    set(c_leanvm_xmss_output
        "${cargo_target_dir}/release/${CMAKE_STATIC_LIBRARY_PREFIX}leanvm_xmss_c${CMAKE_STATIC_LIBRARY_SUFFIX}"
    )
    set(c_leanvm_xmss_header "${header_dir}/leanvm-xmss.h")
    set(c_leanvm_xmss_compat_header "${header_dir}/pq-bindings-c-rust.h")
    set(c_leanvm_xmss_args build --release --locked)
    file(MAKE_DIRECTORY "${header_dir}")
    if(C_XMSS_TEST_CONFIG)
        list(APPEND c_leanvm_xmss_args --features test-config)
    endif()

    add_custom_command(
        OUTPUT "${c_leanvm_xmss_output}" "${c_leanvm_xmss_header}" "${c_leanvm_xmss_compat_header}"
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${header_dir}"
        COMMAND
            "${CMAKE_COMMAND}" -E env
            "CARGO_TARGET_DIR=${cargo_target_dir}"
            "LEANVM_XMSS_HEADER_DIR=${header_dir}"
            "${CARGO_EXECUTABLE}" ${c_leanvm_xmss_args}
        COMMAND
            "${CMAKE_COMMAND}" -E copy_if_different
            "${source_dir}/include/pq-bindings-c-rust.h"
            "${c_leanvm_xmss_compat_header}"
        WORKING_DIRECTORY "${source_dir}"
        DEPENDS
            "${source_dir}/Cargo.toml"
            "${source_dir}/Cargo.lock"
            "${source_dir}/build.rs"
            "${source_dir}/cbindgen.toml"
            "${source_dir}/src/lib.rs"
        COMMENT "Building c-leanvm-xmss Rust bindings${C_XMSS_TEST_CONFIG}"
        VERBATIM
    )

    add_custom_target(${target_name}_build DEPENDS "${c_leanvm_xmss_output}" "${c_leanvm_xmss_header}" "${c_leanvm_xmss_compat_header}")

    add_library(${target_name} STATIC IMPORTED GLOBAL)
    set_target_properties(${target_name}
        PROPERTIES
            IMPORTED_LOCATION "${c_leanvm_xmss_output}"
            INTERFACE_INCLUDE_DIRECTORIES "${header_dir}"
    )
    if(C_XMSS_TEST_CONFIG)
        set_target_properties(${target_name}
            PROPERTIES
                INTERFACE_COMPILE_DEFINITIONS "LANTERN_SIGNATURE_SIZE=424"
        )
    endif()

    add_dependencies(${target_name} ${target_name}_build)
endfunction()

function(lantern_configure_dependencies target)
    set(wrapper_target "lantern_c_leanvm_xmss")
    if(ARGC GREATER 1)
        set(wrapper_target "${ARGV1}")
    endif()

    if(NOT TARGET ${target})
        message(FATAL_ERROR "lantern_configure_dependencies expects an existing CMake target")
    endif()

    set(external_root ${PROJECT_SOURCE_DIR}/external)

    _lantern_define_interface(lantern_libp2p ${external_root}/c-libp2p)
    _lantern_define_static(lantern_c_ssz ${external_root}/c-ssz)
    _lantern_define_snappy(lantern_snappy_c ${external_root}/snappy-c)
    _lantern_define_c_leanvm_xmss_variant(
        lantern_c_leanvm_xmss
        ${external_root}/c-leanvm-xmss
        ${CMAKE_BINARY_DIR}/c-leanvm-xmss/prod
        ${CMAKE_BINARY_DIR}/c-leanvm-xmss/prod/include
    )
    _lantern_define_c_leanvm_xmss_variant(
        lantern_c_leanvm_xmss_test
        ${external_root}/c-leanvm-xmss
        ${CMAKE_BINARY_DIR}/c-leanvm-xmss/test
        ${CMAKE_BINARY_DIR}/c-leanvm-xmss/test/include
        TEST_CONFIG
    )

    set(libp2p_source_dir ${external_root}/c-libp2p)
    if(EXISTS ${libp2p_source_dir}/CMakeLists.txt)
        if(NOT TARGET libp2p_unified)
            # c-libp2p builds numerous component libraries (sha3, libtomcrypt, etc.)
            # that expose identically named symbols.  When these components are
            # forced to build as static archives (BUILD_SHARED_LIBS=OFF) the final
            # link step for lantern_cli pulls both archives into a single binary
            # and the duplicate SHA3/Keccak symbols collide, causing cmake to hang
            # inside the linker until it times out.  Let the subproject build
            # shared objects so each archive keeps its own namespace.
            if(DEFINED BUILD_SHARED_LIBS)
                set(_lantern_prev_build_shared_libs "${BUILD_SHARED_LIBS}")
                set(_lantern_had_build_shared_libs TRUE)
            else()
                set(_lantern_prev_build_shared_libs "")
                set(_lantern_had_build_shared_libs FALSE)
            endif()
            set(BUILD_SHARED_LIBS ON CACHE BOOL "Build shared libraries" FORCE)
            set(ENABLE_COVERAGE OFF CACHE BOOL "Disable coverage when building c-libp2p as a dependency" FORCE)
            if(DEFINED CMAKE_POSITION_INDEPENDENT_CODE)
                set(_lantern_had_pic TRUE)
                set(_lantern_prev_pic "${CMAKE_POSITION_INDEPENDENT_CODE}")
            else()
                set(_lantern_had_pic FALSE)
                set(_lantern_prev_pic "")
            endif()
            set(CMAKE_POSITION_INDEPENDENT_CODE ON)
            set(_saved_fetchcontent_basedir "${FETCHCONTENT_BASE_DIR}")
            set(FETCHCONTENT_BASE_DIR ${CMAKE_BINARY_DIR}/c-libp2p/_deps)
            add_subdirectory(${libp2p_source_dir} ${CMAKE_BINARY_DIR}/c-libp2p EXCLUDE_FROM_ALL)
            set_property(DIRECTORY ${CMAKE_BINARY_DIR}/c-libp2p PROPERTY EXCLUDE_FROM_TESTING TRUE)
            set(FETCHCONTENT_BASE_DIR "${_saved_fetchcontent_basedir}")
            if(_lantern_had_build_shared_libs)
                set(BUILD_SHARED_LIBS "${_lantern_prev_build_shared_libs}" CACHE BOOL "Build shared libraries" FORCE)
            else()
                unset(BUILD_SHARED_LIBS CACHE)
            endif()
            if(_lantern_had_pic)
                set(CMAKE_POSITION_INDEPENDENT_CODE "${_lantern_prev_pic}")
            else()
                unset(CMAKE_POSITION_INDEPENDENT_CODE)
            endif()
            if(TARGET libtomcrypt)
                target_include_directories(libtomcrypt PRIVATE ${libp2p_source_dir}/external/libtommath)
                target_include_directories(libtomcrypt PRIVATE ${libp2p_source_dir}/external/libtomcrypt/src/headers)
            endif()
            if(TARGET secp256k1)
                # The shared libp2p peer-id target links against secp256k1; force PIC to avoid linker failures on Linux.
                set_target_properties(secp256k1 PROPERTIES POSITION_INDEPENDENT_CODE ON)
            endif()
            if(TARGET libp2p_unified)
                target_include_directories(libp2p_unified PUBLIC ${libp2p_source_dir})
            endif()
            set(libp2p_binary_dir ${CMAKE_BINARY_DIR}/c-libp2p)
            if(TARGET protocol_quic)
                target_include_directories(protocol_quic PRIVATE ${libp2p_binary_dir}/_deps/picotls-src/include)
                target_include_directories(protocol_quic PRIVATE ${libp2p_source_dir})
                target_include_directories(protocol_quic PRIVATE ${libp2p_source_dir}/include/libp2p)
                target_include_directories(
                    protocol_quic PRIVATE ${libp2p_source_dir}/external/libtomcrypt/src/headers)
                if(EXISTS ${CMAKE_BINARY_DIR}/_deps/picotls-src/include)
                    target_include_directories(
                        protocol_quic PRIVATE ${CMAKE_BINARY_DIR}/_deps/picotls-src/include)
                endif()
            endif()
            if(TARGET protocol_noise)
                target_include_directories(protocol_noise PRIVATE ${libp2p_binary_dir}/_deps/picotls-src/include)
                target_include_directories(protocol_noise PRIVATE ${libp2p_source_dir})
                target_include_directories(protocol_noise PRIVATE ${libp2p_source_dir}/include/libp2p)
                target_include_directories(
                    protocol_noise PRIVATE ${libp2p_source_dir}/external/libtomcrypt/src/headers)
                if(EXISTS ${CMAKE_BINARY_DIR}/_deps/picotls-src/include)
                    target_include_directories(
                        protocol_noise PRIVATE ${CMAKE_BINARY_DIR}/_deps/picotls-src/include)
                endif()
            endif()
        endif()
    else()
        message(FATAL_ERROR "Missing c-libp2p sources at ${libp2p_source_dir}. Run scripts/bootstrap.sh to fetch git submodules.")
    endif()

    target_link_libraries(${target}
        PUBLIC
            lantern_libp2p
            lantern_c_ssz
            lantern_snappy_c
            ${wrapper_target}
            libp2p_unified
            protocol_gossipsub
            protocol_ping
    )

    if(CMAKE_DL_LIBS)
        target_link_libraries(${target} PUBLIC ${CMAKE_DL_LIBS})
    endif()

    if(NOT WIN32)
        target_link_libraries(${target} PUBLIC m)
    endif()
endfunction()
