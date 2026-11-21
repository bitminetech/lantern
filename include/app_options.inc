/*
 * The command line options of lantern_app_options (docs/reference/app.md), in RODATA: each
 * record is the name's length, its AppOptions field, its kind, then the name in 24 bytes.
 * The same on every ISA.
 */
.set APP_OPTION_TEXT, 0                 /* an Arg */
.set APP_OPTION_ENDPOINT, 1             /* an Arg, without http:// */
.set APP_OPTION_PORT, 2                 /* 1 to 65535 */
.set APP_OPTION_PEERS, 3                /* 1 to APP_MAX_TARGET_PEERS */
.set APP_OPTION_ADDRESS, 4              /* an IPv4 address */
.set APP_OPTION_LEVEL, 5                /* error, warn, info or debug: 0 to 3 */
.set APP_OPTION_CONNECTIONS, 6          /* 1 to APP_MAX_HTTP_CONNECTIONS */
.set APP_OPTION_FLAG, 7                 /* no value: 1 */
.set APP_OPTION_BYTES, 48

    .p2align 3
app_options:
    .quad 11, AppOptions_network_dir, APP_OPTION_TEXT
    .ascii "network-dir"
    .space 24 - 11
    .quad 18, AppOptions_execution, APP_OPTION_ENDPOINT
    .ascii "execution-endpoint"
    .space 24 - 18
    .quad 10, AppOptions_jwt_secret, APP_OPTION_TEXT
    .ascii "jwt-secret"
    .space 24 - 10
    .quad 10, AppOptions_boot_nodes, APP_OPTION_TEXT
    .ascii "boot-nodes"
    .space 24 - 10
    .quad 4, AppOptions_port, APP_OPTION_PORT
    .ascii "port"
    .space 24 - 4
    .quad 11, AppOptions_enr_address, APP_OPTION_ADDRESS
    .ascii "enr-address"
    .space 24 - 11
    .quad 9, AppOptions_http_port, APP_OPTION_PORT
    .ascii "http-port"
    .space 24 - 9
    .quad 12, AppOptions_http_address, APP_OPTION_ADDRESS
    .ascii "http-address"
    .space 24 - 12
    .quad 20, AppOptions_http_max_connections, APP_OPTION_CONNECTIONS
    .ascii "http-max-connections"
    .space 24 - 20
    .quad 12, AppOptions_target_peers, APP_OPTION_PEERS
    .ascii "target-peers"
    .space 24 - 12
    .quad 8, AppOptions_data_dir, APP_OPTION_TEXT
    .ascii "data-dir"
    .space 24 - 8
    .quad 16, AppOptions_checkpoint_state, APP_OPTION_TEXT
    .ascii "checkpoint-state"
    .space 24 - 16
    .quad 16, AppOptions_checkpoint_block, APP_OPTION_TEXT
    .ascii "checkpoint-block"
    .space 24 - 16
    .quad 9, AppOptions_log_level, APP_OPTION_LEVEL
    .ascii "log-level"
    .space 24 - 9
    .quad 9, AppOptions_supernode, APP_OPTION_FLAG
    .ascii "supernode"
    .space 24 - 9
    .quad 7, AppOptions_builder, APP_OPTION_ENDPOINT
    .ascii "builder"
    .space 24 - 7
app_options_end:
app_levels:                             /* the name of each log level in 8 bytes, then their lengths */
    .ascii "error"
    .space 3
    .ascii "warn"
    .space 4
    .ascii "info"
    .space 4
    .ascii "debug"
    .space 3
app_level_lengths:
    .byte 5, 4, 4, 5
app_http:
    .ascii "http://"
