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
        if(NOT EXISTS ${source_dir}/CMakeLists.txt)
            message(FATAL_ERROR "Missing c-ssz sources at ${source_dir}. Run scripts/bootstrap.sh to fetch git submodules.")
        endif()
        if(NOT EXISTS ${source_dir}/external/aws-lc/CMakeLists.txt)
            message(FATAL_ERROR "Missing AWS-LC sources at ${source_dir}/external/aws-lc. Run git submodule update --init --recursive external/c-ssz.")
        endif()

        set(SSZ_USE_SYSTEM_CRYPTO OFF CACHE BOOL "Build c-ssz against vendored AWS-LC" FORCE)
        set(SSZ_BUILD_TESTS OFF CACHE BOOL "Do not build c-ssz tests from Lantern" FORCE)
        set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
        set(BUILD_LIBSSL OFF CACHE BOOL "" FORCE)
        set(BUILD_TOOL OFF CACHE BOOL "" FORCE)
        set(DISABLE_GO ON CACHE BOOL "" FORCE)
        set(DISABLE_PERL ON CACHE BOOL "" FORCE)

        if(NOT TARGET ssz)
            add_subdirectory(${source_dir} ${CMAKE_BINARY_DIR}/c-ssz EXCLUDE_FROM_ALL)
            set_property(DIRECTORY ${CMAKE_BINARY_DIR}/c-ssz PROPERTY EXCLUDE_FROM_TESTING TRUE)
        endif()

        add_library(${target_name} INTERFACE)
        target_link_libraries(${target_name} INTERFACE ssz)
    endif()
endfunction()

function(_lantern_configure_awslc_openssl_package source_dir)
    if(NOT TARGET crypto)
        message(FATAL_ERROR "AWS-LC crypto target must exist before configuring the OpenSSL package shim.")
    endif()

    set(_awslc_include_dir "${source_dir}/external/aws-lc/include")
    set(_openssl_config_dir "${CMAKE_BINARY_DIR}/aws-lc-openssl")
    file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/c-ssz/external/aws-lc/symbol_prefix_include")
    file(MAKE_DIRECTORY "${_openssl_config_dir}")
    file(WRITE "${_openssl_config_dir}/picotls_awslc_compat.h"
"#ifndef LANTERN_PICOTLS_AWSLC_COMPAT_H
#define LANTERN_PICOTLS_AWSLC_COMPAT_H
#include <picotls/openssl.h>
#if defined(OPENSSL_IS_AWSLC) && defined(PTLS_OPENSSL_HAVE_CHACHA20_POLY1305) && !PTLS_OPENSSL_HAVE_CHACHA20_POLY1305
#undef PTLS_OPENSSL_HAVE_CHACHA20_POLY1305
#endif
#endif
")
    file(WRITE "${_openssl_config_dir}/OpenSSLConfig.cmake"
"set(OpenSSL_FOUND TRUE)
set(OPENSSL_FOUND TRUE)
set(OpenSSL_VERSION \"3.0.0\")
set(OPENSSL_VERSION \"3.0.0\")
set(OPENSSL_INCLUDE_DIR \"${_awslc_include_dir}\")
set(OPENSSL_INCLUDE_DIRS \"${_awslc_include_dir}\")
set(OpenSSL_Crypto_FOUND TRUE)
set(OpenSSL_SSL_FOUND TRUE)
if(NOT TARGET OpenSSL::Crypto)
    add_library(OpenSSL::Crypto INTERFACE IMPORTED)
    set_target_properties(OpenSSL::Crypto PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES \"${_awslc_include_dir}\"
        INTERFACE_COMPILE_DEFINITIONS \"OPENSSL_NO_CHACHA;OPENSSL_NO_POLY1305\")
    target_link_libraries(OpenSSL::Crypto INTERFACE crypto)
endif()
if(NOT TARGET OpenSSL::SSL)
    add_library(OpenSSL::SSL INTERFACE IMPORTED)
    set_target_properties(OpenSSL::SSL PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES \"${_awslc_include_dir}\"
        INTERFACE_COMPILE_DEFINITIONS \"OPENSSL_NO_CHACHA;OPENSSL_NO_POLY1305\")
    target_link_libraries(OpenSSL::SSL INTERFACE OpenSSL::Crypto)
endif()
set(OPENSSL_CRYPTO_LIBRARY OpenSSL::Crypto)
set(OPENSSL_CRYPTO_LIBRARIES OpenSSL::Crypto)
set(OPENSSL_SSL_LIBRARY OpenSSL::SSL)
set(OPENSSL_SSL_LIBRARIES OpenSSL::SSL)
set(OPENSSL_LIBRARIES OpenSSL::Crypto)
")
    set(OpenSSL_DIR "${_openssl_config_dir}" CACHE PATH "Resolve OpenSSL-compatible consumers to vendored AWS-LC" FORCE)
    set(OPENSSL_ROOT_DIR "${source_dir}/external/aws-lc" CACHE PATH "Vendored AWS-LC root" FORCE)
    set(OPENSSL_INCLUDE_DIR "${_awslc_include_dir}" CACHE PATH "Vendored AWS-LC OpenSSL-compatible headers" FORCE)
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
    _lantern_configure_awslc_openssl_package(${external_root}/c-ssz)
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
            set(_saved_find_package_prefer_config "${CMAKE_FIND_PACKAGE_PREFER_CONFIG}")
            set(CMAKE_FIND_PACKAGE_PREFER_CONFIG TRUE)
            set(FETCHCONTENT_BASE_DIR ${CMAKE_BINARY_DIR}/c-libp2p/_deps)
            add_subdirectory(${libp2p_source_dir} ${CMAKE_BINARY_DIR}/c-libp2p EXCLUDE_FROM_ALL)
            set_property(DIRECTORY ${CMAKE_BINARY_DIR}/c-libp2p PROPERTY EXCLUDE_FROM_TESTING TRUE)
            set(FETCHCONTENT_BASE_DIR "${_saved_fetchcontent_basedir}")
            set(CMAKE_FIND_PACKAGE_PREFER_CONFIG "${_saved_find_package_prefer_config}")
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
            if(TARGET picoquic-core)
                target_compile_options(picoquic-core PRIVATE -include "${CMAKE_BINARY_DIR}/aws-lc-openssl/picotls_awslc_compat.h")
                if(APPLE)
                    target_compile_definitions(picoquic-core PRIVATE __APPLE_USE_RFC_3542)
                endif()
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
