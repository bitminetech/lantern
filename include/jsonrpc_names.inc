/*
 * The JSON names and strings of the Engine API client's response parser, as read only data for
 * asm/core/<ISA>/jsonrpc.s, which includes this file in read only data, before its code.
 * json_statuses and json_methods: entries of a length byte and the bytes, then a 0 byte;
 * a status is ENGINE_STATUS_* in entry order from 1, a method its capability bit from 0.
 */
json_id:
    .ascii  "id"
json_id_end:
.set json_id_len, 2
.if json_id_end - json_id != json_id_len
.error "the length of json_id is wrong"
.endif
json_result:
    .ascii  "result"
json_result_end:
.set json_result_len, 6
.if json_result_end - json_result != json_result_len
.error "the length of json_result is wrong"
.endif
json_error:
    .ascii  "error"
json_error_end:
.set json_error_len, 5
.if json_error_end - json_error != json_error_len
.error "the length of json_error is wrong"
.endif
json_code:
    .ascii  "code"
json_code_end:
.set json_code_len, 4
.if json_code_end - json_code != json_code_len
.error "the length of json_code is wrong"
.endif
json_status:
    .ascii  "status"
json_status_end:
.set json_status_len, 6
.if json_status_end - json_status != json_status_len
.error "the length of json_status is wrong"
.endif
json_latest_valid_hash:
    .ascii  "latestValidHash"
json_latest_valid_hash_end:
.set json_latest_valid_hash_len, 15
.if json_latest_valid_hash_end - json_latest_valid_hash != json_latest_valid_hash_len
.error "the length of json_latest_valid_hash is wrong"
.endif
json_payload_status:
    .ascii  "payloadStatus"
json_payload_status_end:
.set json_payload_status_len, 13
.if json_payload_status_end - json_payload_status != json_payload_status_len
.error "the length of json_payload_status is wrong"
.endif
json_payload_id:
    .ascii  "payloadId"
json_payload_id_end:
.set json_payload_id_len, 9
.if json_payload_id_end - json_payload_id != json_payload_id_len
.error "the length of json_payload_id is wrong"
.endif
json_true:
    .ascii  "true"
json_true_end:
.set json_true_len, 4
.if json_true_end - json_true != json_true_len
.error "the length of json_true is wrong"
.endif
json_false:
    .ascii  "false"
json_false_end:
.set json_false_len, 5
.if json_false_end - json_false != json_false_len
.error "the length of json_false is wrong"
.endif
json_null:
    .ascii  "null"
json_null_end:
.set json_null_len, 4
.if json_null_end - json_null != json_null_len
.error "the length of json_null is wrong"
.endif
json_escapes:                               /* the characters after a backslash, but u */
    .byte   0x22, 0x5c, 0x2f, 0x62, 0x66, 0x6e, 0x72, 0x74
json_statuses:
    .byte   5
    .ascii  "VALID"
    .byte   7
    .ascii  "INVALID"
    .byte   7
    .ascii  "SYNCING"
    .byte   8
    .ascii  "ACCEPTED"
    .byte   18
    .ascii  "INVALID_BLOCK_HASH"
    .byte   0
json_methods:
    .byte   19
    .ascii  "engine_newPayloadV1"
    .byte   19
    .ascii  "engine_newPayloadV2"
    .byte   19
    .ascii  "engine_newPayloadV3"
    .byte   19
    .ascii  "engine_newPayloadV4"
    .byte   26
    .ascii  "engine_forkchoiceUpdatedV1"
    .byte   26
    .ascii  "engine_forkchoiceUpdatedV2"
    .byte   26
    .ascii  "engine_forkchoiceUpdatedV3"
    .byte   19
    .ascii  "engine_getPayloadV1"
    .byte   19
    .ascii  "engine_getPayloadV2"
    .byte   19
    .ascii  "engine_getPayloadV3"
    .byte   19
    .ascii  "engine_getPayloadV4"
    .byte   19
    .ascii  "engine_getPayloadV5"
    .byte   0
.if ENGINE_STATUS_VALID != 1 || ENGINE_STATUS_INVALID_BLOCK_HASH != 5
.error "json_statuses lists the statuses in ENGINE_STATUS_* order"
.endif
