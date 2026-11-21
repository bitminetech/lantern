/*
 * The texts of the eth1 follower's requests and the names its parsers read (docs/reference/eth1.md),
 * and the encoding of a DepositEvent log's data with its values zero, as read only data for
 * asm/core/<ISA>/eth1.s, which includes this file in read only data, before its code.
 */
e1_open:
    .ascii  "{\"jsonrpc\":\"2.0\",\"id\":"
e1_open_end:
.set e1_open_len, 22
.if e1_open_end - e1_open != e1_open_len
.error "the length of e1_open is wrong"
.endif
e1_block:
    .ascii  ",\"method\":\"eth_getBlockByNumber\",\"params\":[\""
e1_block_end:
.set e1_block_len, 44
.if e1_block_end - e1_block != e1_block_len
.error "the length of e1_block is wrong"
.endif
e1_latest:
    .ascii  "latest"
e1_latest_end:
.set e1_latest_len, 6
.if e1_latest_end - e1_latest != e1_latest_len
.error "the length of e1_latest is wrong"
.endif
e1_bclose:
    .ascii  "\",false]}"
e1_bclose_end:
.set e1_bclose_len, 9
.if e1_bclose_end - e1_bclose != e1_bclose_len
.error "the length of e1_bclose is wrong"
.endif
e1_logs:
    .ascii  ",\"method\":\"eth_getLogs\",\"params\":[{\"address\":\"0x"
e1_logs_end:
.set e1_logs_len, 48
.if e1_logs_end - e1_logs != e1_logs_len
.error "the length of e1_logs is wrong"
.endif
e1_topics:
    .ascii  "\",\"topics\":[\"0x649bbc62d0e31342afea4e5cd82d4049e7e1ee912fc0889aa790803be39038c5\"],\"fromBlock\":\""
e1_topics_end:
.set e1_topics_len, 95
.if e1_topics_end - e1_topics != e1_topics_len
.error "the length of e1_topics is wrong"
.endif
e1_to:
    .ascii  "\",\"toBlock\":\""
e1_to_end:
.set e1_to_len, 13
.if e1_to_end - e1_to != e1_to_len
.error "the length of e1_to is wrong"
.endif
e1_lclose:
    .ascii  "\"}]}"
e1_lclose_end:
.set e1_lclose_len, 4
.if e1_lclose_end - e1_lclose != e1_lclose_len
.error "the length of e1_lclose is wrong"
.endif
e1_n_number:
    .ascii  "number"
e1_n_number_end:
.set e1_n_number_len, 6
.if e1_n_number_end - e1_n_number != e1_n_number_len
.error "the length of e1_n_number is wrong"
.endif
e1_n_hash:
    .ascii  "hash"
e1_n_hash_end:
.set e1_n_hash_len, 4
.if e1_n_hash_end - e1_n_hash != e1_n_hash_len
.error "the length of e1_n_hash is wrong"
.endif
e1_n_timestamp:
    .ascii  "timestamp"
e1_n_timestamp_end:
.set e1_n_timestamp_len, 9
.if e1_n_timestamp_end - e1_n_timestamp != e1_n_timestamp_len
.error "the length of e1_n_timestamp is wrong"
.endif
e1_n_removed:
    .ascii  "removed"
e1_n_removed_end:
.set e1_n_removed_len, 7
.if e1_n_removed_end - e1_n_removed != e1_n_removed_len
.error "the length of e1_n_removed is wrong"
.endif
e1_n_block_number:
    .ascii  "blockNumber"
e1_n_block_number_end:
.set e1_n_block_number_len, 11
.if e1_n_block_number_end - e1_n_block_number != e1_n_block_number_len
.error "the length of e1_n_block_number is wrong"
.endif
e1_n_topics:
    .ascii  "topics"
e1_n_topics_end:
.set e1_n_topics_len, 6
.if e1_n_topics_end - e1_n_topics != e1_n_topics_len
.error "the length of e1_n_topics is wrong"
.endif
e1_n_data:
    .ascii  "data"
e1_n_data_end:
.set e1_n_data_len, 4
.if e1_n_data_end - e1_n_data != e1_n_data_len
.error "the length of e1_n_data is wrong"
.endif
/* The 576 bytes of the deposit contract's DepositEvent data: the five offsets and lengths, the values zero. */
e1_abi:
    .space  31
    .byte   0xa0
    .space  30
    .byte   0x01, 0x00
    .space  30
    .byte   0x01, 0x40
    .space  30
    .byte   0x01, 0x80
    .space  30
    .byte   0x02, 0x00
    .space  31
    .byte   0x30
    .space  64
    .space  31
    .byte   0x20
    .space  32
    .space  31
    .byte   0x08
    .space  32
    .space  31
    .byte   0x60
    .space  96
    .space  31
    .byte   0x08
    .space  32
e1_abi_end:
.if e1_abi_end - e1_abi != 576
.error "the length of e1_abi is wrong"
.endif
/* The DepositEvent topic: keccak256 of DepositEvent(bytes,bytes,bytes,bytes,bytes). */
e1_topic:
    .byte   0x64, 0x9b, 0xbc, 0x62, 0xd0, 0xe3, 0x13, 0x42, 0xaf, 0xea, 0x4e, 0x5c, 0xd8, 0x2d, 0x40, 0x49
    .byte   0xe7, 0xe1, 0xee, 0x91, 0x2f, 0xc0, 0x88, 0x9a, 0xa7, 0x90, 0x80, 0x3b, 0xe3, 0x90, 0x38, 0xc5
