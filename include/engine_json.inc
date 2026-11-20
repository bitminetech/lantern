/*
 * The JSON text of the Engine API requests (docs/reference/engine-api.md), as read only data
 * for asm/core/<ISA>/enginejson.s. Each text has a label, and a label after it, <label>_end.
 * enginejson.s includes this file in read only data, before its code.
 */
j_open:
    .ascii  "{\"jsonrpc\":\"2.0\",\"id\":"
j_open_end:
.set j_open_len, 22
.if j_open_end - j_open != j_open_len
.error "the length of j_open is wrong"
.endif
j_method_np:
    .ascii  ",\"method\":\"engine_newPayloadV"
j_method_np_end:
.set j_method_np_len, 29
.if j_method_np_end - j_method_np != j_method_np_len
.error "the length of j_method_np is wrong"
.endif
j_method_fcu:
    .ascii  ",\"method\":\"engine_forkchoiceUpdatedV"
j_method_fcu_end:
.set j_method_fcu_len, 36
.if j_method_fcu_end - j_method_fcu != j_method_fcu_len
.error "the length of j_method_fcu is wrong"
.endif
j_params:
    .ascii  "\",\"params\":["
j_params_end:
.set j_params_len, 12
.if j_params_end - j_params != j_params_len
.error "the length of j_params is wrong"
.endif
j_parent_hash:
    .ascii  "{\"parentHash\":"
j_parent_hash_end:
.set j_parent_hash_len, 14
.if j_parent_hash_end - j_parent_hash != j_parent_hash_len
.error "the length of j_parent_hash is wrong"
.endif
j_fee_recipient:
    .ascii  ",\"feeRecipient\":"
j_fee_recipient_end:
.set j_fee_recipient_len, 16
.if j_fee_recipient_end - j_fee_recipient != j_fee_recipient_len
.error "the length of j_fee_recipient is wrong"
.endif
j_state_root:
    .ascii  ",\"stateRoot\":"
j_state_root_end:
.set j_state_root_len, 13
.if j_state_root_end - j_state_root != j_state_root_len
.error "the length of j_state_root is wrong"
.endif
j_receipts_root:
    .ascii  ",\"receiptsRoot\":"
j_receipts_root_end:
.set j_receipts_root_len, 16
.if j_receipts_root_end - j_receipts_root != j_receipts_root_len
.error "the length of j_receipts_root is wrong"
.endif
j_logs_bloom:
    .ascii  ",\"logsBloom\":"
j_logs_bloom_end:
.set j_logs_bloom_len, 13
.if j_logs_bloom_end - j_logs_bloom != j_logs_bloom_len
.error "the length of j_logs_bloom is wrong"
.endif
j_prev_randao:
    .ascii  ",\"prevRandao\":"
j_prev_randao_end:
.set j_prev_randao_len, 14
.if j_prev_randao_end - j_prev_randao != j_prev_randao_len
.error "the length of j_prev_randao is wrong"
.endif
j_block_number:
    .ascii  ",\"blockNumber\":"
j_block_number_end:
.set j_block_number_len, 15
.if j_block_number_end - j_block_number != j_block_number_len
.error "the length of j_block_number is wrong"
.endif
j_gas_limit:
    .ascii  ",\"gasLimit\":"
j_gas_limit_end:
.set j_gas_limit_len, 12
.if j_gas_limit_end - j_gas_limit != j_gas_limit_len
.error "the length of j_gas_limit is wrong"
.endif
j_gas_used:
    .ascii  ",\"gasUsed\":"
j_gas_used_end:
.set j_gas_used_len, 11
.if j_gas_used_end - j_gas_used != j_gas_used_len
.error "the length of j_gas_used is wrong"
.endif
j_timestamp:
    .ascii  ",\"timestamp\":"
j_timestamp_end:
.set j_timestamp_len, 13
.if j_timestamp_end - j_timestamp != j_timestamp_len
.error "the length of j_timestamp is wrong"
.endif
j_extra_data:
    .ascii  ",\"extraData\":"
j_extra_data_end:
.set j_extra_data_len, 13
.if j_extra_data_end - j_extra_data != j_extra_data_len
.error "the length of j_extra_data is wrong"
.endif
j_base_fee:
    .ascii  ",\"baseFeePerGas\":"
j_base_fee_end:
.set j_base_fee_len, 17
.if j_base_fee_end - j_base_fee != j_base_fee_len
.error "the length of j_base_fee is wrong"
.endif
j_block_hash:
    .ascii  ",\"blockHash\":"
j_block_hash_end:
.set j_block_hash_len, 13
.if j_block_hash_end - j_block_hash != j_block_hash_len
.error "the length of j_block_hash is wrong"
.endif
j_transactions:
    .ascii  ",\"transactions\":["
j_transactions_end:
.set j_transactions_len, 17
.if j_transactions_end - j_transactions != j_transactions_len
.error "the length of j_transactions is wrong"
.endif
j_withdrawals:
    .ascii  "],\"withdrawals\":["
j_withdrawals_end:
.set j_withdrawals_len, 17
.if j_withdrawals_end - j_withdrawals != j_withdrawals_len
.error "the length of j_withdrawals is wrong"
.endif
j_w_index:
    .ascii  "{\"index\":"
j_w_index_end:
.set j_w_index_len, 9
.if j_w_index_end - j_w_index != j_w_index_len
.error "the length of j_w_index is wrong"
.endif
j_w_validator:
    .ascii  ",\"validatorIndex\":"
j_w_validator_end:
.set j_w_validator_len, 18
.if j_w_validator_end - j_w_validator != j_w_validator_len
.error "the length of j_w_validator is wrong"
.endif
j_w_address:
    .ascii  ",\"address\":"
j_w_address_end:
.set j_w_address_len, 11
.if j_w_address_end - j_w_address != j_w_address_len
.error "the length of j_w_address is wrong"
.endif
j_w_amount:
    .ascii  ",\"amount\":"
j_w_amount_end:
.set j_w_amount_len, 10
.if j_w_amount_end - j_w_amount != j_w_amount_len
.error "the length of j_w_amount is wrong"
.endif
j_blob_gas_used:
    .ascii  "],\"blobGasUsed\":"
j_blob_gas_used_end:
.set j_blob_gas_used_len, 16
.if j_blob_gas_used_end - j_blob_gas_used != j_blob_gas_used_len
.error "the length of j_blob_gas_used is wrong"
.endif
j_excess_blob_gas:
    .ascii  ",\"excessBlobGas\":"
j_excess_blob_gas_end:
.set j_excess_blob_gas_len, 17
.if j_excess_blob_gas_end - j_excess_blob_gas != j_excess_blob_gas_len
.error "the length of j_excess_blob_gas is wrong"
.endif
j_head:
    .ascii  "{\"headBlockHash\":"
j_head_end:
.set j_head_len, 17
.if j_head_end - j_head != j_head_len
.error "the length of j_head is wrong"
.endif
j_safe:
    .ascii  ",\"safeBlockHash\":"
j_safe_end:
.set j_safe_len, 17
.if j_safe_end - j_safe != j_safe_len
.error "the length of j_safe is wrong"
.endif
j_finalized:
    .ascii  ",\"finalizedBlockHash\":"
j_finalized_end:
.set j_finalized_len, 22
.if j_finalized_end - j_finalized != j_finalized_len
.error "the length of j_finalized is wrong"
.endif
j_fcu_close:
    .ascii  "},null]}"
j_fcu_close_end:
.set j_fcu_close_len, 8
.if j_fcu_close_end - j_fcu_close != j_fcu_close_len
.error "the length of j_fcu_close is wrong"
.endif
j_close:
    .ascii  "]}"
j_close_end:
.set j_close_len, 2
.if j_close_end - j_close != j_close_len
.error "the length of j_close is wrong"
.endif
j_method_gp:
    .ascii  ",\"method\":\"engine_getPayloadV"
j_method_gp_end:
.set j_method_gp_len, 29
.if j_method_gp_end - j_method_gp != j_method_gp_len
.error "the length of j_method_gp is wrong"
.endif
j_attr_open:
    .ascii  "},{\"timestamp\":"
j_attr_open_end:
.set j_attr_open_len, 15
.if j_attr_open_end - j_attr_open != j_attr_open_len
.error "the length of j_attr_open is wrong"
.endif
j_attr_fee_recipient:
    .ascii  ",\"suggestedFeeRecipient\":"
j_attr_fee_recipient_end:
.set j_attr_fee_recipient_len, 25
.if j_attr_fee_recipient_end - j_attr_fee_recipient != j_attr_fee_recipient_len
.error "the length of j_attr_fee_recipient is wrong"
.endif
j_attr_withdrawals:
    .ascii  ",\"withdrawals\":["
j_attr_withdrawals_end:
.set j_attr_withdrawals_len, 16
.if j_attr_withdrawals_end - j_attr_withdrawals != j_attr_withdrawals_len
.error "the length of j_attr_withdrawals is wrong"
.endif
j_attr_parent_root:
    .ascii  ",\"parentBeaconBlockRoot\":"
j_attr_parent_root_end:
.set j_attr_parent_root_len, 25
.if j_attr_parent_root_end - j_attr_parent_root != j_attr_parent_root_len
.error "the length of j_attr_parent_root is wrong"
.endif
j_attr_close:
    .ascii  "}]}"
j_attr_close_end:
.set j_attr_close_len, 3
.if j_attr_close_end - j_attr_close != j_attr_close_len
.error "the length of j_attr_close is wrong"
.endif
