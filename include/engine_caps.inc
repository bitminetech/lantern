/*
 * The JSON text of engine_exchangeCapabilities (docs/reference/engine-api.md), as read only
 * data for asm/core/<ISA>/engine.s, which includes this file in read only data, before its code.
 */
j_caps_open:
    .ascii  "{\"jsonrpc\":\"2.0\",\"id\":"
j_caps_open_end:
.set j_caps_open_len, 22
.if j_caps_open_end - j_caps_open != j_caps_open_len
.error "the length of j_caps_open is wrong"
.endif
j_caps_close:
    .ascii  ",\"method\":\"engine_exchangeCapabilities\",\"params\":[[\"engine_newPayloadV1\",\"engine_newPayloadV2\",\"engine_newPayloadV3\",\"engine_newPayloadV4\",\"engine_forkchoiceUpdatedV1\",\"engine_forkchoiceUpdatedV2\",\"engine_forkchoiceUpdatedV3\",\"engine_getPayloadV1\",\"engine_getPayloadV2\",\"engine_getPayloadV3\",\"engine_getPayloadV4\",\"engine_getPayloadV5\"]]}"
j_caps_close_end:
.set j_caps_close_len, 338
.if j_caps_close_end - j_caps_close != j_caps_close_len
.error "the length of j_caps_close is wrong"
.endif
