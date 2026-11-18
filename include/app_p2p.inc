/*
 * The libp2p Config of the binary (asm-libp2p docs/reference/node.md, Type Config), in RODATA: the
 * LIBP2P_CFG_FIXED bytes before the protocols. The values of asm-libp2p's mainnet test node
 * (tests/mainnet/node.c), with TCP only. lantern_app_main sets size, private_key, entropy, now,
 * protocols and protocols_count. The same on every ISA.
 */
    .p2align 3
app_p2p_config:
    .quad 0                                    /* 0 */
    .quad LIBP2P_KEY_SECP256K1                /* 8 key_type */
    .quad 0                                    /* 16 */
    .quad 0                                    /* 24 */
    .quad 0                                    /* 32 */
    .quad 0                                    /* 40 */
    .quad 0                                    /* 48 */
    .quad 0                                    /* 56 */
    .quad 0                                    /* 64 */
    .quad 0                                    /* 72 */
    .quad 0                                    /* 80 */
    .quad 128                                 /* 88 max_connections */
    .quad 4096                                /* 96 max_streams */
    .quad 128                                 /* 104 max_peers */
    .quad 256                                 /* 112 max_topics */
    .quad 1 << 30                             /* 120 heap_size */
    .quad 65536                               /* 128 seen_capacity */
    .quad 8192                                /* 136 mcache_capacity */
    .quad 4096                                /* 144 pending_capacity */
    .quad 3                                   /* 152 muxers: yamux, mplex */
    .quad 1 << 20                             /* 160 send_window */
    .quad 11 << 20                            /* 168 max_rpc */
    .quad 10 << 20                            /* 176 max_data */
    .quad 10000                               /* 184 handshake_ms */
    .quad 5000                                /* 192 validation_ms */
    .quad 1 << 20                             /* 200 stream_queue */
    .quad 0                                    /* 208 */
    .quad 0                                    /* 216 */
    .quad 8                                   /* 224 d */
    .quad 6                                   /* 232 d_low */
    .quad 12                                  /* 240 d_high */
    .quad 6                                   /* 248 d_lazy */
    .quad 4                                   /* 256 d_score */
    .quad 2                                   /* 264 d_out */
    .quad 700                                 /* 272 heartbeat_ms */
    .quad 60000                               /* 280 fanout_ttl_ms */
    .quad 6                                   /* 288 mcache_len */
    .quad 3                                   /* 296 mcache_gossip */
    .quad 384000                              /* 304 seen_ttl_ms */
    .quad 60000                               /* 312 prune_backoff_ms */
    .quad 10000                               /* 320 unsub_backoff_ms */
    .quad 10000                               /* 328 graft_flood_ms */
    .quad 1                                   /* 336 flood_publish */
    .quad 0x3fd0000000000000                    /* 344 gossip_factor: 0.25 as an f64 */
    .quad 5000                                /* 352 max_ihave_length */
    .quad 10                                  /* 360 max_ihave_messages */
    .quad 3000                                /* 368 iwant_followup_ms */
    .quad 3                                   /* 376 retransmission */
    .quad 60                                  /* 384 opportunistic_ticks */
    .quad 2                                   /* 392 opportunistic_peers */
    .quad 0                                    /* 400 */
    .quad 0                                    /* 408 */
    .quad 0                                    /* 416 */
    .quad 0                                    /* 424 */
    .quad 0                                    /* 432 */
    .quad 0                                    /* 440 */
    .quad 0                                    /* 448 */
    .quad 0                                    /* 456 */
    .quad 0                                    /* 464 */
    .quad 0                                    /* 472 */
    .quad 0                                    /* 480 */
    .quad 0                                    /* 488 */
    .quad 0                                    /* 496 */
    .quad 0                                    /* 504 */
    .quad 0                                    /* 512 */
    .quad 0                                    /* 520 */
    .quad 13                                    /* 528 agent_len */
    .ascii "lantern/0.1.0"                       /* 536 agent */
    .space 64 - 13
    .quad 10                                    /* 600 pv_len */
    .ascii "eth2/1.0.0"                          /* 608 pv */
    .space 32 - 10
    .quad 1                                   /* 640 gossipsub_v12 */
    .quad 1024                                /* 648 idontwant_threshold */
    .quad 256                                 /* 656 dontwant_slots */
    .quad 3                                   /* 664 dontwant_ttl */
    .quad 1000                                /* 672 max_idontwant_messages */
    .quad 10                                  /* 680 max_idontwant_length */
    .quad 1                                   /* 688 gossipsub_v13 */
    .quad 0                                    /* 696 */
    .quad 0                                    /* 704 */
    .quad 0                                    /* 712 */
    .quad 0                                    /* 720 */
    .quad 0                                    /* 728 */
    .quad 0                                    /* 736 */
    .quad 0                                    /* 744 */
    .quad 0                                    /* 752 */
    .quad 0                                    /* 760 */
    .quad 0                                    /* 768 */
app_p2p_config_end:
.if app_p2p_config_end - app_p2p_config - LIBP2P_CFG_FIXED
.error "app_p2p_config is not LIBP2P_CFG_FIXED bytes"
.endif
