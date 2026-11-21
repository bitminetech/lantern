/*
 * lantern core for ARM64 (AAPCS64): the functions that read no fork's layouts, one object
 * (include/forks.inc). Requirements: docs/reference/. Layouts: include/.
 */
.set ISA_ARM64, 1
.include "ssz.inc"
.include "crypto.inc"
.include "bls12381.inc"
.include "kzg.inc"
.include "preset.inc"
.include "lantern.inc"
.include "fork_numbers.inc"
.include "platform.inc"
.include "snappy.inc"
.include "libp2p.inc"
.include "discv5.inc"
.include "reqresp_protocols.inc"
.include "engine_text.inc"
.include "gossip_topics.inc"
.include "api_routes.inc"
.include "macros.s"

/* ---------------------------------------------------------------- Functions */

.include "memory.s"
.include "config.s"
.include "options.s"
.include "api.s"
.include "json.s"
.include "http.s"
.include "route.s"
.include "seen_find.s"
.include "store.s"
.include "seen.s"
.include "topics.s"
.include "reqresp.s"
.include "engine.s"
.include "jsonrpc.s"
.include "node.s"
.include "lcstore.s"
.include "lcnode.s"
.include "builder.s"
.include "db.s"
