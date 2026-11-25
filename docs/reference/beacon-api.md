# Beacon API

## Contents

### Functions

- [`lantern_api_route`](#function-lantern_api_route): finds the operation of a request and reads its parameters.
- [`lantern_http_request`](#function-lantern_http_request): reads one HTTP/1.1 request, head and body, from a connection's bytes.
- [`lantern_json_decode`](#function-lantern_json_decode): the SSZ encoding of a value from its JSON, strictly.
- [`lantern_json_encode`](#function-lantern_json_encode): the JSON of an SSZ value, a chunk at a time.
- [`lantern_json_encode_ssz`](#function-lantern_json_encode_ssz): the JSON of an SSZ encoding, a chunk at a time.
- [`lantern_api_lc_event_text`](#function-lantern_api_lc_event_text): the text of a light client event.
- [`lantern_api_lc_updates_body`](#function-lantern_api_lc_updates_body): the body of getLightClientUpdatesByRange.
- [`lantern_bld_dec`](#function-lantern_bld_dec): writes the decimal digits of a number.
- [`lantern_bld_digits`](#function-lantern_bld_digits): the count of decimal digits of a number.
- [`lantern_bld_hex`](#function-lantern_bld_hex): writes the lower case hex digits of some bytes.
- [`lantern_bld_put`](#function-lantern_bld_put): copies bytes to a cursor.
- [`lantern_bld_reg_json`](#function-lantern_bld_reg_json): writes the JSON of a SignedValidatorRegistrationV1.
- [`lantern_bld_reg_len`](#function-lantern_bld_reg_len): the bytes of the JSON of a SignedValidatorRegistrationV1.
- [`lantern_bld_same`](#function-lantern_bld_same): whether two byte strings are equal.
- [`lantern_bld_status`](#function-lantern_bld_status): the status of a builder's HTTP answer.
- [`lantern_http_chunks`](#function-lantern_http_chunks): checks or copies a chunked request body.
- [`lantern_http_crlf`](#function-lantern_http_crlf): the first CRLF in a range of bytes.
- [`lantern_http_find`](#function-lantern_http_find): the first place of a byte in a range of bytes.
- [`lantern_http_joined`](#function-lantern_http_joined): the joined values of the field lines of a name.
- [`lantern_http_part`](#function-lantern_http_part): puts bytes as a part of an HttpRequest.
- [`lantern_http_same`](#function-lantern_http_same): whether bytes equal lower case bytes without regard to ASCII case.
- [`lantern_http_token`](#function-lantern_http_token): whether a range of bytes is a token.
- [`lantern_http_trim`](#function-lantern_http_trim): a range of bytes without its leading and trailing white space.
- [`lantern_jd_fault`](#function-lantern_jd_fault): records a fault of the JSON decoder.
- [`lantern_jd_hexdigit`](#function-lantern_jd_hexdigit): the value of a hex digit.
- [`lantern_jd_key`](#function-lantern_jd_key): skips a key of a skipped object.
- [`lantern_jd_literal`](#function-lantern_jd_literal): whether a literal starts at a place of the JSON text.
- [`lantern_jd_number`](#function-lantern_jd_number): reads a JSON number.
- [`lantern_jd_offset`](#function-lantern_jd_offset): writes a 4-byte offset into the encoding.
- [`lantern_jd_out`](#function-lantern_jd_out): joins bytes to the encoding.
- [`lantern_jd_skip`](#function-lantern_jd_skip): skips a JSON value with only the checks of the text.
- [`lantern_jd_string`](#function-lantern_jd_string): reads a JSON string.
- [`lantern_jd_value`](#function-lantern_jd_value): decodes a JSON value of a type node.
- [`lantern_jd_ws`](#function-lantern_jd_ws): skips JSON white space.
- [`lantern_json_child`](#function-lantern_json_child): opens the next item of a compound level of the JSON encoder.
- [`lantern_json_decode_mode`](#function-lantern_json_decode_mode): lantern_json_decode or lantern_engine_json_decode by a mode.
- [`lantern_json_hex`](#function-lantern_json_hex): writes the hex token of a byte or bit string of the JSON encoder.
- [`lantern_json_main`](#function-lantern_json_main): the JSON of a value or of an SSZ encoding, a chunk at a time.
- [`lantern_json_number`](#function-lantern_json_number): writes the token of a uint or Boolean of the JSON encoder.
- [`lantern_json_open`](#function-lantern_json_open): opens a level of the JSON encoder for a type node.
- [`lantern_json_put`](#function-lantern_json_put): writes the bytes of a token of the JSON encoder.
- [`lantern_jss_child`](#function-lantern_jss_child): opens the next item of a compound level of an SSZ encoding.
- [`lantern_jss_field_end`](#function-lantern_jss_field_end): the end of a variable field of a container in an SSZ encoding.
- [`lantern_jss_open`](#function-lantern_jss_open): opens a level of the JSON encoder for an SSZ encoding.
- [`lantern_node_bid_data`](#function-lantern_node_bid_data): the JSON of the bid in a builder's getHeader answer.
- [`lantern_node_builder_call`](#function-lantern_node_builder_call): takes an entry of builder_calls.
- [`lantern_node_builder_event`](#function-lantern_node_builder_event): takes a NODE_EV_BUILDER event.
- [`lantern_node_builder_register`](#function-lantern_node_builder_register): sends the valid registrations of a registerValidator to the builder.
- [`lantern_node_produce_header`](#function-lantern_node_produce_header): sends the builder's header call of a produceBlockV3 entry.
- [`lantern_node_publish_submit`](#function-lantern_node_publish_submit): sends the submitBlindedBlockV2 call of a publishBlindedBlockV2 entry.
- [`lantern_node_registration_put`](#function-lantern_node_registration_put): keeps a validator's builder registration.
- [`lantern_node_registrations_find`](#function-lantern_node_registrations_find): the validators of the records of a registerValidator.
- [`lantern_route_decode`](#function-lantern_route_decode): percent-decodes bytes.
- [`lantern_route_hex`](#function-lantern_route_hex): reads a 0x hex text of a fixed length.
- [`lantern_route_ids_array`](#function-lantern_route_ids_array): reads null or an array of strings of a body parameter.
- [`lantern_route_key`](#function-lantern_route_key): which list parameter a body key names.
- [`lantern_route_lit`](#function-lantern_route_lit): whether a literal starts the body at the cursor.
- [`lantern_route_match`](#function-lantern_route_match): whether a path matches a route template.
- [`lantern_route_next_item`](#function-lantern_route_next_item): one item of a list value.
- [`lantern_route_number`](#function-lantern_route_number): reads a decimal number below 2^64.
- [`lantern_route_pct_ok`](#function-lantern_route_pct_ok): whether the percent-encoding of bytes is good.
- [`lantern_route_string`](#function-lantern_route_string): reads a JSON string of the body.
- [`lantern_route_value`](#function-lantern_route_value): reads the value of a parameter into an ApiRoute.
- [`lantern_route_weight`](#function-lantern_route_weight): the weight an Accept value gives a media type.
- [`lantern_route_word`](#function-lantern_route_word): the value of a word of a parameter.
- [`lantern_route_ws`](#function-lantern_route_ws): skips JSON white space of the body.
- [`lantern_api_base58`](#function-lantern_api_base58): the base58btc text of some bytes.
- [`lantern_api_blob_body`](#function-lantern_api_blob_body): the body of the blob stream.
- [`lantern_api_blob_wanted`](#function-lantern_api_blob_wanted): whether a commitment's versioned hash is asked for.
- [`lantern_api_body`](#function-lantern_api_body): writes the body of a response.
- [`lantern_api_bool`](#function-lantern_api_bool): writes a JSON Boolean.
- [`lantern_api_checkpoint`](#function-lantern_api_checkpoint): writes a Checkpoint of the view.
- [`lantern_api_code`](#function-lantern_api_code): the api_codes entry of a status.
- [`lantern_api_code_text`](#function-lantern_api_code_text): writes a text of an api_codes entry.
- [`lantern_api_committees_json`](#function-lantern_api_committees_json): writes the items of the getEpochCommittees stream.
- [`lantern_api_dec`](#function-lantern_api_dec): writes a number in decimal.
- [`lantern_api_dec256`](#function-lantern_api_dec256): writes a 256-bit number in decimal.
- [`lantern_api_duties_json`](#function-lantern_api_duties_json): writes the JSON of getAttesterDuties.
- [`lantern_api_event_text`](#function-lantern_api_event_text): the text of an event of a topic.
- [`lantern_api_failures`](#function-lantern_api_failures): writes the failures of a NODE_WORK_API_SUBMIT.
- [`lantern_api_fork_choice_body`](#function-lantern_api_fork_choice_body): writes the body of getDebugForkChoice.
- [`lantern_api_fork_name`](#function-lantern_api_fork_name): writes the name of a fork.
- [`lantern_api_fork_schedule`](#function-lantern_api_fork_schedule): writes the body of getForkSchedule.
- [`lantern_api_header_json`](#function-lantern_api_header_json): writes the fields of a block header item.
- [`lantern_api_headers_json`](#function-lantern_api_headers_json): writes the getBlockHeaders stream.
- [`lantern_api_heads_body`](#function-lantern_api_heads_body): writes the body of getDebugChainHeadsV2.
- [`lantern_api_hex16`](#function-lantern_api_hex16): writes 16 bits in hex.
- [`lantern_api_hex4`](#function-lantern_api_hex4): the 4 hex digits of 16 bits.
- [`lantern_api_liveness_body`](#function-lantern_api_liveness_body): writes the body of getLiveness.
- [`lantern_api_names`](#function-lantern_api_names): whether ValidatorRef items name a validator.
- [`lantern_api_op_event_text`](#function-lantern_api_op_event_text): the text of an event of an operation topic.
- [`lantern_api_payload_event_text`](#function-lantern_api_payload_event_text): the text of a payload_attributes event.
- [`lantern_api_peer_item`](#function-lantern_api_peer_item): writes a peer of getPeers and getPeer.
- [`lantern_api_peers_body`](#function-lantern_api_peers_body): writes the body of getPeers.
- [`lantern_api_pending_item`](#function-lantern_api_pending_item): writes a pending item.
- [`lantern_api_pending_json`](#function-lantern_api_pending_json): writes the items of a pending stream.
- [`lantern_api_pool_json`](#function-lantern_api_pool_json): writes a pool stream.
- [`lantern_api_put`](#function-lantern_api_put): writes bytes into the response.
- [`lantern_api_qdec`](#function-lantern_api_qdec): writes a number in decimal, in quotes.
- [`lantern_api_qdec256`](#function-lantern_api_qdec256): writes a Uint256 in decimal, in quotes.
- [`lantern_api_qhex`](#function-lantern_api_qhex): writes bytes as quoted hex.
- [`lantern_api_qint`](#function-lantern_api_qint): writes a signed number in decimal, in quotes.
- [`lantern_api_respond`](#function-lantern_api_respond): writes an HTTP response.
- [`lantern_api_reward_fields`](#function-lantern_api_reward_fields): writes the fields of an attestation reward item.
- [`lantern_api_rewards_body`](#function-lantern_api_rewards_body): writes the body of getBlockRewards.
- [`lantern_api_rewards_json`](#function-lantern_api_rewards_json): writes the items of getAttestationsRewards.
- [`lantern_api_sidecar_body`](#function-lantern_api_sidecar_body): the body of a sidecar stream.
- [`lantern_api_sidecar_event_text`](#function-lantern_api_sidecar_event_text): the text of an event of a sidecar topic.
- [`lantern_api_spec`](#function-lantern_api_spec): writes the body of getSpec.
- [`lantern_api_sse_head`](#function-lantern_api_sse_head): the head of an eventstream answer.
- [`lantern_api_state_read_body`](#function-lantern_api_state_read_body): writes the bodies of getStateRandao, getEpochSyncCommittees and getProposerLookahead.
- [`lantern_api_stream_head`](#function-lantern_api_stream_head): writes the head of a streamed answer.
- [`lantern_api_stream_json`](#function-lantern_api_stream_json): writes the JSON of a stream's SSZ bytes.
- [`lantern_api_sync_duties_body`](#function-lantern_api_sync_duties_body): writes the body of getSyncCommitteeDuties.
- [`lantern_api_sync_rewards_body`](#function-lantern_api_sync_rewards_body): writes the body of getSyncCommitteeRewards.
- [`lantern_api_text`](#function-lantern_api_text): writes a text in quotes.
- [`lantern_api_validator_item`](#function-lantern_api_validator_item): writes the item of a validator.
- [`lantern_api_validator_status`](#function-lantern_api_validator_status): the API status of a validator.
- [`lantern_api_validators_json`](#function-lantern_api_validators_json): writes the items of a validator stream.
- [`lantern_api_view_finalized`](#function-lantern_api_view_finalized): sets head_finalized of an ApiView.
- [`lantern_api_wei`](#function-lantern_api_wei): writes a Gwei amount in Wei.
- [`lantern_copy_root`](#function-lantern_copy_root): copies 32 bytes.
- [`lantern_node_api_advance`](#function-lantern_node_api_advance): brings the state of an ApiView to its slot.
- [`lantern_node_api_aggregate`](#function-lantern_node_api_aggregate): the SSZ bytes of the aggregate of a getAggregatedAttestationV2 stream.
- [`lantern_node_api_below`](#function-lantern_node_api_below): the block of the chain at or below a slot.
- [`lantern_node_api_blob_stream`](#function-lantern_node_api_blob_stream): starts the blob stream of a block.
- [`lantern_node_api_block`](#function-lantern_node_api_block): finds the block of a block_id.
- [`lantern_node_api_block_event`](#function-lantern_node_api_block_event): queues the block event of a block.
- [`lantern_node_api_check`](#function-lantern_node_api_check): checks a NODE_EV_API or NODE_EV_API_IDENTITY event.
- [`lantern_node_api_chunk_done`](#function-lantern_node_api_chunk_done): takes the end of a NODE_WORK_API_CHUNK.
- [`lantern_node_api_chunk_run`](#function-lantern_node_api_chunk_run): the NODE_WORK_API_CHUNK work of lantern_node_run.
- [`lantern_node_api_chunk_work`](#function-lantern_node_api_chunk_work): queues a NODE_WORK_API_CHUNK of a NodeApi entry.
- [`lantern_node_api_closed`](#function-lantern_node_api_closed): takes a NODE_EV_API_CLOSED event.
- [`lantern_node_api_committees_check`](#function-lantern_node_api_committees_check): the epoch of a getEpochCommittees.
- [`lantern_node_api_committees_cursor`](#function-lantern_node_api_committees_cursor): sets the cursor of a getEpochCommittees stream.
- [`lantern_node_api_committees_prep`](#function-lantern_node_api_committees_prep): starts a chunk of a getEpochCommittees stream.
- [`lantern_node_api_contribution`](#function-lantern_node_api_contribution): the SSZ bytes of the contribution of a produceSyncCommitteeContribution stream.
- [`lantern_node_api_db_ref`](#function-lantern_node_api_db_ref): the NODE_DB_REF of a block root in the Db.
- [`lantern_node_api_done`](#function-lantern_node_api_done): takes the end of a NODE_WORK_API_ENCODE.
- [`lantern_node_api_encode`](#function-lantern_node_api_encode): queues the NODE_WORK_API_ENCODE of an operation.
- [`lantern_node_api_end`](#function-lantern_node_api_end): ends the stream of a NodeApi entry.
- [`lantern_node_api_event`](#function-lantern_node_api_event): answers a NODE_EV_API event.
- [`lantern_node_api_event_count`](#function-lantern_node_api_event_count): the NodeApi entries of eventstream.
- [`lantern_node_api_event_done`](#function-lantern_node_api_event_done): takes the end of a NODE_WORK_API_EVENT.
- [`lantern_node_api_event_run`](#function-lantern_node_api_event_run): the NODE_WORK_API_EVENT work of lantern_node_run.
- [`lantern_node_api_events`](#function-lantern_node_api_events): sends an event text to the eventstream entries of its topic.
- [`lantern_node_api_final_block`](#function-lantern_node_api_final_block): whether a slot is at most the finalized block's.
- [`lantern_node_api_find`](#function-lantern_node_api_find): the NodeApi entry of a connection.
- [`lantern_node_api_find_peer`](#function-lantern_node_api_find_peer): the NodePeer of a route's peer_id.
- [`lantern_node_api_find_validator`](#function-lantern_node_api_find_validator): the index of the validator of a ValidatorRef.
- [`lantern_node_api_fold`](#function-lantern_node_api_fold): folds a pool attestation into the aggregate of a getAggregatedAttestationV2 stream.
- [`lantern_node_api_free`](#function-lantern_node_api_free): the free NodeApi entries of the node.
- [`lantern_node_api_head_events`](#function-lantern_node_api_head_events): queues the head and finalized_checkpoint events at a quiet point.
- [`lantern_node_api_headers_stream`](#function-lantern_node_api_headers_stream): starts the getBlockHeaders stream.
- [`lantern_node_api_ids`](#function-lantern_node_api_ids): puts the ids of a validator operation.
- [`lantern_node_api_lookup`](#function-lantern_node_api_lookup): starts the lookup of a state_id of a root.
- [`lantern_node_api_lookup_done`](#function-lantern_node_api_lookup_done): takes the end of a NODE_WORK_API_LOOKUP.
- [`lantern_node_api_lookup_run`](#function-lantern_node_api_lookup_run): the NODE_WORK_API_LOOKUP work of lantern_node_run.
- [`lantern_node_api_new`](#function-lantern_node_api_new): takes a free NodeApi entry.
- [`lantern_node_api_on_chain`](#function-lantern_node_api_on_chain): whether a block is on the chain.
- [`lantern_node_api_parent`](#function-lantern_node_api_parent): the imported parent of a block.
- [`lantern_node_api_pool_advance`](#function-lantern_node_api_pool_advance): moves a pool stream to its next entry.
- [`lantern_node_api_pool_stream`](#function-lantern_node_api_pool_stream): starts the stream of a pool GET.
- [`lantern_node_api_produce`](#function-lantern_node_api_produce): starts a produceBlockV3.
- [`lantern_node_api_publish`](#function-lantern_node_api_publish): starts a publishBlockV2.
- [`lantern_node_api_publish_count`](#function-lantern_node_api_publish_count): the count of the publishBlockV2 entries.
- [`lantern_node_api_put8`](#function-lantern_node_api_put8): puts 8 bytes under a new id.
- [`lantern_node_api_reorg`](#function-lantern_node_api_reorg): the depth of a reorg.
- [`lantern_node_api_rerun`](#function-lantern_node_api_rerun): goes on with a lookup entry.
- [`lantern_node_api_rewards`](#function-lantern_node_api_rewards): starts getBlockRewards or getSyncCommitteeRewards.
- [`lantern_node_api_rewards_state`](#function-lantern_node_api_rewards_state): the state of the chain at a slot, for the rewards.
- [`lantern_node_api_root_event`](#function-lantern_node_api_root_event): queues the event of a block root.
- [`lantern_node_api_run`](#function-lantern_node_api_run): the NODE_WORK_API_ENCODE work of lantern_node_run.
- [`lantern_node_api_same_root`](#function-lantern_node_api_same_root): whether two roots are the same.
- [`lantern_node_api_send`](#function-lantern_node_api_send): queues an API_SEND of a response.
- [`lantern_node_api_sent`](#function-lantern_node_api_sent): takes a NODE_EV_API_SENT event.
- [`lantern_node_api_sidecar_stream`](#function-lantern_node_api_sidecar_stream): starts the sidecar stream of a block.
- [`lantern_node_api_state`](#function-lantern_node_api_state): finds the state of a state_id.
- [`lantern_node_api_state_answer`](#function-lantern_node_api_state_answer): answers a state operation.
- [`lantern_node_api_stream`](#function-lantern_node_api_stream): starts the stream of getBlockV2, getStateV2 or a validator operation.
- [`lantern_node_api_submit`](#function-lantern_node_api_submit): starts a pool POST.
- [`lantern_node_api_submit_done`](#function-lantern_node_api_submit_done): takes the end of a NODE_WORK_API_SUBMIT.
- [`lantern_node_api_submit_run`](#function-lantern_node_api_submit_run): the NODE_WORK_API_SUBMIT work of lantern_node_run.
- [`lantern_node_api_subscribe`](#function-lantern_node_api_subscribe): starts an eventstream.
- [`lantern_node_api_subscribed`](#function-lantern_node_api_subscribed): whether an eventstream has a topic.
- [`lantern_node_api_sync_fold`](#function-lantern_node_api_sync_fold): folds a pool sync committee message into the contribution of a stream.
- [`lantern_node_api_validators_prep`](#function-lantern_node_api_validators_prep): selects the validators of a chunk of a validator stream.
- [`lantern_node_api_view`](#function-lantern_node_api_view): fills an ApiView from the node and the store.
- [`lantern_node_blob_advance`](#function-lantern_node_blob_advance): moves a blob stream past an item.
- [`lantern_node_headers_next`](#function-lantern_node_headers_next): the next item of a getBlockHeaders stream.
- [`lantern_node_op_event`](#function-lantern_node_op_event): queues the event of a valid operation.
- [`lantern_node_pool_attestation`](#function-lantern_node_pool_attestation): the electra Attestation of a pool SingleAttestation.
- [`lantern_node_pool_kind`](#function-lantern_node_pool_kind): the lantern_node_json kind of a pool operation.
- [`lantern_node_pool_next`](#function-lantern_node_pool_next): the next pool entry a pool stream answers.
- [`lantern_node_produce_answer`](#function-lantern_node_produce_answer): starts the answer of a produceBlockV3 entry.
- [`lantern_node_produce_bid_go`](#function-lantern_node_produce_bid_go): moves a produceBlockV3 entry on from NODE_PRODUCE_BID.
- [`lantern_node_produce_build`](#function-lantern_node_produce_build): starts the build of a produceBlockV3 entry.
- [`lantern_node_produce_done`](#function-lantern_node_produce_done): takes the end of a work of block production.
- [`lantern_node_produce_due`](#function-lantern_node_produce_due): moves on the produceBlockV3 entries that wait for a bid.
- [`lantern_node_produce_fail`](#function-lantern_node_produce_fail): answers an error to a produceBlockV3 entry and ends it.
- [`lantern_node_produce_next`](#function-lantern_node_produce_next): queues the next work of a produceBlockV3 entry in NODE_PRODUCE_FOLD.
- [`lantern_node_produce_release`](#function-lantern_node_produce_release): frees the draft and engine result of a produceBlockV3 entry.
- [`lantern_node_proposer_put`](#function-lantern_node_proposer_put): keeps a ProposerPreparation.
- [`lantern_node_publish`](#function-lantern_node_publish): publishes SSZ bytes on a gossip topic.
- [`lantern_node_publish_answer`](#function-lantern_node_publish_answer): answers a publishBlockV2 entry and ends it.
- [`lantern_node_publish_check_work`](#function-lantern_node_publish_check_work): queues the PUBLISH_CHECK of a publishBlockV2 entry.
- [`lantern_node_publish_done`](#function-lantern_node_publish_done): takes the end of a work of block publishing.
- [`lantern_node_publish_drop`](#function-lantern_node_publish_drop): frees the ids of a publishBlockV2 entry but the block's bytes.
- [`lantern_node_publish_end`](#function-lantern_node_publish_end): ends a publishBlockV2 entry.
- [`lantern_node_publish_poll`](#function-lantern_node_publish_poll): answers the publishBlockV2 entries whose import ended.
- [`lantern_node_publish_sidecar_done`](#function-lantern_node_publish_sidecar_done): takes the end of a valid PUBLISH_SIDECAR of a publishBlockV2 entry.
- [`lantern_node_publish_sidecar_work`](#function-lantern_node_publish_sidecar_work): queues the PUBLISH_SIDECAR of the next sidecar.
- [`lantern_node_publish_sidecars_work`](#function-lantern_node_publish_sidecars_work): queues the PUBLISH_SIDECARS of a publishBlockV2 entry.
- [`lantern_node_recon_sidecar_done`](#function-lantern_node_recon_sidecar_done): takes the end of a PUBLISH_SIDECAR of the reconstruction.
- [`lantern_node_replay_block`](#function-lantern_node_replay_block): queues the REPLAY work of a block of the replay.
- [`lantern_node_replay_due`](#function-lantern_node_replay_due): queues the next blocks of the replay in flight.
- [`lantern_node_replay_get`](#function-lantern_node_replay_get): the post-state of a block at a slot by the replay.
- [`lantern_node_sidecar_next`](#function-lantern_node_sidecar_next): the next sidecar of a sidecar stream.
- [`lantern_node_sidecar_of`](#function-lantern_node_sidecar_of): the data of a sidecar of a block.
- [`lantern_node_submit_check`](#function-lantern_node_submit_check): checks the records of a NODE_WORK_API_SUBMIT.
- [`lantern_node_submit_copy`](#function-lantern_node_submit_copy): copies bytes as a record of lantern_node_api_submit_run.
- [`lantern_node_submit_decode`](#function-lantern_node_submit_decode): decodes a JSON operation as a record of lantern_node_api_submit_run.
- [`lantern_node_submit_topic`](#function-lantern_node_submit_topic): the gossip topic of a pool POST.
- [`lantern_submit_ws`](#function-lantern_submit_ws): skips JSON white space of a submitted body.

### Types

- [`ApiIdentity`](#type-apiidentity): the texts of the node's identity that the shell knows.
- [`ApiRoute`](#type-apiroute): the operation of a request and its parameters.
- [`HttpLimits`](#type-httplimits): the largest request head and body a connection takes.
- [`HttpRequest`](#type-httprequest): one request, read.
- [`JsonCursor`](#type-jsoncursor): where lantern_json_encode goes on.
- [`JsonFault`](#type-jsonfault): why and where lantern_json_decode refused a JSON text.
- [`ValidatorRef`](#type-validatorref): a validator by index or by public key.

## Spec

- Document: [beacon-APIs v4.0.0](https://github.com/ethereum/beacon-APIs/tree/v4.0.0).
- Validator client additions: the parts of [beacon-APIs v5.0.0-beta.0](https://github.com/ethereum/beacon-APIs/tree/v5.0.0-beta.0) (commit `7911555`) that validator clients call: the operation getProposerDutiesV2 (`apis/validator/duties/proposer.v2.yaml`), which Lighthouse v8.3.3 asks for, and the eventstream topics `head_v2` and `execution_payload_available` (`apis/eventstream/index.yaml`), which Prysm v7.3.1 asks for. The operation is the 77th of the route table, after the 76 of v4.0.0; the topics follow `data_column_sidecar`.
- Section: the operations of `beacon-node-oapi.yaml` and `apis/`, with the JSON of `types/`: numbers as decimal strings, byte strings as `0x` and lower case hex; an error body is an `ErrorMessage` of `types/http.yaml`.
- JSON of SSZ values: beacon-APIs `types/primitive.yaml` and the types of each fork: a uint as a decimal string, `Boolean` as `true` or `false`, byte strings and bit strings as `0x` and lower case hex, lists and vectors as arrays, containers as objects of the spec's field names.
- Responses: [RFC 9112](https://www.rfc-editor.org/rfc/rfc9112) section 4 (status line), section 6.3 (an HTTP/1.0 body with no length ends when the connection closes), section 7.1 (chunked transfer coding) and section 9.3 (persistence: an HTTP/1.1 connection stays open unless `close`; an HTTP/1.0 connection closes unless `keep-alive`); [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110) section 8.6 (`Content-Length`), section 10.2.1 (`Allow`) and section 15 (status codes and reason phrases).
- Requests: [RFC 9112](https://www.rfc-editor.org/rfc/rfc9112) sections 2 to 7 (message format, request line, fields, body length, chunked coding) and [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110) section 5 (field syntax); status 431 of [RFC 6585](https://www.rfc-editor.org/rfc/rfc6585) section 5.
- `Eth-Consensus-Version` on the responses of getBlockV2 and getStateV2: the fork of the block or the state, as beacon-APIs `apis/beacon/blocks/block.v2.yaml` and `apis/debug/state.v2.yaml` require it.
- Routes: the 69 paths and 76 operations of `beacon-node-oapi.yaml` and `apis/` at beacon-APIs v4.0.0 (commit 88fc940), with their parameters of `params/index.yaml` and `apis/`; percent-encoding of [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986) section 2.1; `Accept` of RFC 9110 section 12.5.1; `Content-Type` of RFC 9110 section 8.3.

## Function `lantern_api_route`

Finds the operation of one request and reads its parameters, by their types.

### Signature

```
lantern_api_route(request, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `request` | input | [`HttpRequest`](#type-httprequest), as lantern_http_request gave it with `LANTERN_OK` |
| `out` | output | [`ApiRoute`](#type-apiroute), its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the operation and its parameters.
- `LANTERN_INVALID_ROUTE`: `status` of `out` is the HTTP status to answer: 400, 404, 405, 406, 414 or 415. `fault`, `allow` and `op` say why.
- `LANTERN_BUFFER_TOO_SMALL`: `size` of `out` is below `API_ROUTE_FIXED`, or the request breaks no rule and `out` has room for fewer bytes than its parts.

### Function does

- Operations:
  - The 76 operations of beacon-APIs v4.0.0, numbered `API_OP_*` from 1 in the order of `paths` in `beacon-node-oapi.yaml`, `GET` before `POST` on one path.
  - Each has a method, a path template, and its parameters (include/api_routes.inc).
- Path:
  - The `path` part splits at each `/` after the first byte. Each segment is percent-decoded: `%` and two hex digits of either case is that byte. A `%` without two hex digits gives 400, `fault` 0.
  - A template matches when it has as many segments, each fixed segment is equal byte for byte, and each parameter segment `{name}` is not empty.
  - No template matches: 404.
  - A template matches, but it has no operation for the method: 405. `allow` holds its methods: bit 0 `GET`, bit 1 `POST`.
- Query:
  - The `query` part splits at each `&`. An empty item is skipped. An item splits at its first `=` into name and value; with no `=` the value is empty. Both are percent-decoded, as the path is; a broken `%` gives 400, `fault` 0.
  - A name the operation does not take is skipped.
  - A name given twice: a list or a set takes both values, in order. Any other parameter gives 400.
  - The value of a list or a set splits at each `,`. An empty item gives 400.
  - A required parameter that is missing gives 400.
- Parameters by type. A value that breaks its type gives 400, `fault` the parameter:
  - Number (`epoch`, `slot`, `index`, `committee_index`, `subcommittee_index`, `start_period`, `count`, `builder_boost_factor`): one or more decimal digits, value below 2^64.
  - `syncing_status`: a number from 100 to 599.
  - Hex: `0x` and hex digits of either case, as many as the type says.
  - `state_id`: `head`, `genesis`, `finalized`, `justified`, a number (a slot), or hex of 32 bytes (a state root).
  - `block_id`: `head`, `genesis`, `finalized`, a number (a slot), or hex of 32 bytes (a block root).
  - `block_root`: hex of 32 bytes.
  - `validator_id`, and each item of `id`: a number (an index) or hex of 48 bytes (a public key, any bytes).
  - `peer_id`: 1 to 128 bytes of the base58btc alphabet.
  - `parent_root`, `attestation_data_root`, `beacon_block_root`, each item of `versioned_hashes`: hex of 32 bytes.
  - `randao_reveal`: hex of 96 bytes. `graffiti`: hex of 32 bytes.
  - `skip_randao_verification`: an empty value.
  - `broadcast_validation`: `gossip` (1), `consensus` (2) or `consensus_and_equivocation` (3). When it is missing: 1.
  - Each item of `indices`: a number.
  - Sets, a bit for each name: `status` (the nine `ValidatorStatus` names; `pending`, `active`, `exited` and `withdrawal` set the bits of their statuses), `state` and `direction` of getPeers, `topics` of eventstream (`API_STATUS_*`, `API_PEER_*`, `API_DIRECTION_*`, `API_TOPIC_*`).
  - `id` of getStateValidators and getStateValidatorBalances: more than 64 items give 414, `fault` `API_PARAM_ID`.
- The JSON body of postStateValidators, postStateValidatorBalances, postStateValidatorIdentities, getSyncCommitteeRewards, getAttestationsRewards, getAttesterDuties, getSyncCommitteeDuties and getLiveness gives `id` and `status` items as a query does, with no limit on the count of `id` items:
  - postStateValidators (`API_FLAG_IDS_OBJECT`): an object whose members are `ids` and `statuses`, each at most once, each `null` or an array of strings. Each string of `ids` is an `id` item; each of `statuses` a `status` item. Lighthouse v8.3.3 takes this body with the same rule (`deny_unknown_fields`).
  - The other seven (`API_FLAG_IDS_ARRAY`), whose bodies the spec gives as arrays of strings, each a public key or a validator index, or for getAttesterDuties, getSyncCommitteeDuties and getLiveness each a `Uint64`, a validator index (a public key item is then the operation's 400): no body, `null`, or an array of strings, each an `id` item.
  - JSON white space (space, tab, LF and CR) may stand before and after each token. A string follows RFC 8259 section 7: between two `"`, no byte below 0x20, and each `\` starts an escape: `\"`, `\\`, `\/`, `\b`, `\f`, `\n`, `\r`, `\t`, or `\u` and 4 hex digits. Its value, the key or the item, has each escape decoded; a `\u` of 0x80 or more gives a byte no item holds.
  - An empty array, `null` or a missing member gives no item: the parameter counts as not given.
  - Any other body, or bytes after its value: 400, `fault` 0. An item that breaks its type: 400, `fault` `API_PARAM_ID` or `API_PARAM_STATUS`. The first fault in the body's order is the one given.
- `Eth-Consensus-Version`, on the five operations that require it (publishBlindedBlockV2, publishBlockV2, submitPoolAttestationsV2, submitPoolAttesterSlashingsV2, publishAggregateAndProofsV2): a fork name from `phase0` to `fulu`, which sets `consensus_version` to its `FORK_*`. Missing or another value: 400, `fault` `API_PARAM_CONSENSUS_VERSION`.
- `Accept`, on the operations that can answer with SSZ (those whose responses list 406):
  - No `Accept`: JSON.
  - Items split at each `,`, white space around them trimmed, empty items skipped. An item is a media range, then parameters after `;`. The range compares without regard to case.
  - `q=` sets the item's weight: `0` to `1` with up to 3 decimals (RFC 9110 section 12.4.2). A broken `q` value skips the item. No `q`: weight 1. Other parameters are skipped.
  - `application/json` weighs by the most specific range that matches it: `application/json`, then `application/*`, then `*/*`; the highest weight among ranges of that kind. No match: weight 0. `application/octet-stream` the same way.
  - The heavier type answers; a tie answers JSON. Both weight 0: 406.
  - Other operations ignore `Accept` and answer JSON.
- `Content-Type`, on the operations that take an SSZ body (those whose responses list 415):
  - The media type before any `;`, trimmed, without regard to case: `application/json` or no `Content-Type` is JSON; `application/octet-stream` is SSZ; another type gives 415.
  - Other `POST` operations ignore it: JSON.
- Order of the checks; the first fault found is the one given:
  1. `size` of `out` below `API_ROUTE_FIXED`.
  2. The path's percent-encoding; then its template (404) and its method (405).
  3. The query's percent-encoding.
  4. The path parameters, in the order of the path.
  5. The query items, in their order; within a list or a set, its items in order. The 65th `id` gives 414 before it is read.
  6. Required query parameters: the missing one of lowest `API_PARAM_*`.
  7. `Eth-Consensus-Version`, then `Content-Type`, then the JSON body of the five operations above, then `Accept`.
  8. The room of `out`.
- On `LANTERN_OK`, every field of `out` is written; a parameter that is not given is zero, its bit of `present` clear, apart from `broadcast_validation`, which is 1 when the operation takes it. The list, then the peer id, follow the fixed part, each at a multiple of 8 bytes, with zero bytes between.
- On `LANTERN_INVALID_ROUTE`, `status`, `fault`, `allow` and `op` are written: `allow` once the path matches, `op` once its method matches too, else zero; `fault` the parameter for 400 and 414, else zero.

### Function never

- Reads more than `request` and the `size` field of `out`.
- Writes more than `out`.
- Makes an OS call.

### Limits

- Stack of its own: 496 bytes on x86-64 (return address included), 496 bytes on ARM64, 496 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_route`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `request`, `out`.

## Function `lantern_http_request`

Reads one HTTP/1.1 request, its head and its body, from the start of a connection's unread bytes.

### Signature

```
lantern_http_request(bytes, limits, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | ByteList: the connection's bytes not yet taken by a request |
| `limits` | input | [`HttpLimits`](#type-httplimits) |
| `out` | output | [`HttpRequest`](#type-httprequest), its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the request, and `used` the bytes it took.
- `LANTERN_HTTP_MORE`: `bytes` holds no whole request yet, and no fault so far.
- `LANTERN_INVALID_HTTP`: the request breaks a rule below; `status` of `out` is the HTTP status to answer, after which the connection closes.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer bytes than the request's parts.

### Function does

- Request line, `method SP request-target SP HTTP-version CRLF` (RFC 9112 section 3):
  - `method`: a token. `GET` and `POST` get their own value; another token is `HTTP_METHOD_OTHER`.
  - `request-target`: origin form, `/` and then visible bytes up to the space. Split at the first `?` into `path` and `query`.
  - `HTTP-version`: `HTTP/1.1` or `HTTP/1.0`. Another `HTTP/` version gives 505; anything else gives 400.
  - Any other fault of the line gives 400.
- A request may start after empty lines (CRLF), as RFC 9112 section 2.2 allows; they count in `used`.
- The head ends at the first CRLF CRLF after the empty lines. No end within the first `head_max` bytes of `bytes` gives 431.
- Field lines, `field-name ":" OWS field-value OWS CRLF` (RFC 9112 section 5):
  - Field names compare without regard to case.
  - White space between the name and the colon, a line that starts with white space (obsolete line folding), or a name that is no token: 400.
  - A value holds no CR, LF or NUL: else 400.
- Fields it reads, by name:
  - `Host`: HTTP/1.1 needs exactly one; none, or more than one, gives 400 (RFC 9112 section 3.2).
  - `Content-Length`: digits only; more than one line, or one list, with differing values: 400. A value above `body_max`: 413.
  - `Transfer-Encoding`: `chunked`, alone, without regard to case. Any other coding: 501. Present with `Content-Length`: 400 (RFC 9112 section 6.3 allows rejecting it as a likely smuggling attempt).
  - `Connection`: the token `close` sets `close`; HTTP/1.0 sets `close` unless the token `keep-alive` is there.
  - `Accept`, `Content-Type` and `Eth-Consensus-Version`: their values go to `accept`, `content_type` and `consensus_version`. Lines of one field join with `, ` between them, in order (RFC 9110 section 5.3).
- The body (RFC 9112 section 6):
  - `Content-Length`: that many bytes after the head.
  - `chunked`: chunks of hex size, each line followed by CRLF; after the hex digits a line may hold `;`, space or tab and then anything but CR, LF and NUL, which is skipped (chunk extensions). The last chunk is size 0; trailer lines are skipped up to the empty line. A size line with no hex digit, a size past 2^64 - 1, chunk data not followed by CRLF, or a size line longer than `head_max` gives 400. Trailer lines of more than `head_max` bytes in all give 431. A body above `body_max` gives 413, once the size line that passes it is in.
  - Neither: no body.
- `used`: the bytes from the start of `bytes` to the end of the request, chunk framing and trailers included. The next request on the connection starts there.
- `out` holds copies: `path`, `query`, the three field values and the body (unchunked), in its parts, in that order, each at a multiple of 8 bytes. Its room: `HTTP_REQUEST_FIXED` + each part's bytes rounded up to a multiple of 8.
- Faults of the head are found once the head has ended: before that, only 431.

### Function never

- Reads more than `bytes`, `limits` and the `size` field of `out`.
- Writes more than `out`.
- Makes an OS call.

### Limits

- Stack of its own: 352 bytes on x86-64 (return address included), 320 bytes on ARM64, 320 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_http_request`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `bytes`, `limits`, `out`.

## Function `lantern_json_decode`

Reads one value of an SSZ type from its JSON, as the Beacon API takes it, and writes the value's SSZ encoding.

### Signature

```
lantern_json_decode(type, json, scratch, out, fault) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `type` | input | asm-ssz `TypeDescriptor`: a root type of a fork's type table, as for lantern_json_encode |
| `json` | input | ByteList: the JSON text |
| `scratch` | scratch | `Scratch`: at least `JSON_DECODE_SCRATCH` (6208) bytes |
| `out` | output | ByteList, its `size` set: the SSZ encoding goes from its offset 24 |
| `fault` | output | [`JsonFault`](#type-jsonfault) |

### Returns

- `LANTERN_OK`: `out` holds the SSZ encoding of the value.
- `LANTERN_INVALID_JSON`: the text breaks a rule below; `fault` says which and where.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than `JSON_DECODE_SCRATCH` bytes, or `out` has room for fewer bytes than the encoding; `size` of `fault` is the room the encoding needs, when the text is valid.

### Function does

- The text (RFC 8259): one value, with white space (space, tab, LF, CR) allowed before and after it and between tokens.
- Strings hold no `\` and no byte below 0x20.
- Each SSZ kind, in the forms lantern_json_encode writes:
  - uint of w bytes: a string of 1 to 78 decimal digits whose value is below 2^(8w).
  - `Boolean`: `true` or `false`.
  - `ByteVector[N]`: a string, `0x` and 2N hex digits of either case.
  - `ByteList[N]`: a string, `0x` and an even count of hex digits, at most 2N.
  - `BitVector[N]`: a string, `0x` and the hex digits of ceil(N / 8) bytes, with every bit from N on zero.
  - `BitList[N]`: a string, `0x` and the hex digits of one byte or more, the last not zero; the bits below its highest set bit, the delimiter, number at most N.
  - `Vector[T, N]`: an array of N items; `List[T, N]`: an array of at most N items.
  - `Container`: an object with each field's name exactly once, in any order, and no other name.
- Order of the checks; the first fault found is the one given:
  - A value of a container: its members in text order, each name a field not seen before (`JSON_FAULT_FIELD` at the name), its value skipped with only the checks of the text; then a field not given (`JSON_FAULT_MISSING` at the `}`); then the value of each field in field order, by its kind.
  - A value of a list or vector: its items skipped in text order with only the checks of the text; then their count (`JSON_FAULT_LENGTH` at the `[`); then each item in order, by its kind.
  - A value of another kind: by its kind; a token of another JSON type gives `JSON_FAULT_TYPE` at it.
  - After the root value, only white space.
  - The checks of the text in a skipped value: strings, numbers (RFC 8259 section 6), `true`, `false`, `null`, and arrays and objects nested at most 64 deep; else `JSON_FAULT_SYNTAX`.
- `fault` on `LANTERN_INVALID_JSON`: the kind, the offset in `json` where the token at fault starts (for a text that ends early, the length of the text), and the path from the root to the value at fault: the object for a field name or a missing field, the array for a count, the value being skipped for a fault of the text inside it, else the value whose token is at fault.
- The encoding: SSZ (ssz-specs v0.1.0, as asm-ssz writes it): the fields of a container in spec order, its fixed part with 4-byte offsets, then its variable parts.

### Function never

- Reads more than `type`, the names after its field records, `json`, `scratch` and the `size` field of `out`.
- Writes more than `scratch`, `out` and `fault`.
- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_json_decode`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `type`, `json`, `scratch`, `out`, `fault`.

## Function `lantern_json_encode`

Writes the JSON of one SSZ value, as the Beacon API shows it, a chunk at a time.

### Signature

```
lantern_json_encode(type, value, cursor, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `type` | input | asm-ssz `TypeDescriptor`: a root type of a fork's type table (include/descriptors.inc), whose field records are followed by the names of its fields |
| `value` | input | asm-ssz `Value` of the type |
| `cursor` | state | [`JsonCursor`](#type-jsoncursor): all zero for a new value |
| `out` | output | ByteList: the bytes go after its `count`, up to its `size` |

### Returns

- `LANTERN_OK`: the JSON is whole, and `cursor` says so.
- `LANTERN_JSON_MORE`: `out` is full; `cursor` holds where the next call goes on.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has no room for a byte. Nothing is changed.

### Caller must

- Pass a valid value of the type.
- Pass the same `type` and `value` again with the `cursor` of the last call, until `LANTERN_OK`.

### Function does

- Each SSZ kind (beacon-APIs `types/primitive.yaml`):
  - uint: its decimal digits, in quotes.
  - `Boolean`: `true` or `false`.
  - `ByteVector`, `ByteList`: `0x` and two lower case hex digits for each byte, in quotes.
  - `BitVector`: the same, of its bytes.
  - `BitList`: the same, of its SSZ bytes: its bits, then the delimiter bit.
  - `Vector`, `List` of another kind: `[`, its items with `,` between them, `]`.
  - `Container`: `{`, then for each field in order `"name":` and its value, with `,` between them, `}`.
- No white space.
- The name of a field: the 32 bytes after the type table's field records at the same index as its field record, up to the first zero byte, or all 32.
- The bytes of all the calls of one value, in order, are the whole JSON, whatever the room of each call.

### Function never

- Reads more than `type`, the names after its field records, `value` and `cursor`.
- Writes more than `out` from its `count` and `cursor`.
- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_json_encode`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `type`, `value`, `cursor`, `out`.

## Function `lantern_json_encode_ssz`

Writes the JSON of one SSZ encoding, as lantern_json_encode writes it for the value of that encoding, a chunk at a time.

### Signature

```
lantern_json_encode_ssz(type, ssz, cursor, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `type` | input | asm-ssz `TypeDescriptor`, as for lantern_json_encode |
| `ssz` | input | ByteList: a valid SSZ encoding of the type |
| `cursor` | state | [`JsonCursor`](#type-jsoncursor): all zero for a new encoding |
| `out` | output | ByteList: the bytes go after its `count`, up to its `size` |

### Returns

- As lantern_json_encode.

### Caller must

- Pass a valid encoding of the type: one that ssz_deserialize takes.
- Pass the same `type` and `ssz` again with the `cursor` of the last call, until `LANTERN_OK`.

### Function does

- The JSON of lantern_json_encode for the value of the encoding, from the bytes of the encoding: a field of fixed size at its `ssz_offset`; a field of variable size from its 4-byte offset to the next variable field's offset, or the end; an item of a list or vector of fixed size at its index times the item's size, with the count of a list its bytes over that size; an item of variable size from its offset to the next, the count of a list its first offset over 4, or 0 with no bytes; a bit list's bytes as they are, with their delimiter.
- In `JsonCursor`, `base` of a level is the offset in `ssz` of its first byte, and `next` the offset of the byte after its last.

### Function never

- Reads more than `type`, the names after its field records, the bytes of `ssz` and `cursor`.
- Writes more than `out` from its `count` and `cursor`.
- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_json_encode_ssz`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `type`, `ssz`, `cursor`, `out`.

## Function `lantern_api_lc_event_text`

The text of a light client event.

### Signature

```
lantern_api_lc_event_text(out, topic, lc, scratch) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `out` | output | ByteList, its count set |
| `topic` | input | u64 in a register: the light client topic |
| `lc` | input | [`LcStore`](light-client.md#type-lcstore) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |

### Returns

- `LANTERN_OK`: `out` holds the event's text.
- `LANTERN_NO_STATE_ANSWER`: the store holds no update of the topic.
- `LANTERN_BUFFER_TOO_SMALL`: `out` or `scratch` is short.

### Function does

- Writes `event: <topic>` LF `data: {"version":…,"data":…}` LF LF (beacon-APIs eventstream).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_lc_event_text`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: the registers of the lantern_api_put writer.
- Argument order: `out`, `topic`, `lc`, `scratch`.

## Function `lantern_api_lc_updates_body`

The body of getLightClientUpdatesByRange.

### Signature

```
lantern_api_lc_updates_body(view)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `view` | input | `ApiView` |

### Function does

- Writes, with the writer of lantern_api_put, each update from the first period with an update to the first period of none, of the view's node.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 64 bytes on x86-64 (return address included), 64 bytes on ARM64, 64 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_lc_updates_body`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the view in x22, rbp, s4, and the lantern_api_put writer's registers.
- Argument order: `view`.

## Function `lantern_bld_dec`

Writes the decimal digits of a number.

### Signature

```
lantern_bld_dec(cursor, value) -> cursor
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `cursor` | output | the place to write |
| `value` | input | u64 in a register |

### Function does

- Writes the decimal digits of `value` at the cursor.
- Returns the cursor past them.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_bld_dec`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x13; rax, rcx, rdx, r8 to r11; a0, t0 to t3.
- Argument order: `cursor`, `value`.

## Function `lantern_bld_digits`

The count of decimal digits of a number.

### Signature

```
lantern_bld_digits(value) -> count
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `value` | input | u64 in a register |

### Function does

- Returns the count of decimal digits of `value`.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_bld_digits`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9, x10; rax, rcx, rdx, r8; a0, t0, t1.
- Argument order: `value`.

## Function `lantern_bld_hex`

Writes the lower case hex digits of some bytes.

### Signature

```
lantern_bld_hex(cursor, bytes, length) -> cursor
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `cursor` | output | the place to write |
| `bytes` | input | `length` bytes |
| `length` | input | u64 in a register |

### Function does

- Writes the lower case hex digits of the bytes at the cursor.
- Returns the cursor past them.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_bld_hex`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x12; rax, rcx, r8, r9; a0, t0 to t2.
- Argument order: `cursor`, `bytes`, `length`.

## Function `lantern_bld_put`

Copies bytes to a cursor.

### Signature

```
lantern_bld_put(cursor, bytes, length) -> cursor
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `cursor` | output | the place to write |
| `bytes` | input | `length` bytes |
| `length` | input | u64 in a register |

### Function does

- Copies the bytes to the cursor.
- Returns the cursor past them.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_bld_put`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `cursor`, `bytes`, `length`.

## Function `lantern_bld_reg_json`

Writes the JSON of a SignedValidatorRegistrationV1.

### Signature

```
lantern_bld_reg_json(cursor, registration) -> cursor
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `cursor` | output | the place to write |
| `registration` | input | the SSZ bytes of a `SignedValidatorRegistrationV1` |

### Function does

- Writes the JSON of the registration at the cursor (node.md, NODE_WORK_API_SUBMIT of registerValidator).
- Returns the cursor past it.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_bld_reg_json`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `cursor`, `registration`.

## Function `lantern_bld_reg_len`

The bytes of the JSON of a SignedValidatorRegistrationV1.

### Signature

```
lantern_bld_reg_len(registration) -> bytes
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `registration` | input | the 180 SSZ bytes of a `SignedValidatorRegistrationV1` |

### Function does

- Returns the bytes of the JSON lantern_bld_reg_json writes of it.

### Function never

- Writes memory but its own stack.
- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_bld_reg_len`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `registration`.

## Function `lantern_bld_same`

Whether two byte strings are equal.

### Signature

```
lantern_bld_same(a, b, b_length, a_length) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `a` | input | `a_length` bytes |
| `b` | input | `b_length` bytes |
| `b_length` | input | u64 in a register |
| `a_length` | input | u64 in a register |

### Function does

- Returns 1 when the bytes of `b` are those of `a`, else 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_bld_same`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9, x10; rax, rdi, rsi, rdx; a0, t0, t1.
- Argument order: `a`, `b`, `b_length`, `a_length`.

## Function `lantern_bld_status`

The status of a builder's HTTP answer.

### Signature

```
lantern_bld_status(answer, scratch) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `answer` | input | ByteList: the answer's bytes |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |

### Function does

- Returns the HTTP status of the answer, from lantern_http_parse_response with eof 1 and its body at the end of `scratch`; or 0 when it is none.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_bld_status`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `answer`, `scratch`.

## Function `lantern_http_chunks`

Checks or copies a chunked request body.

### Signature

```
lantern_http_chunks(destination, bytes, length, start, head_max, body_max) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `destination` | output | the body's bytes, or 0 to check |
| `bytes` | input | `length` bytes |
| `length` | input | u64 in a register |
| `start` | input | u64 in a register: the index of the chunked body |
| `head_max` | input | u64 in a register |
| `body_max` | input | u64 in a register |

### Returns

- `LANTERN_OK`: also gives the index past the trailers and the body's bytes.
- `LANTERN_HTTP_MORE`: the bytes end before the body.
- `LANTERN_INVALID_HTTP`: also gives the HTTP status.

### Function does

- With `destination` 0, checks the chunked body by lantern_http_request's rules (RFC 9112 section 7.1).
- With a destination, copies a body checked before there.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_http_chunks`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It returns the second and third values in x1 and x2 on ARM64, rdx and rcx on x86-64, a1 and a2 on RISC-V.
- Registers it changes, on ARM64 and RISC-V: x0 to x2, x6 to x17; a0 to a2, a6, a7, t0 to t5.
- Argument order: `destination`, `bytes`, `length`, `start`, `head_max`, `body_max`.

## Function `lantern_http_crlf`

The first CRLF in a range of bytes.

### Signature

```
lantern_http_crlf(bytes, first, end) -> index
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | the bytes |
| `first` | input | u64 in a register |
| `end` | input | u64 in a register |

### Function does

- Returns the index of the first CRLF that starts in [`first`, `end` - 1), else `end`.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_http_crlf`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x11; rax, r8; a0, t0 to t3.
- Argument order: `bytes`, `first`, `end`.

## Function `lantern_http_find`

The first place of a byte in a range of bytes.

### Signature

```
lantern_http_find(bytes, first, end, byte) -> index
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | the bytes |
| `first` | input | u64 in a register |
| `end` | input | u64 in a register |
| `byte` | input | u8 in a register |

### Function does

- Returns the index of the first `byte` in [`first`, `end`), else `end`.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_http_find`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It takes `byte` in w3, cl, a3.
- Registers it changes, on ARM64 and RISC-V: x0, x9, x10; a0, t0, t1.
- Argument order: `bytes`, `first`, `end`, `byte`.

## Function `lantern_http_joined`

The joined values of the field lines of a name.

### Signature

```
lantern_http_joined(bytes, first, head_end, name, name_length, request, offset, ref) -> offset
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | the request's bytes |
| `first` | input | u64 in a register: the index of the first field line |
| `head_end` | input | u64 in a register: the index of the head's CRLF CRLF |
| `name` | input | `name_length` lower case bytes |
| `name_length` | input | u64 in a register |
| `request` | output | [`HttpRequest`](#type-httprequest) |
| `offset` | input | u64 in a register: the part's offset in `request` |
| `ref` | input | u64 in a register: the offset of its PartRef in `request` |

### Caller must

- The field lines are checked.

### Function does

- Joins the values of the field lines of the name with ", " into a part of `request` at `offset`, its PartRef at `ref`.
- Returns the next part's offset.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_http_joined`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `bytes`, `first`, `head_end`, `name`, `name_length`, `request`, `offset`, `ref`.

## Function `lantern_http_part`

Puts bytes as a part of an HttpRequest.

### Signature

```
lantern_http_part(request, offset, bytes, length, ref) -> offset
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `request` | output | [`HttpRequest`](#type-httprequest) |
| `offset` | input | u64 in a register |
| `bytes` | input | `length` bytes |
| `length` | input | u64 in a register |
| `ref` | input | u64 in a register: the offset of the PartRef in `request` |

### Function does

- Copies the bytes into a part of `request` at `offset`, its PartRef at `ref`.
- Returns `offset` + `length` rounded up to a multiple of 8.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_http_part`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9, x10; rax, r9; a0, t0, t1.
- Argument order: `request`, `offset`, `bytes`, `length`, `ref`.

## Function `lantern_http_same`

Whether bytes equal lower case bytes without regard to ASCII case.

### Signature

```
lantern_http_same(a, a_length, b, b_length) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `a` | input | `a_length` bytes |
| `a_length` | input | u64 in a register |
| `b` | input | `b_length` lower case bytes |
| `b_length` | input | u64 in a register |

### Function does

- Returns 1 when the bytes of `a` are those of `b` without regard to ASCII case, else 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_http_same`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x11; rax, r8; a0, t0 to t2.
- Argument order: `a`, `a_length`, `b`, `b_length`.

## Function `lantern_http_token`

Whether a range of bytes is a token.

### Signature

```
lantern_http_token(bytes, first, end) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | the bytes |
| `first` | input | u64 in a register |
| `end` | input | u64 in a register |

### Function does

- Returns 1 when [`first`, `end`) is a token (RFC 9110 section 5.6.2), else 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_http_token`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x13; rax, r8; a0, t0 to t3.
- Argument order: `bytes`, `first`, `end`.

## Function `lantern_http_trim`

A range of bytes without its leading and trailing white space.

### Signature

```
lantern_http_trim(bytes, first, end) -> (first, end)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | the bytes |
| `first` | input | u64 in a register |
| `end` | input | u64 in a register |

### Function does

- Returns the start and end of [`first`, `end`) without leading and trailing spaces and tabs.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_http_trim`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Registers it changes, on ARM64 and RISC-V: x0, x1, x9, x10; a0, a1, t0 to t2.
- Argument order: `bytes`, `first`, `end`.

## Function `lantern_jd_fault`

Records a fault of the JSON decoder.

### Signature

```
lantern_jd_fault(fault, at, depth) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `fault` | input | u64 in a register: the fault |
| `at` | input | the byte, or past the end |
| `depth` | input | u64 in a register |

### Function does

- Records the fault at the byte (the end when past it) and the depth in the decoder's [`JsonFault`](#type-jsonfault).
- Gives the fault flag 1.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_jd_fault`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It gives the flag in x1, rax, a1.
- Registers it changes, on ARM64, x86-64, RISC-V: x1, x9; rax, rcx; a1, t0.
- Argument order: `fault`, `at`, `depth`.

## Function `lantern_jd_hexdigit`

The value of a hex digit.

### Signature

```
lantern_jd_hexdigit(byte) -> value
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `byte` | input | u8 in a register |

### Function does

- Returns the value of the hex digit, or 16 for another byte.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_jd_hexdigit`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0; rax; a0, t0.
- Argument order: `byte`.

## Function `lantern_jd_key`

Skips a key of a skipped object.

### Signature

```
lantern_jd_key(cursor, depth) -> (cursor, flag)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `cursor` | input | the text at `"name":` |
| `depth` | input | u64 in a register |

### Function does

- Gives the first byte of the key's value; else a fault at `depth`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_jd_key`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- The decoder returns the cursor and a fault flag: in x0 and x1 on ARM64, rdi and rax on x86-64, a0 and a1 on RISC-V.
- Argument order: `cursor`, `depth`.

## Function `lantern_jd_literal`

Whether a literal starts at a place of the JSON text.

### Signature

```
lantern_jd_literal(at, text, length) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `at` | input | the place in the JSON text |
| `text` | input | `length` bytes |
| `length` | input | u64 in a register |

### Function does

- Gives 1 when the bytes of `text` start at `at` below the text's end, else 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_jd_literal`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It gives the flag in x1, eax, a1.
- Registers it changes, on ARM64, x86-64, RISC-V: x1, x9 to x12; rax, rcx, r8; a1, t0 to t3.
- Argument order: `at`, `text`, `length`.

## Function `lantern_jd_number`

Reads a JSON number.

### Signature

```
lantern_jd_number(cursor, depth) -> (cursor, flag)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `cursor` | input | the number's first byte |
| `depth` | input | u64 in a register |

### Function does

- Gives the byte after the number (RFC 8259 section 6); else a fault at `depth`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_jd_number`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- The decoder returns the cursor and a fault flag: in x0 and x1 on ARM64, rdi and rax on x86-64, a0 and a1 on RISC-V.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1, x3, x9, x10; rax, rcx, rdi; a0, a1, t0, t1.
- Argument order: `cursor`, `depth`.

## Function `lantern_jd_offset`

Writes a 4-byte offset into the encoding.

### Signature

```
lantern_jd_offset(offset, at)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `offset` | input | u32 in a register |
| `at` | input | u64 in a register: the byte of the encoding |

### Function does

- Writes the offset at the byte of the encoding when the decoder writes.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_jd_offset`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the write flag, 1 to write, in x24, r15, s6.
- Registers it changes, on ARM64 and RISC-V: x9; t0.
- Argument order: `offset`, `at`.

## Function `lantern_jd_out`

Joins bytes to the encoding.

### Signature

```
lantern_jd_out(bytes, length)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | `length` bytes |
| `length` | input | u64 in a register |

### Function does

- The bytes join the encoding; written when the decoder writes.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_jd_out`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the write flag, 1 to write, in x24, r15, s6.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1, x9, x10; rcx, rdx; t0, t1.
- Argument order: `bytes`, `length`.

## Function `lantern_jd_skip`

Skips a JSON value with only the checks of the text.

### Signature

```
lantern_jd_skip(cursor, depth) -> (cursor, flag)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `cursor` | input | the value's first byte |
| `depth` | input | u64 in a register |

### Function does

- Gives the byte after the value; faults at `depth`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_jd_skip`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- The decoder returns the cursor and a fault flag: in x0 and x1 on ARM64, rdi and rax on x86-64, a0 and a1 on RISC-V.
- Argument order: `cursor`, `depth`.

## Function `lantern_jd_string`

Reads a JSON string.

### Signature

```
lantern_jd_string(cursor, depth) -> (cursor, flag, first, end)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `cursor` | input | the string's quote |
| `depth` | input | u64 in a register |

### Function does

- Gives the byte after the closing quote, and the string's first byte and end.
- A `\` or a byte below 0x20, or the end, is a fault at `depth`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_jd_string`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- The decoder returns the cursor and a fault flag: in x0 and x1 on ARM64, rdi and rax on x86-64, a0 and a1 on RISC-V.
- It gives the string's first byte and end in x3 and x4, r8 and r9, a3 and a4.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1, x3, x4, x9; rax, rcx, rdi, r8, r9; a0, a1, a3, a4, t0, t1.
- Argument order: `cursor`, `depth`.

## Function `lantern_jd_value`

Decodes a JSON value of a type node.

### Signature

```
lantern_jd_value(node, cursor, depth) -> (cursor, flag)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `node` | input | a type node |
| `cursor` | input | the value's first byte |
| `depth` | input | u64 in a register |

### Function does

- Its encoding joins the encoding; gives the byte after the value; else a fault.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 176 bytes on x86-64 (return address included), 176 bytes on ARM64, 176 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_jd_value`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- The decoder returns the cursor and a fault flag: in x0 and x1 on ARM64, rdi and rax on x86-64, a0 and a1 on RISC-V.
- Registers it reads, on ARM64, x86-64, RISC-V: the encoding in x23, r13, s5; the write flag in x24, r15, s6.
- Argument order: `node`, `cursor`, `depth`.

## Function `lantern_jd_ws`

Skips JSON white space.

### Signature

```
lantern_jd_ws(cursor) -> cursor
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `cursor` | input | a byte of the JSON text |

### Function does

- Returns the first byte at or after `cursor` that is no white space.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_jd_ws`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9; rax; a0, t0.
- Argument order: `cursor`.

## Function `lantern_json_child`

Opens the next item of a compound level of the JSON encoder.

### Signature

```
lantern_json_child()
```

### Function does

- Opens the next item of the compound level at index `item`, one level deeper.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_json_child`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the level in x28, r12, s10, and the other registers of lantern_json_open.

## Function `lantern_json_decode_mode`

lantern_json_decode or lantern_engine_json_decode by a mode.

### Signature

```
lantern_json_decode_mode(type, json, scratch, out, fault, mode) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `type` | input | the asm-ssz type descriptor |
| `json` | input | ByteList |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `out` | output | the SSZ encoding |
| `fault` | output | [`JsonFault`](#type-jsonfault) |
| `mode` | input | u64 in a register: 0 Beacon API, 1 Engine API |

### Returns

- As lantern_json_decode.

### Function does

- Mode 0 decodes the Beacon API's JSON, as lantern_json_decode; mode 1 the Engine API's, as lantern_engine_json_decode.
- Keeps the mode at byte 56 of `scratch`, before the field tables.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_json_decode_mode`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `type`, `json`, `scratch`, `out`, `fault`, `mode`.

## Function `lantern_json_hex`

Writes the hex token of a byte or bit string of the JSON encoder.

### Signature

```
lantern_json_hex(kind) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `kind` | input | u64 in a register |

### Function does

- Writes the token's bytes from the cursor's done bytes on, while `out` has room.
- Returns 0 when the token is whole, else 1.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_json_hex`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the level in x28, r12, s10.
- Registers it changes, on ARM64, x86-64, RISC-V: x0 to x7, x9 to x15; rax, rcx, rdx, rsi, r8 to r11; a0 to a5, t0 to t6.
- Argument order: `kind`.

## Function `lantern_json_main`

The JSON of a value or of an SSZ encoding, a chunk at a time.

### Signature

```
lantern_json_main(type, value, cursor, out, mode, length) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `type` | input | the asm-ssz type descriptor |
| `value` | input | the value, or the SSZ encoding |
| `cursor` | state | [`JsonCursor`](#type-jsoncursor) |
| `out` | output | ByteList |
| `mode` | input | u64 in a register: 0 a value, 1 an encoding |
| `length` | input | u64 in a register: the encoding's bytes |

### Returns

- As lantern_json_encode.

### Function does

- The body of lantern_json_encode (mode 0) and lantern_json_encode_ssz (mode 1).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_json_main`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `type`, `value`, `cursor`, `out`, `mode`, `length`.

## Function `lantern_json_number`

Writes the token of a uint or Boolean of the JSON encoder.

### Signature

```
lantern_json_number(kind) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `kind` | input | u64 in a register |

### Function does

- Writes the token from the cursor's done bytes on, while `out` has room.
- Returns 0 when the token is whole, else 1.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_json_number`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the level in x28, r12, s10.
- Argument order: `kind`.

## Function `lantern_json_open`

Opens a level of the JSON encoder for a type node.

### Signature

```
lantern_json_open(node, offset, base)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `node` | input | a type node |
| `offset` | input | u64 in a register: the storage's offset in the value |
| `base` | input | u64 in a register: 2^64 - 1, or the base of a PartRef's offset |

### Function does

- With `base` 2^64 - 1: inline for a type of fixed size; a value of its own with its size first for a type of variable size.
- Else the storage is a PartRef at `offset` whose offset counts from `base`.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_json_open`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the level in x28, r12, s10.
- Registers it changes, on ARM64, x86-64, RISC-V: x3 to x7, x9 to x12; rax, r8 to r11; t0 to t4.
- Argument order: `node`, `offset`, `base`.

## Function `lantern_json_put`

Writes the bytes of a token of the JSON encoder.

### Signature

```
lantern_json_put(bytes, length) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | `length` bytes |
| `length` | input | u64 in a register |

### Function does

- Writes the token's bytes from the cursor's done bytes on, while `out` has room.
- Returns 0 when the token is whole (done 0), else 1 (done counts the bytes written).

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_json_put`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x12; rax, rcx, rdx; a0, t0, t1.
- Argument order: `bytes`, `length`.

## Function `lantern_jss_child`

Opens the next item of a compound level of an SSZ encoding.

### Signature

```
lantern_jss_child()
```

### Function does

- Opens the next item of the compound level at index `item`, one level deeper.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_jss_child`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the level in x28, r12, s10, and the other registers of lantern_jss_open.

## Function `lantern_jss_field_end`

The end of a variable field of a container in an SSZ encoding.

### Signature

```
lantern_jss_field_end(field) -> offset
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `field` | input | u64 in a register: a field index |

### Function does

- Returns the offset of the next variable field after `field` of the container level, or the level's end with none.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_jss_field_end`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It takes the field in x1, rsi, a1.
- Registers it reads, on ARM64, x86-64, RISC-V: the level in x28, r12, s10.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x13; rax, rcx, r8 to r11; a0, t0 to t5.
- Argument order: `field`.

## Function `lantern_jss_open`

Opens a level of the JSON encoder for an SSZ encoding.

### Signature

```
lantern_jss_open(node, first, end)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `node` | input | a type node |
| `first` | input | u64 in a register: the byte of the encoding where it starts |
| `end` | input | u64 in a register: its end |

### Function does

- Sets the level's base and end (`next`), and the count of its items or bytes.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_jss_open`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the level in x28, r12, s10.
- Registers it changes, on ARM64, x86-64, RISC-V: x3 to x5, x9 to x12; rax, r8 to r11; t0 to t4.
- Argument order: `node`, `first`, `end`.

## Function `lantern_node_bid_data`

The JSON of the bid in a builder's getHeader answer.

### Signature

```
lantern_node_bid_data(answer, scratch, fork) -> (status, data, length)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `answer` | input | ByteList: the answer's bytes |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `fork` | input | u64 in a register |

### Returns

- `LANTERN_OK`: also gives the text of `data` and its bytes.
- `LANTERN_INVALID_HTTP`, `LANTERN_NO_BID`, `LANTERN_INVALID_JSON`, `LANTERN_INVALID_BID` or `LANTERN_BUFFER_TOO_SMALL`.

### Function does

- Parses the answer with lantern_http_parse_response, eof 1, the body unchunked at the end of `scratch`, whose size drops below it; the caller restores it (node.md, NODE_WORK_PRODUCE_BID).
- Needs status 200, and a body that is an object whose first member `version` is a string, the fork's name, and whose first member `data` is a value.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 128 bytes on ARM64, 160 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_bid_data`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It returns three values: x0 to x2; rax, rdx, rcx; a0 to a2.
- Argument order: `answer`, `scratch`, `fork`.

## Function `lantern_node_builder_call`

Takes an entry of builder_calls.

### Signature

```
lantern_node_builder_call(kind, api) -> index
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `kind` | input | u64 in a register |
| `api` | input | u64 in a register: the NodeApi entry |

### Function does

- Returns the index of a free entry of `builder_calls`, now of the kind, the NodeApi entry and `time_ms`; 2^64 - 1 with none free (node.md, the builder calls).

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_builder_call`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x12, x16; rax, rcx, rdx; a0, a7, t0 to t3.
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Argument order: `kind`, `api`.

## Function `lantern_node_builder_event`

Takes a NODE_EV_BUILDER event.

### Signature

```
lantern_node_builder_event(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | `NodeEvent` of kind `NODE_EV_BUILDER` |

### Function does

- A header call that its produceBlockV3 entry still awaits ends there: the answer's bytes in a BYTES_PUT to a new id at `PRODUCE_BID` when the call did not fail and the actions have room (node.md, the builder calls).
- Then the call's entry goes free.
- A submit call answers its publish entry.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_builder_event`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It takes the event in x21, r12, s3.
- Registers it reads, on ARM64, x86-64, RISC-V: the scratch in x23, r14, s5; the actions in x24, r15, s6.
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Argument order: `event`.

## Function `lantern_node_builder_register`

Sends the valid registrations of a registerValidator to the builder.

### Signature

```
lantern_node_builder_register(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | `NodeEvent` of kind `NODE_EV_WORK_DONE` of a NODE_WORK_API_SUBMIT of registerValidator |

### Function does

- With `NODE_FLAG_BUILDER`: a NODE_BUILDER_REGISTER call of the JSON array of the registrations of `LANTERN_VALID` (node.md).
- None with none, with no free call, or with no room in the actions.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_builder_register`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It takes the event in x21, r12, s3.
- Registers it reads, on ARM64, x86-64, RISC-V: the actions in x24, r15, s6.
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Argument order: `event`.

## Function `lantern_node_produce_header`

Sends the builder's header call of a produceBlockV3 entry.

### Signature

```
lantern_node_produce_header(entry, event, hash)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the produceBlockV3 `NodeApi` entry |
| `event` | input | `NodeEvent` of its PRODUCE_CHECK |
| `hash` | input | Bytes32: the head's block_hash |

### Function does

- On the way into `NODE_PRODUCE_PAYLOAD` (node.md, Block production), with `NODE_FLAG_BUILDER`: a NODE_BUILDER_HEADER call of its slot, the hash and the pubkey of the proposer's NodeProposer entry.
- Only when builder_boost_factor is not 0, the entry has registered 1, the head's NodeBlock is not NOT_VALIDATED, and the check says the chain is healthy.
- The entry keeps the call + 1 and the registration's fee recipient.
- None with no free call or no room in the actions.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_produce_header`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the store in x20, rbp, s2; the actions in x24, r15, s6.
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Argument order: `entry`, `event`, `hash`.

## Function `lantern_node_publish_submit`

Sends the submitBlindedBlockV2 call of a publishBlindedBlockV2 entry.

### Signature

```
lantern_node_publish_submit(entry, json) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the publishBlindedBlockV2 `NodeApi` entry |
| `json` | input | ByteList: the block's JSON |

### Returns

- 0: the call went; the entry is in `NODE_PUBLISH_SUBMIT` with the call + 1 at `PUBLISH_CALL`.
- 500: no builder, no free call or no room.

### Function does

- Writes the call's request (node.md, NODE_PUBLISH_SUBMIT).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_publish_submit`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the actions in x24, r15, s6.
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Argument order: `entry`, `json`.

## Function `lantern_node_registration_put`

Keeps a validator's builder registration.

### Signature

```
lantern_node_registration_put(registration, index)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `registration` | input | ByteList: the 180 SSZ bytes of a `SignedValidatorRegistrationV1` of `LANTERN_VALID` |
| `index` | input | u64 in a register: the validator index |

### Function does

- The validator's NodeProposer entry takes it, unless the entry holds one of a later timestamp (beacon-APIs registerValidator).
- With no entry: the first free one (until_epoch at most the store's epoch, registered 0), else a new one when the part has room; else none.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_registration_put`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the store in x20, rbp, s2.
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Argument order: `registration`, `index`.

## Function `lantern_node_registrations_find`

The validators of the records of a registerValidator.

### Signature

```
lantern_node_registrations_find(state, records, count, scratch) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `records` | state | the draft records of the registrations |
| `count` | input | u64 in a register |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |

### Returns

- `LANTERN_OK`: each record is marked.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has no room for the table.

### Function does

- One scan of the state's validators through a table of the records' pubkeys at the end of `scratch`: a power of two of slots, at least twice the count, each a record or 0 (node.md, NODE_WORK_API_SUBMIT).
- Each record whose pubkey is of a validator eligible at the state's epoch (builder-specs is_eligible_for_registration) takes `LANTERN_VALID` and the validator's index.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_registrations_find`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `state`, `records`, `count`, `scratch`.

## Function `lantern_route_decode`

Percent-decodes bytes.

### Signature

```
lantern_route_decode(bytes, length, out, room) -> length
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | `length` bytes, each % followed by two hex digits |
| `length` | input | u64 in a register |
| `out` | output | at most `room` bytes |
| `room` | input | u64 in a register |

### Function does

- Writes the bytes, percent-decoded, to `out`, at most `room` bytes.
- Returns the decoded length, which may pass `room`.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_route_decode`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x13; rax, r8 to r11; a0, t0 to t6.
- Argument order: `bytes`, `length`, `out`, `room`.

## Function `lantern_route_hex`

Reads a 0x hex text of a fixed length.

### Signature

```
lantern_route_hex(text, length, bytes, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `text` | input | `length` bytes |
| `length` | input | u64 in a register |
| `bytes` | input | u64 in a register: the value's bytes |
| `out` | output | `bytes` bytes |

### Function does

- Returns 0 with the value in `out` when the text is 0x and the hex of `bytes` bytes, else 1.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_route_hex`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x12; rax, r8, r9; a0, t0 to t3.
- Argument order: `text`, `length`, `bytes`, `out`.

## Function `lantern_route_ids_array`

Reads null or an array of strings of a body parameter.

### Signature

```
lantern_route_ids_array(param) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `param` | input | u64 in a register: `API_PARAM_ID` or `API_PARAM_STATUS` |

### Function does

- Each string is an item of the parameter: `API_PARAM_ID` into the list of `out`, `API_PARAM_STATUS` its bits; its bit of `present` is set.
- Returns 0, or the fault + 1.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_route_ids_array`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads and moves, on ARM64, x86-64, RISC-V: the body cursor in x21, r12, s3; it reads the body end in x25, r13, s4.
- Registers it reads, on ARM64, x86-64, RISC-V: the stack of lantern_api_route in x22, r15, s6.
- Argument order: `param`.

## Function `lantern_route_key`

Which list parameter a body key names.

### Signature

```
lantern_route_key(length) -> param
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `length` | input | u64 in a register: the key's bytes |

### Function does

- Returns `API_PARAM_ID` when the key is ids, `API_PARAM_STATUS` when it is statuses, else 0.
- The key is at 192 of the locals of lantern_api_route.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_route_key`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It takes the length in x1, rcx, a1.
- Registers it reads, on ARM64, x86-64, RISC-V: the stack of lantern_api_route in x22, r15, s6.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x13; rax, rdx, rsi, rdi, r8; a0, a2, t0 to t3.
- Argument order: `length`.

## Function `lantern_route_lit`

Whether a literal starts the body at the cursor.

### Signature

```
lantern_route_lit(bytes, length) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | `length` bytes |
| `length` | input | u64 in a register |

### Function does

- Returns 1 when the bytes start the body at the cursor, before its end, and moves the cursor past them; else 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_route_lit`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads and moves, on ARM64, x86-64, RISC-V: the body cursor in x21, r12, s3; it reads the body end in x25, r13, s4.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x11; rax, rcx; a0, t0 to t2.
- Argument order: `bytes`, `length`.

## Function `lantern_route_match`

Whether a path matches a route template.

### Signature

```
lantern_route_match(path, length, template, template_length, params) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `path` | input | `length` bytes whose percent-encoding is good |
| `length` | input | u64 in a register |
| `template` | input | `template_length` bytes |
| `template_length` | input | u64 in a register |
| `params` | output | the list of the parameter segments |

### Function does

- Returns 1 when the path matches the template, else 0.
- Each parameter segment goes to the list: its count, then for each its API_PARAM_*, start and end in the path.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_route_match`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64 and RISC-V: x0, x9 to x15; a0, a5, a6, t0 to t6.
- Argument order: `path`, `length`, `template`, `template_length`, `params`.

## Function `lantern_route_next_item`

One item of a list value.

### Signature

```
lantern_route_next_item(bytes, first, end, out, room) -> (next, length, comma)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | the value's bytes |
| `first` | input | u64 in a register |
| `end` | input | u64 in a register |
| `out` | output | at most `room` bytes |
| `room` | input | u64 in a register |

### Function does

- Writes the bytes from `first` to `end`, percent-decoded, up to the first decoded comma, to `out`, at most `room` bytes.
- Returns the index after the item and its comma, the item's decoded length (it may pass `room`), and 1 when a comma ended it.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_route_next_item`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It returns three values: x0 to x2; rax, rdx, rcx; a0 to a2.
- Registers it changes, on ARM64, x86-64, RISC-V: x0 to x2, x5, x9 to x13; rax, rcx, rdx, r9 to r11; a0 to a2, a5, t0 to t6.
- Argument order: `bytes`, `first`, `end`, `out`, `room`.

## Function `lantern_route_number`

Reads a decimal number below 2^64.

### Signature

```
lantern_route_number(text, length) -> (status, value)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `text` | input | `length` bytes |
| `length` | input | u64 in a register |

### Function does

- Returns 0 and the value when the text is a decimal number below 2^64, else 1.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_route_number`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1, x9 to x13; rax, rcx, rdx, r8, r9; a0, a1, t0 to t4.
- Argument order: `text`, `length`.

## Function `lantern_route_pct_ok`

Whether the percent-encoding of bytes is good.

### Signature

```
lantern_route_pct_ok(bytes, length) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | `length` bytes |
| `length` | input | u64 in a register |

### Function does

- Returns 1 when each % of the bytes is followed by two hex digits, else 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_route_pct_ok`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x12; rax, rcx, rdx, r8; a0, t0 to t5.
- Argument order: `bytes`, `length`.

## Function `lantern_route_string`

Reads a JSON string of the body.

### Signature

```
lantern_route_string() -> (status, length)
```

### Function does

- Writes the value of the JSON string at the cursor (RFC 8259 section 7), each escape decoded (a \\u of 0x80 or more as the byte 0x80), into the 200 bytes at 192 of the locals of lantern_api_route; moves the cursor past it.
- Returns 0, or 1 when it breaks the rules, then the value's length, 201 when it is longer than 200.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_route_string`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads and moves, on ARM64, x86-64, RISC-V: the body cursor in x21, r12, s3; it reads the body end in x25, r13, s4.
- Registers it reads, on ARM64, x86-64, RISC-V: the stack of lantern_api_route in x22, r15, s6.
- It returns the length in x1, rcx, a1.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1, x9 to x13; rax, rcx, rdx, rsi, r8; a0, a1, t0 to t3.

## Function `lantern_route_value`

Reads the value of a parameter into an ApiRoute.

### Signature

```
lantern_route_value(route, param, bytes, length, item) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `route` | output | [`ApiRoute`](#type-apiroute) |
| `param` | input | u64 in a register |
| `bytes` | input | `length` decoded bytes |
| `length` | input | u64 in a register |
| `item` | output | 64 bytes: an item of a list |

### Function does

- Writes the value of the parameter into `route`; an item of a list goes to `item`.
- Returns 0, or 1 when the value breaks its type.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_route_value`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `route`, `param`, `bytes`, `length`, `item`.

## Function `lantern_route_weight`

The weight an Accept value gives a media type.

### Signature

```
lantern_route_weight(accept, length, media, media_length) -> weight
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `accept` | input | `length` bytes |
| `length` | input | u64 in a register |
| `media` | input | `media_length` lower case bytes |
| `media_length` | input | u64 in a register |

### Function does

- Returns the weight, 0 to 1000, that the Accept value gives the media type, by lantern_api_route's rules.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_route_weight`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `accept`, `length`, `media`, `media_length`.

## Function `lantern_route_word`

The value of a word of a parameter.

### Signature

```
lantern_route_word(param, word, length) -> (flag, value)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `param` | input | u64 in a register |
| `word` | input | `length` bytes |
| `length` | input | u64 in a register |

### Function does

- Returns 1 and the word's value when the bytes are a word of `api_words` for the parameter, else 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_route_word`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1, x6, x7, x9 to x14; rax, rcx, rdx, r8 to r11; a0, a1, t0 to t6.
- Argument order: `param`, `word`, `length`.

## Function `lantern_route_ws`

Skips JSON white space of the body.

### Signature

```
lantern_route_ws()
```

### Function does

- Moves the cursor past the JSON white space (space, tab, LF, CR) before the body's end.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_route_ws`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads and moves, on ARM64, x86-64, RISC-V: the body cursor in x21, r12, s3; it reads the body end in x25, r13, s4.
- Registers it changes, on ARM64, x86-64, RISC-V: x9; rax; t0, t1.

## Function `lantern_api_base58`

The base58btc text of some bytes.

### Signature

```
lantern_api_base58(bytes, length, out, work) -> length
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | `length` bytes, at most 48 |
| `length` | input | u64 in a register |
| `out` | output | the text |
| `work` | scratch | 72 bytes |

### Function does

- Writes a 1 for each leading zero byte, then the base58btc digits.
- Returns the text's length.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 0 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_base58`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64: x0, x4, x9 to x15.
- Argument order: `bytes`, `length`, `out`, `work`.

## Function `lantern_api_blob_body`

The body of the blob stream.

### Signature

```
lantern_api_blob_body(sidecar, hashes) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `sidecar` | input | the sidecar's SSZ bytes, or 0 |
| `hashes` | input | ByteList of Root items: the versioned hashes asked, or 0 |

### Returns

- 1: the answer is whole.
- 0: more is to come.
- 2: the bytes are no encoding.

### Function does

- As lantern_api_stream_json (node.md, NODE_WORK_API_CHUNK, the blob stream): the bytes of the sidecar's blob, or of its cell, from `sent` of the event, as many as fit, as JSON in lower case hex.
- With `sidecar` 0, or a blob past the last: `]}`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 80 bytes on x86-64 (return address included), 48 bytes on ARM64, 80 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_blob_body`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the stream registers of lantern_api_stream_json.
- It takes the sidecar in x21, rdi, s3, and the hashes in x20, rsi, a1.
- Argument order: `sidecar`, `hashes`.

## Function `lantern_api_blob_wanted`

Whether a commitment's versioned hash is asked for.

### Signature

```
lantern_api_blob_wanted(commitment, hashes) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `commitment` | input | 48 bytes: a KZGCommitment |
| `hashes` | input | ByteList of Root items |

### Function does

- Returns 1 when kzg_commitment_to_versioned_hash of the commitment (deneb beacon-chain.md: `VERSIONED_HASH_VERSION_KZG`, then the last 31 bytes of its sha256) is one of the items, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_blob_wanted`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It takes the hashes in x20, rsi, a1.
- Argument order: `commitment`, `hashes`.

## Function `lantern_api_body`

Writes the body of a response.

### Signature

```
lantern_api_body(status)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `status` | input | the status, for an error body |

### Function does

- Writes the body of the kind for the view: an error body of the status, or the JSON of an operation (lantern_node_api_event).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_body`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put, and the body kind in x28, at S7, in s10.
- Argument order: `status`.

## Function `lantern_api_bool`

Writes a JSON Boolean.

### Signature

```
lantern_api_bool(flag)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `flag` | input | u64 in a register |

### Function does

- Writes `true` when `flag` is not 0, else `false`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_bool`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.
- Argument order: `flag`.

## Function `lantern_api_checkpoint`

Writes a Checkpoint of the view.

### Signature

```
lantern_api_checkpoint(checkpoint)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `checkpoint` | input | a `Checkpoint` of the view |

### Function does

- Writes `{"epoch":…,"root":…}`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_checkpoint`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.
- Argument order: `checkpoint`.

## Function `lantern_api_code`

The api_codes entry of a status.

### Signature

```
lantern_api_code(status) -> entry
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `status` | input | u64 in a register |

### Function does

- Returns the `api_codes` entry of the status, or 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_code`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x11; rax, rcx; a0, t0 to t2.
- Argument order: `status`.

## Function `lantern_api_code_text`

Writes a text of an api_codes entry.

### Signature

```
lantern_api_code_text(entry, field)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | input | an `api_codes` entry, or 0 |
| `field` | input | u64 in a register: 8 the reason phrase, 24 the message |

### Function does

- Writes the text at the field of the entry; none for no entry.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_code_text`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.
- Argument order: `entry`, `field`.

## Function `lantern_api_committees_json`

Writes the items of the getEpochCommittees stream.

### Signature

```
lantern_api_committees_json(state) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |

### Returns

- 1: the answer is whole.
- 0: more is to come.
- 2: a committee fails.

### Function does

- Writes the items from the cursor at `NodeEvent_api` + 16 of the event, then `]}` once they are all written.
- The cursor: +0 the slot, +8 the index, +16 the member, +24 the epoch, +32 the items written, +40 and +48 the slot and the index asked or 2^64 - 1, +56 the committees per slot, +64 1 within an item, +72 the scratch, +80 the CommitteeCache.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 64 bytes on x86-64 (return address included), 64 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_committees_json`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the stream registers of lantern_api_stream_json.
- It takes the state in x20, rdi, s3.
- Argument order: `state`.

## Function `lantern_api_dec`

Writes a number in decimal.

### Signature

```
lantern_api_dec(value)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `value` | input | u64 in a register |

### Function does

- Writes the decimal digits of `value`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_dec`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.
- Argument order: `value`.

## Function `lantern_api_dec256`

Writes a 256-bit number in decimal.

### Signature

```
lantern_api_dec256(value)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `value` | input | 32 bytes: a little-endian number |

### Function does

- Writes the decimal digits of the number.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_dec256`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.
- Argument order: `value`.

## Function `lantern_api_duties_json`

Writes the JSON of getAttesterDuties.

### Signature

```
lantern_api_duties_json()
```

### Function does

- Writes `{"dependent_root":…,"execution_optimistic":…,"data":[{"pubkey":…,…,"slot":…},…]}` from the view, an item for each record with an assignment.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_duties_json`, local to its object. Only x86-64 and RISC-V have it.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.

## Function `lantern_api_event_text`

The text of an event of a topic.

### Signature

```
lantern_api_event_text(view, out, topic) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `view` | input | `ApiView` |
| `out` | output | ByteList, its count set |
| `topic` | input | u64 in a register |

### Returns

- `LANTERN_OK`: `out` holds the event's text.
- `LANTERN_BUFFER_TOO_SMALL`: `out` is short.

### Function does

- Writes the text of the event of the topic from the view's event fields (lantern_node_api_event).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_event_text`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: the registers of the lantern_api_put writer.
- Argument order: `view`, `out`, `topic`.

## Function `lantern_api_failures`

Writes the failures of a NODE_WORK_API_SUBMIT.

### Signature

```
lantern_api_failures(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | `NodeEvent` of the work |

### Function does

- Writes `{"index":<i>,"message":"REJECT"}` for each record of `LANTERN_GOSSIP_REJECT`, with , between, then `]}`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_failures`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.
- It takes the event in x22, rbp, s4.
- Argument order: `event`.

## Function `lantern_api_fork_choice_body`

Writes the body of getDebugForkChoice.

### Signature

```
lantern_api_fork_choice_body()
```

### Function does

- Writes `{"justified_checkpoint":…,"finalized_checkpoint":…,"fork_choice_nodes":[…]}` of the store at `ApiView_val_state` of the view, each node's weight at `ApiView_weights`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_fork_choice_body`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.

## Function `lantern_api_fork_name`

Writes the name of a fork.

### Signature

```
lantern_api_fork_name(fork)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `fork` | input | u64 in a register |

### Function does

- Writes the fork's name.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 16 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_fork_name`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.
- Argument order: `fork`.

## Function `lantern_api_fork_schedule`

Writes the body of getForkSchedule.

### Signature

```
lantern_api_fork_schedule()
```

### Function does

- Writes, with the config of the view, phase0, then each fork to fulu whose epoch is below 2^64 - 1 (lantern_node_api_event).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_fork_schedule`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.

## Function `lantern_api_header_json`

Writes the fields of a block header item.

### Signature

```
lantern_api_header_json(slot, header, canonical)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `slot` | input | u64 in a register |
| `header` | input | the header's proposer_index, parent_root, state_root, body_root and signature, in that order |
| `canonical` | input | u64 in a register |

### Function does

- Writes `,"canonical":…,"header":{"message":{"slot":…,"proposer_index":…,"parent_root":…,"state_root":…,"body_root":…},"signature":…`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_header_json`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.
- Argument order: `slot`, `header`, `canonical`.

## Function `lantern_api_headers_json`

Writes the getBlockHeaders stream.

### Signature

```
lantern_api_headers_json(header) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `header` | input | the address of an item's header: its slot, then the fields lantern_api_header_json reads, or 0 |

### Function does

- As lantern_api_stream_json: the item `{"root":…,"canonical":…,"header":…}`, its root at byte 0 of the entry's cursor and canonical bit 0 of its member, after , when `API_STREAM_ITEMS` is set.
- Then `API_STREAM_ITEMS` and `API_STREAM_ITEM_DONE` in the event.
- With `header` 0: `]}`.
- Returns 1 when the answer is whole, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_headers_json`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the stream registers of lantern_api_stream_json.
- It takes the header in x21, rdi, s3.
- Argument order: `header`.

## Function `lantern_api_heads_body`

Writes the body of getDebugChainHeadsV2.

### Signature

```
lantern_api_heads_body()
```

### Function does

- Writes `{"data":[{"root":…,"slot":…,"execution_optimistic":…},…]}` of the store nodes at `ApiView_val_state` of the view whose byte at `ApiView_heads` is 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_heads_body`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.

## Function `lantern_api_hex16`

Writes 16 bits in hex.

### Signature

```
lantern_api_hex16(value)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `value` | input | u16 in a register |

### Function does

- Writes the lower case hex digits of the 16 bits, with no leading zeros.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_hex16`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.
- Argument order: `value`.

## Function `lantern_api_hex4`

The 4 hex digits of 16 bits.

### Signature

```
lantern_api_hex4(value, out)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `value` | input | u16 in a register |
| `out` | output | 4 bytes |

### Function does

- Writes the 4 lower case hex digits of the value.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_hex4`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x9, x10; rax, rcx, rdx, rdi; a0, a2, t0 to t2.
- Argument order: `value`, `out`.

## Function `lantern_api_liveness_body`

Writes the body of getLiveness.

### Signature

```
lantern_api_liveness_body()
```

### Function does

- Writes `{"data":[{"index":…,"is_live":…},…]}` of the ValidatorRef items at `ApiView_sd_ids` of the view, each by its byte at `ApiView_live_out`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_liveness_body`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.

## Function `lantern_api_names`

Whether ValidatorRef items name a validator.

### Signature

```
lantern_api_names(index, state, refs) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `index` | input | u64 in a register |
| `state` | input | `BeaconState` |
| `refs` | input | ByteList of [`ValidatorRef`](#type-validatorref) items |

### Function does

- Returns 1 when the items name the validator of the state, by its index or its pubkey, else 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_names`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x3 to x13; rax, rcx, r8 to r11; a0, a7, t0 to t6.
- Argument order: `index`, `state`, `refs`.

## Function `lantern_api_op_event_text`

The text of an event of an operation topic.

### Signature

```
lantern_api_op_event_text(out, topic, kind, ssz, cursor) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `out` | output | ByteList, its count set |
| `topic` | input | u64 in a register |
| `kind` | input | u64 in a register |
| `ssz` | input | the operation's SSZ bytes |
| `cursor` | state | [`JsonCursor`](#type-jsoncursor) |

### Returns

- `LANTERN_OK`: `out` holds the event's text.
- `LANTERN_BUFFER_TOO_SMALL`: `out` is short.
- `LANTERN_INVALID_ENCODING`: the bytes are no encoding of the kind.

### Function does

- Writes `event: <topic>` LF `data: ` and lantern_node_json of the kind and the bytes, LF LF (beacon-APIs eventstream).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_op_event_text`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It takes the fork in x15, r10, t6.
- Registers it changes, on ARM64, x86-64, RISC-V: the registers of the lantern_api_put writer.
- Argument order: `out`, `topic`, `kind`, `ssz`, `cursor`.

## Function `lantern_api_payload_event_text`

The text of a payload_attributes event.

### Signature

```
lantern_api_payload_event_text(out, state, attributes, proposer, head) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `out` | output | ByteList, its count set |
| `state` | input | `BeaconState` |
| `attributes` | input | the payload attributes of a preparation |
| `proposer` | input | u64 in a register: the proposer index |
| `head` | input | Root: the head root |

### Returns

- `LANTERN_OK`: `out` holds the event's text.
- `LANTERN_BUFFER_TOO_SMALL`: `out` is short.

### Function does

- Writes `event: payload_attributes` LF `data: {"version":…,"data":{…}}` LF LF (beacon-APIs eventstream).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 144 bytes on ARM64, 192 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_payload_event_text`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It takes the fork in x15, r10, t6.
- Registers it changes, on ARM64, x86-64, RISC-V: the registers of the lantern_api_put writer.
- Argument order: `out`, `state`, `attributes`, `proposer`, `head`.

## Function `lantern_api_peer_item`

Writes a peer of getPeers and getPeer.

### Signature

```
lantern_api_peer_item(peer)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `peer` | input | `NodePeer` |

### Function does

- Writes `{"peer_id":…,"enr":null,"last_seen_p2p_address":…,"state":"connected","direction":…}`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 192 bytes on x86-64 (return address included), 192 bytes on ARM64, 192 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_peer_item`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.
- Argument order: `peer`.

## Function `lantern_api_peers_body`

Writes the body of getPeers.

### Signature

```
lantern_api_peers_body()
```

### Function does

- Writes `{"data":[<peer>,…],"meta":{"count":…}}` of the NodePeers of the view's node whose state and direction are in the sets at `ApiView_peer_states` and `ApiView_peer_directions`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_peers_body`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.

## Function `lantern_api_pending_item`

Writes a pending item.

### Signature

```
lantern_api_pending_item(item, kind)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `item` | input | the item's SSZ bytes |
| `kind` | input | u64 in a register: a kind of lantern_node_pending |

### Function does

- Writes the JSON of a PendingDeposit, a PendingPartialWithdrawal or a PendingConsolidation from its SSZ fields.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_pending_item`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.
- Argument order: `item`, `kind`.

## Function `lantern_api_pending_json`

Writes the items of a pending stream.

### Signature

```
lantern_api_pending_json(state) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |

### Returns

- 1: the answer is whole.
- 0: more is to come.
- 2: the state has no such list.

### Function does

- Writes the items from the index at `NodeEvent_api` + 16 of the event, with , between; then `]}` once they are all written (node.md, NODE_WORK_API_CHUNK).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 64 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_pending_json`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the stream registers of lantern_api_stream_json.
- It takes the state in x20, rdi, s3.
- Argument order: `state`.

## Function `lantern_api_pool_json`

Writes a pool stream.

### Signature

```
lantern_api_pool_json(bytes) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | the pool entry's SSZ bytes, or 0 |

### Returns

- 1: the answer is whole.
- 0: more is to come.
- 2: the bytes are no encoding.

### Function does

- As lantern_api_stream_json: the JSON of the pool entry from the cursor at `NodeEvent_api` + 16, by lantern_node_json of the fork in `sent` and the kind of the GET, after , when `API_STREAM_ITEMS` is set and the cursor is at its start.
- Once whole: `API_STREAM_ITEMS` and `API_STREAM_ITEM_DONE` in the event.
- With `bytes` 0: `]}`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_pool_json`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the stream registers of lantern_api_stream_json.
- It takes the bytes in x21, rdi, s3.
- Argument order: `bytes`.

## Function `lantern_api_put`

Writes bytes into the response.

### Signature

```
lantern_api_put(bytes, length)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | `length` bytes |
| `length` | input | u64 in a register |

### Function does

- The bytes join the response; the first pass only counts them.
- Past the end of the room, the room ran out.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_put`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- The writer, on ARM64, x86-64, RISC-V: the cursor in x24, r12, s6; the pass (0 counts the bytes, 1 writes them) in x25, r13, s7; the end of the room in x26, r14, s8; 1 when the room ran out in x27, r15, s9; the ApiView in x22, rbp, s4.
- The writer's functions keep its registers; only lantern_api_respond calls them.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1, x9, x10; rax, rcx, rsi, rdi; a0, a1, t0, t1.
- Argument order: `bytes`, `length`.

## Function `lantern_api_qdec`

Writes a number in decimal, in quotes.

### Signature

```
lantern_api_qdec(value)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `value` | input | u64 in a register |

### Function does

- Writes the decimal digits of `value` in quotes.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_qdec`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.
- Argument order: `value`.

## Function `lantern_api_qdec256`

Writes a Uint256 in decimal, in quotes.

### Signature

```
lantern_api_qdec256(value)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `value` | input | 32 bytes: a little-endian Uint256 |

### Function does

- Writes the decimal digits of the number in quotes.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_qdec256`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.
- Argument order: `value`.

## Function `lantern_api_qhex`

Writes bytes as quoted hex.

### Signature

```
lantern_api_qhex(bytes, length)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | `length` bytes |
| `length` | input | u64 in a register |

### Function does

- Writes `"0x`, the lower case hex of the bytes, and `"`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_qhex`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.
- Argument order: `bytes`, `length`.

## Function `lantern_api_qint`

Writes a signed number in decimal, in quotes.

### Signature

```
lantern_api_qint(value)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `value` | input | i64 in a register (two's complement) |

### Function does

- Writes the value in decimal in quotes, with - before a value below 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_qint`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.
- Argument order: `value`.

## Function `lantern_api_respond`

Writes an HTTP response.

### Signature

```
lantern_api_respond(view, out, status, body, flags) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `view` | input | `ApiView` |
| `out` | output | ByteList, its count set |
| `status` | input | u64 in a register: the HTTP status |
| `body` | input | u64 in a register: 0 none, `API_BODY_ERROR`, or an API_OP_* |
| `flags` | input | u64 in a register: `API_R_CLOSE`, `API_R_KEEP`, `API_R_NO_REASON`, and the allow bits from bit 8 |

### Returns

- `LANTERN_OK`: `out` holds the response.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has too little room.

### Function does

- Writes the status line of the status, then its fields, then the body of the kind from the view (lantern_node_api_event).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_respond`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: the registers of the lantern_api_put writer.
- Argument order: `view`, `out`, `status`, `body`, `flags`.

## Function `lantern_api_reward_fields`

Writes the fields of an attestation reward item.

### Signature

```
lantern_api_reward_fields(item)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `item` | input | a 48-byte item of lantern_node_attestation_rewards |

### Function does

- Writes `,"head":…,"target":…,"source":…,"inactivity":…}`, with `,"inclusion_delay":…` before inactivity when the fork of the stream's entry is phase0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_reward_fields`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put; the NodeApi entry in x22, rbx, s4.
- Argument order: `item`.

## Function `lantern_api_rewards_body`

Writes the body of getBlockRewards.

### Signature

```
lantern_api_rewards_body()
```

### Function does

- Writes `{"execution_optimistic":…,"finalized":…,"data":{"proposer_index":…,"total":…,"attestations":…,"sync_aggregate":…,"proposer_slashings":…,"attester_slashings":…}}` of the 48 bytes of lantern_node_block_rewards at `ApiView_live_out` of the view.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_rewards_body`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.

## Function `lantern_api_rewards_json`

Writes the items of getAttestationsRewards.

### Signature

```
lantern_api_rewards_json(state) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |

### Returns

- 1: the answer is whole.
- 0: more is to come.
- 2: the state is one the functions refuse.
- 3: the scratch is too small.

### Function does

- Writes the items from the cursor at `NodeEvent_api` + 16 of the event, then `]}}` once all are written.
- The cursor: +0 the next step or validator, +16 the bitmap of the ids, +32 the items written, +48 the part (0 no totals yet, 1 the ideal items, 2 the validators' items), +56 the totals, +592 the chunk's scratch.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_rewards_json`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the stream registers of lantern_api_stream_json.
- It takes the state in x20, rdi, s3.
- Argument order: `state`.

## Function `lantern_api_sidecar_body`

The body of a sidecar stream.

### Signature

```
lantern_api_sidecar_body(bytes) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | the sidecar's SSZ bytes, or 0 |

### Returns

- 1: the answer is whole.
- 0: more is to come.
- 2: the bytes are no encoding.

### Function does

- As lantern_api_stream_json (node.md, NODE_WORK_API_CHUNK, the sidecar streams).
- As JSON: the JSON of the sidecar from the cursor at `NodeEvent_api` + 16 by lantern_node_json of the entry's fork and the operation's kind, after , when `API_STREAM_ITEMS` is set and the cursor is at its start.
- As SSZ: its bytes from `sent` of the event, as many as fit.
- At the sidecar's end: `API_STREAM_ITEMS` and `API_STREAM_ITEM_DONE` in the event.
- With `bytes` 0: `]}` as JSON, nothing as SSZ.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_sidecar_body`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the stream registers of lantern_api_stream_json.
- It takes the bytes in x21, rdi, s3.
- Argument order: `bytes`.

## Function `lantern_api_sidecar_event_text`

The text of an event of a sidecar topic.

### Signature

```
lantern_api_sidecar_event_text(out, topic, ssz, scratch) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `out` | output | ByteList, its count set |
| `topic` | input | u64 in a register |
| `ssz` | input | ByteList: the sidecar's SSZ bytes |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |

### Returns

- `LANTERN_OK`: `out` holds the event's text.
- `LANTERN_BUFFER_TOO_SMALL`: `out` is short.
- `LANTERN_INVALID_ENCODING`: the bytes are no sidecar.

### Function does

- Writes `event: <topic>` LF `data: {"block_root":…,"index":…,"slot":…,…}` LF LF from the sidecar's bytes (beacon-APIs eventstream).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 240 bytes on x86-64 (return address included), 240 bytes on ARM64, 240 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_sidecar_event_text`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It takes the fork in x15, r10, t6.
- Registers it changes, on ARM64, x86-64, RISC-V: the registers of the lantern_api_put writer.
- Argument order: `out`, `topic`, `ssz`, `scratch`.

## Function `lantern_api_spec`

Writes the body of getSpec.

### Signature

```
lantern_api_spec()
```

### Function does

- Writes each key of `API_SPEC_KEYS` with the config of the view (lantern_node_api_event).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 80 bytes on x86-64 (return address included), 80 bytes on ARM64, 80 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_spec`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.

## Function `lantern_api_sse_head`

The head of an eventstream answer.

### Signature

```
lantern_api_sse_head(out, flags) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `out` | output | ByteList, its count set |
| `flags` | input | u64 in a register: the answer flags |

### Returns

- `LANTERN_OK`: `out` holds the head.
- `LANTERN_BUFFER_TOO_SMALL`: `out` is short.

### Function does

- Writes the head of an eventstream answer (lantern_node_api_event).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_sse_head`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: the registers of the lantern_api_put writer.
- Argument order: `out`, `flags`.

## Function `lantern_api_state_read_body`

Writes the bodies of getStateRandao, getEpochSyncCommittees and getProposerLookahead.

### Signature

```
lantern_api_state_read_body(locals, kind)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `locals` | input | the locals of lantern_api_body, the flags at 8 |
| `kind` | input | u64 in a register: the body kind |

### Function does

- Writes the body of the kind from the view, as lantern_api_body.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_state_read_body`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.
- On ARM64 it takes the kind in x28.
- Argument order: `locals`, `kind`.

## Function `lantern_api_stream_head`

Writes the head of a streamed answer.

### Signature

```
lantern_api_stream_head(length)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `length` | input | u64 in a register: the Content-Length, or 2^64 - 1 |

### Function does

- Writes the head for the flags at `NodeEvent_api` + 8 of the event and the fork of the entry (lantern_node_api_event).
- With a length, Content-Length; with 2^64 - 1, Transfer-Encoding: chunked when `API_STREAM_CHUNKED` is set, else neither.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_stream_head`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the stream registers of lantern_api_stream_json.
- Argument order: `length`.

## Function `lantern_api_stream_json`

Writes the JSON of a stream's SSZ bytes.

### Signature

```
lantern_api_stream_json(bytes) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | the entry's SSZ bytes |

### Returns

- 1: the answer is whole.
- 0: more is to come.
- 2: the bytes are no encoding.

### Function does

- Writes the JSON of the bytes from the cursor at `NodeEvent_api` + 16 of the event, up to the end of the room less a byte, through the event's ByteList at `NodeEvent_api_bytes`; then `}` once it is whole.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_stream_json`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It takes the bytes in x21, rdi, s3.
- The stream registers, on ARM64, x86-64, RISC-V: the NodeApi entry in x22, rbx, s4; the event in x23, rbp, s5; with the writer of lantern_api_put.
- On ARM64 and RISC-V the chunk's bytes start at x28 and s10.
- Argument order: `bytes`.

## Function `lantern_api_sync_duties_body`

Writes the body of getSyncCommitteeDuties.

### Signature

```
lantern_api_sync_duties_body()
```

### Function does

- Writes `{"execution_optimistic":…,"data":[{"pubkey":…,"validator_index":…,"validator_sync_committee_indices":[…]},…]}` of the ValidatorRef items at `ApiView_sd_ids` of the view.
- Each by its places in the committee at `ApiView_sync_out`; the pubkeys those of the state at `ApiView_val_state`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 64 bytes on x86-64 (return address included), 64 bytes on ARM64, 64 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_sync_duties_body`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.

## Function `lantern_api_sync_rewards_body`

Writes the body of getSyncCommitteeRewards.

### Signature

```
lantern_api_sync_rewards_body()
```

### Function does

- Writes `{"execution_optimistic":…,"finalized":…,"data":[{"validator_index":…,"reward":…},…]}` of the items of lantern_node_sync_rewards at `ApiView_live_out` of the view.
- With ValidatorRef items at `ApiView_sd_ids`: only those of the validators of `ApiView_val_state` that one names.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_sync_rewards_body`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.

## Function `lantern_api_text`

Writes a text in quotes.

### Signature

```
lantern_api_text(text)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `text` | input | its length, then its bytes |

### Function does

- Writes the text in quotes.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_text`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.
- Argument order: `text`.

## Function `lantern_api_validator_item`

Writes the item of a validator.

### Signature

```
lantern_api_validator_item(state, index, kind)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `index` | input | u64 in a register |
| `kind` | input | u64 in a register: 0 getStateValidators, 1 the balances, 2 the identities, 3 their SSZ (64 bytes) |

### Function does

- Writes the item of the validator of the kind.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_validator_item`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.
- Argument order: `state`, `index`, `kind`.

## Function `lantern_api_validator_status`

The API status of a validator.

### Signature

```
lantern_api_validator_status(validator, epoch) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `validator` | input | the SSZ bytes of a `Validator` |
| `epoch` | input | u64 in a register |

### Function does

- Returns the API_STATUS_* of the validator at the epoch.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_validator_status`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x12; rax, rcx, rdx; a0, t0 to t3.
- Argument order: `validator`, `epoch`.

## Function `lantern_api_validators_json`

Writes the items of a validator stream.

### Signature

```
lantern_api_validators_json(state) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |

### Returns

- 1: the answer is whole.
- 0: more is to come.

### Function does

- Writes the items from the cursor at `NodeEvent_api` + 16 of the event; then `]}` for JSON once they are all written.
- The cursor: +0 the next index, +8 the status bits, +16 the bitmap, +24 the epoch, +32 the items written.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_validators_json`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the stream registers of lantern_api_stream_json.
- It takes the state in x20, rdi, s3.
- Argument order: `state`.

## Function `lantern_api_view_finalized`

Sets head_finalized of an ApiView.

### Signature

```
lantern_api_view_finalized(view)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `view` | state | `ApiView` |

### Function does

- `head_finalized` takes 1 when the view's head_root is the root of the store's finalized checkpoint, else 0.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_view_finalized`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the store in x20, rbp, s2.
- Registers it changes, on ARM64, x86-64, RISC-V: x9 to x16; rax, rsi, xmm0 to xmm2; a6, a7, t0 to t2.
- Argument order: `view`.

## Function `lantern_api_wei`

Writes a Gwei amount in Wei.

### Signature

```
lantern_api_wei(gwei)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `gwei` | input | u64 in a register |

### Function does

- Writes the amount in Wei, in decimal.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_api_wei`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the writer of lantern_api_put.
- Argument order: `gwei`.

## Function `lantern_copy_root`

Copies 32 bytes.

### Signature

```
lantern_copy_root(out, root)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `out` | output | Bytes32 |
| `root` | input | Bytes32 |

### Function does

- Copies the 32 bytes.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 0 bytes on ARM64.

### ABI

- Role: L0.
- Symbol: `lantern_copy_root`, local to its object. Only ARM64 have it.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It is on ARM64.
- Registers it changes, on ARM64: x16, x17.
- Argument order: `out`, `root`.

## Function `lantern_node_api_advance`

Brings the state of an ApiView to its slot.

### Signature

```
lantern_node_api_advance(view)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `view` | state | `ApiView` |

### Function does

- When head_slot is past look_state_slot: a STATE_COPY of look_state, the copy across the fork boundaries to head_slot, and a SLOTS work of it to head_slot when it is below it (node.md, NODE_EV_API).
- look_state is the copy, look_copy 1.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_advance`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Registers it reads, on ARM64, x86-64, RISC-V: the actions in x24, r15, s6.
- Argument order: `view`.

## Function `lantern_node_api_aggregate`

The SSZ bytes of the aggregate of a getAggregatedAttestationV2 stream.

### Signature

```
lantern_node_api_aggregate(out) -> (status, length)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `out` | output | the SSZ bytes of an `Attestation` |

### Returns

- 0: `out` holds the bytes; the second value is their count.
- 1: a committee index not below `MAX_COMMITTEES_PER_SLOT`.

### Function does

- Writes the aggregate in the cursor at `NodeEvent_api` + 16 of the event as the Attestation of the fork of the entry (node.md, getAggregatedAttestationV2): aggregation_bits of the cursor's length with its bits, data, signature.
- From electra, committee_bits with the bit of `filter_index`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_aggregate`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the stream registers of lantern_api_stream_json.
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Argument order: `out`.

## Function `lantern_node_api_below`

The block of the chain at or below a slot.

### Signature

```
lantern_node_api_below(slot) -> (index, entry)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `slot` | input | u64 in a register |

### Function does

- Returns the NodeBlock index and entry of the block of the chain at or below the slot.
- Returns 2^64 - 1 and the lowest block of the chain the node keeps (0 with no head) when it is above the slot.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 48 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_below`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Argument order: `slot`.

## Function `lantern_node_api_blob_stream`

Starts the blob stream of a block.

### Signature

```
lantern_node_api_blob_stream(connection, route, flags, view) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `connection` | input | u64 in a register |
| `route` | input | [`ApiRoute`](#type-apiroute) |
| `flags` | input | u64 in a register: the answer flags |
| `view` | input | `ApiView` |

### Returns

- 0: the stream starts.
- 404: a fulu block of which the node holds a column sidecar but not one of each of the first `NUMBER_OF_COLUMNS` / 2 columns.

### Function does

- Starts the blob stream of the block of the view (node.md, NODE_EV_API, the blob stream).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_blob_stream`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Registers it reads, on ARM64, x86-64, RISC-V: the actions in x24, r15, s6.
- Argument order: `connection`, `route`, `flags`, `view`.

## Function `lantern_node_api_block`

Finds the block of a block_id.

### Signature

```
lantern_node_api_block(route, view) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `route` | input | [`ApiRoute`](#type-apiroute) |
| `view` | output | `ApiView` |

### Returns

- 0: the view holds the block.
- 404: the node keeps no such block.

### Function does

- Writes the block of the route's block_id into the view (lantern_node_api_event): head_root, head_slot, canonical, head_finalized, is_optimistic, look_index, look_data.
- For a block the node keeps, also look_state and look_state_slot.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_block`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Registers it reads, on ARM64, x86-64, RISC-V: the store in x20, rbp, s2.
- Argument order: `route`, `view`.

## Function `lantern_node_api_block_event`

Queues the block event of a block.

### Signature

```
lantern_node_api_block_event(entry)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | input | the `NodeBlock` entry |

### Function does

- Queues the block event of its slot and root, execution_optimistic from its payload status (node.md, The events).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_block_event`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Registers it reads, on ARM64, x86-64, RISC-V: the actions in x24, r15, s6.
- Argument order: `entry`.

## Function `lantern_node_api_check`

Checks a NODE_EV_API or NODE_EV_API_IDENTITY event.

### Signature

```
lantern_node_api_check(event, size) -> (flag, scratch)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | `NodeEvent` |
| `size` | input | u64 in a register |

### Function does

- Returns 0 when the event, its ByteList at 24 inside it, keeps its rules (node.md, NodeEvent), else 1.
- Also returns the scratch it needs.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_check`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1, x9 to x15; rax, rcx, rdx, rsi, r8 to r11; a0, a1, t0 to t6.
- Argument order: `event`, `size`.

## Function `lantern_node_api_chunk_done`

Takes the end of a NODE_WORK_API_CHUNK.

### Signature

```
lantern_node_api_chunk_done(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | `NodeEvent` of kind `NODE_EV_WORK_DONE` |

### Function does

- Sends the chunk, then queues the next chunk or ends the stream (node.md, lantern_node_step).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_chunk_done`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Registers it reads, on ARM64, x86-64, RISC-V: the actions in x24, r15, s6.
- Argument order: `event`.

## Function `lantern_node_api_chunk_run`

The NODE_WORK_API_CHUNK work of lantern_node_run.

### Signature

```
lantern_node_api_chunk_run(node, work, data, scratch, event, room, state_a) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `node` | input | the node |
| `work` | input | `NodeAction` of the work |
| `data` | input | the SSZ bytes, or for a validator stream the ids |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `event` | output | `NodeEvent` |
| `room` | input | u64 in a register: the bytes of the event's buffer |
| `state_a` | input | `BeaconState`, for a validator stream |

### Returns

- As lantern_node_run.

### Function does

- Writes the next chunk of the NodeApi entry at the work's `arg` at `NodeEvent_api` of the event (node.md, NODE_WORK_API_CHUNK).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 176 bytes on x86-64 (return address included), 160 bytes on ARM64, 176 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_chunk_run`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `node`, `work`, `data`, `scratch`, `event`, `room`, `state_a`.

## Function `lantern_node_api_chunk_work`

Queues a NODE_WORK_API_CHUNK of a NodeApi entry.

### Signature

```
lantern_node_api_chunk_work(index, entry)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `index` | input | u64 in a register |
| `entry` | state | the `NodeApi` entry |

### Function does

- Queues the work; the entry takes `API_STREAM_BUSY`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 16 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_chunk_work`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Registers it reads, on ARM64, x86-64, RISC-V: the actions in x24, r15, s6.
- Argument order: `index`, `entry`.

## Function `lantern_node_api_closed`

Takes a NODE_EV_API_CLOSED event.

### Signature

```
lantern_node_api_closed(connection)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `connection` | input | u64 in a register |

### Function does

- The connection's stream ends; with a chunk or work queued it takes `API_STREAM_GONE`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_closed`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Registers it reads, on ARM64, x86-64, RISC-V: the actions in x24, r15, s6.
- Argument order: `connection`.

## Function `lantern_node_api_committees_check`

The epoch of a getEpochCommittees.

### Signature

```
lantern_node_api_committees_check(route, view) -> epoch
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `route` | input | [`ApiRoute`](#type-apiroute) |
| `view` | input | `ApiView` |

### Function does

- Returns the epoch of the route for the state of the view (lantern_node_api_event).
- Returns 2^64 - 1 for 400: an epoch above the state's + 1, one whose seed's RANDAO mix the state no longer holds, or a slot of another epoch.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_committees_check`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x13; rax, rcx, rdx, r8, r9; a0, t0 to t4.
- Argument order: `route`, `view`.

## Function `lantern_node_api_committees_cursor`

Sets the cursor of a getEpochCommittees stream.

### Signature

```
lantern_node_api_committees_cursor(entry, route, epoch)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the `NodeApi` entry |
| `route` | input | [`ApiRoute`](#type-apiroute) |
| `epoch` | input | u64 in a register |

### Function does

- Writes the first slot at 0, the first index at 8, the epoch at 24, and the slot and the index asked at 40 and 48 (2^64 - 1 for none) (node.md, NODE_EV_API).

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_committees_cursor`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x9 to x12; rax, rcx; t0 to t3.
- Argument order: `entry`, `route`, `epoch`.

## Function `lantern_node_api_committees_prep`

Starts a chunk of a getEpochCommittees stream.

### Signature

```
lantern_node_api_committees_prep(scratch, state, node) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `state` | input | `BeaconState` |
| `node` | input | the node |

### Returns

- 0: the cursor is ready.
- 400: an index asked at or past the count, in the first chunk.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has no room for a committee and lantern_get_beacon_committee.
- Else the status of the count.

### Function does

- At the cursor at `NodeEvent_api` + 16 of the event: +56 get_committee_count_per_slot of the state at the epoch at +24; +72 the scratch and +80 the node's CommitteeCache, for lantern_api_committees_json (node.md, NODE_WORK_API_CHUNK).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 32 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_committees_prep`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the stream registers of lantern_api_stream_json.
- On ARM64 it takes the state in x20 and the node in x19.
- Argument order: `scratch`, `state`, `node`.

## Function `lantern_node_api_contribution`

The SSZ bytes of the contribution of a produceSyncCommitteeContribution stream.

### Signature

```
lantern_node_api_contribution(out) -> (status, length)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `out` | output | the SSZ bytes of a `SyncCommitteeContribution` |

### Returns

- 0: `out` holds the bytes; the second value is their count.

### Function does

- Writes the contribution in the cursor at `NodeEvent_api` + 16 of the event (node.md, produceSyncCommitteeContribution): slot `filter_slot`, the beacon_block_root, subcommittee_index `filter_index` of the entry, the bits, the signature.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_contribution`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the stream registers of lantern_api_stream_json.
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Argument order: `out`.

## Function `lantern_node_api_db_ref`

The NODE_DB_REF of a block root in the Db.

### Signature

```
lantern_node_api_db_ref(root) -> ref
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `root` | input | Bytes32 |

### Function does

- Returns the `NODE_DB_REF` of the Db's record of the block of the root, or 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_db_ref`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Argument order: `root`.

## Function `lantern_node_api_done`

Takes the end of a NODE_WORK_API_ENCODE.

### Signature

```
lantern_node_api_done(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | `NodeEvent` of kind `NODE_EV_WORK_DONE` |

### Function does

- Sends its response to the connection, or the error 500 (node.md, lantern_node_step).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_done`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Registers it reads, on ARM64, x86-64, RISC-V: the actions in x24, r15, s6.
- Argument order: `event`.

## Function `lantern_node_api_encode`

Queues the NODE_WORK_API_ENCODE of an operation.

### Signature

```
lantern_node_api_encode(op, connection, flags, view) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `op` | input | u64 in a register |
| `connection` | input | u64 in a register |
| `flags` | input | u64 in a register: the answer flags |
| `view` | input | `ApiView`: the lookup |

### Returns

- 0: the work is queued.
- 404: a header with neither bytes nor a post-state.

### Function does

- Queues the work from the lookup in the view (node.md, NODE_EV_API).
- Then a STATE_FREE of the state when it is a copy.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_encode`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Registers it reads, on ARM64, x86-64, RISC-V: the actions in x24, r15, s6.
- Argument order: `op`, `connection`, `flags`, `view`.

## Function `lantern_node_api_end`

Ends the stream of a NodeApi entry.

### Signature

```
lantern_node_api_end(entry)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the `NodeApi` entry |

### Function does

- The entry is free; the api part's count drops past the free entries at its end.
- With `API_STREAM_OWN`: a BYTES_FREE of its data, which lantern_node_ids gives to another entry that sends the same bytes.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 48 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_end`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Registers it reads, on ARM64, x86-64, RISC-V: the actions in x24, r15, s6.
- Argument order: `entry`.

## Function `lantern_node_api_event`

Answers a NODE_EV_API event.

### Signature

```
lantern_node_api_event(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | `NodeEvent` of kind `NODE_EV_API` |

### Function does

- Answers the request by these rules (node.md, `NODE_EV_API`):
  - The response in one piece:
    - The status line: `HTTP/1.1`, a space, the code in decimal, a space, its reason phrase, CRLF.
    - `Content-Type: application/json` CRLF, when it has a body.
    - `Content-Length: ` and the body's bytes in decimal, CRLF; `0` with no body.
    - With 405: `Allow: ` and the methods of `allow`, `GET`, `POST` or `GET, POST`, CRLF.
    - `Connection: close` CRLF when the connection closes after it; `Connection: keep-alive` CRLF when an HTTP/1.0 request keeps it open.
    - CRLF, then the body.
  - The connection closes after the response when the request has `close`, or when lantern_http_request found it faulty.
  - Reason phrases: 200 `OK`, 202 `Accepted`, 206 `Partial Content`, 400 `Bad Request`, 404 `Not Found`, 405 `Method Not Allowed`, 406 `Not Acceptable`, 413 `Content Too Large`, 414 `URI Too Long`, 415 `Unsupported Media Type`, 431 `Request Header Fields Too Large`, 500 `Internal Server Error`, 501 `Not Implemented`, 503 `Service Unavailable`, 505 `HTTP Version Not Supported`.
  - The code of getHealth's `syncing_status` has none: the line ends with the space after the code.
  - An error is a status of 400 or more.
  - Its body is `{"code":<code>,"message":"<message>"}`, with the code in decimal and the message of its status: 400 `BAD_REQUEST`, 404 `NOT_FOUND`, 405 `METHOD_NOT_ALLOWED`, 406 `NOT_ACCEPTABLE`, 413 `CONTENT_TOO_LARGE`, 414 `URI_TOO_LONG`, 415 `UNSUPPORTED_MEDIA_TYPE`, 431 `REQUEST_HEADER_FIELDS_TOO_LARGE`, 500 `INTERNAL_SERVER_ERROR`, 501 `NOT_IMPLEMENTED`, 503 `SERVICE_UNAVAILABLE`, 505 `HTTP_VERSION_NOT_SUPPORTED`.
  - JSON has no white space and the fields in the order below.
  - A number is a decimal string, a byte string `0x` and lower case hex, a text its bytes in quotes, a flag `true` or `false`.
  - The values:
    - `genesis_time`: the store's `genesis_time_ms` / 1000.
    - `genesis_validators_root`: the node's.
    - `genesis_fork_version`: `GENESIS_FORK_VERSION` of the node's config.
    - The head: the `NodeBlock` of `head_root`.
    - `head_slot`: its slot.
    - `is_optimistic`: its `payload_status` is `PAYLOAD_STATUS_NOT_VALIDATED`.
    - `current_slot`: the store's slot.
    - `is_syncing`: `NODE_FLAG_SYNCING`.
    - `el_offline`: `NODE_FLAG_EL_OFFLINE`.
    - `connected`: the `NodePeer` entries.
    - The MetaData: `seq_number` the node's `metadata_seq`; `attnets` the 8 bytes of the node's `attnets` (bit i of byte i / 8 for subnet i); from altair `syncnets` 1 zero byte; from fulu `custody_group_count` the node's `custody_count` (node.md, validator custody).
    - The fork is that of the store's slot.
    - The texts: the node's `api_identity`, from the last `NODE_EV_API_IDENTITY`; each is empty before one.
  - getHealth: no body; 200; 206 when `is_syncing`, `is_optimistic` or `el_offline`; and then, with `syncing_status`, that code in place of 206.
  - getNetworkIdentity: `{"data":{"peer_id":…,"enr":…,"p2p_addresses":[…],"discovery_addresses":[…],"metadata":{"seq_number":…,"attnets":…,"syncnets":…,"custody_group_count":…}}}`.
  - Each address list holds its text, or nothing when the text is empty.
  - getNodeVersion: `{"data":{"version":…}}`.
  - getSyncingStatus: `{"data":{"head_slot":…,"sync_distance":…,"is_syncing":…,"is_optimistic":…,"el_offline":…}}`; `sync_distance` is `current_slot` minus `head_slot`, or 0 when it is below.
  - getPeerCount: `{"data":{"disconnected":"0","connecting":"0","connected":…,"disconnecting":"0"}}`.
  - getPeers: `{"data":[<peer>,…],"meta":{"count":…}}`, each `NodePeer` in order whose state, `connected`, is in the `state` set and whose direction is in the `direction` set, of the sets given; `count` the items, a JSON number.
  - getPeer: the `NodePeer` whose `peer_id` text is the route's `peer_id`: `{"data":<peer>}`; with none, 404.
  - A peer: `{"peer_id":…,"enr":null,"last_seen_p2p_address":…,"state":"connected","direction":…}`.
    - `peer_id`: base58btc of its peer ID.
    - `last_seen_p2p_address`: the multiaddr of its connection's address: `/ip4/` and the 4 bytes in decimal with `.` between, or `/ip6/` and the 8 groups of 16 bits in lower case hex with no leading zeros and `:` between; then `/tcp/` and the port for TCP, or `/udp/`, the port and `/quic-v1` for QUIC; then `/p2p/` and its `peer_id`.
    - `direction`: `inbound` or `outbound`.
  - getGenesis: `{"data":{"genesis_time":…,"genesis_validators_root":…,"genesis_fork_version":…}}`.
  - getDebugChainHeadsV2: `{"data":[{"root":…,"slot":…,"execution_optimistic":…},…]}`, the leaves of the fork choice tree: each node of the store's `blocks`, in their order, that no node names as its `parent`.
  - A node whose payload is `INVALIDATED`, and each node below it, is out of the tree (fork-choice.md, optimistic sync: removed from fork choice).
  - `execution_optimistic`: its `payload_status` is `NOT_VALIDATED`.
  - getDebugForkChoice: `{"justified_checkpoint":…,"finalized_checkpoint":…,"fork_choice_nodes":[…]}`, the store's checkpoints and each node of its `blocks`, in their order: `{"slot":…,"block_root":…,"parent_root":…,"justified_epoch":…,"finalized_epoch":…,"weight":…,"validity":…,"execution_block_hash":…}`.
    - `justified_epoch` and `finalized_epoch`: the epochs of `current_justified_checkpoint` and `finalized_checkpoint` of the block's post-state (`BlockNode.justified_checkpoint`, `BlockNode.finalized_epoch`).
    - `weight`: get_weight of the node (fork-choice.md, lantern_get_weight), from lantern_node_weights.
    - `validity`: `valid`, `invalid` or `optimistic` for a `payload_status` of `VALID`, `INVALIDATED` or `NOT_VALIDATED`.
    - `execution_block_hash`: `BlockNode.block_hash`, zero before bellatrix.
    - The error 500 when lantern_node_weights fails, as when the store's balances are not those of its justified checkpoint.
  - getSpec: `{"data":{…}}`, the keys and values of the node's config, the preset and the spec's constants:
    - Each key of `CONFIG_KEYS` and `BLOB_SCHEDULE`, in the order of the pinned configs/<preset>.yaml, with the node's values; and `SECONDS_PER_SLOT`, `SLOT_DURATION_MS` / 1000, right before `SLOT_DURATION_MS`, the key clients and tools read from configs before the spec gave the slot in milliseconds.
    - Then each key of the pinned presets/<preset>/phase0.yaml to fulu.yaml, in file order.
    - Then each row of the Constants tables of beacon-chain.md of phase0 to fulu, in table order, but `PARTICIPATION_FLAG_WEIGHTS`, the one list: the validator client of Nimbus v26.10.2 reads each value but `BLOB_SCHEDULE` and `GAS_LIMIT_SCHEDULE` as a string and stops at a list, and the beacon nodes of Nimbus and Teku leave it out. beacon-APIs v4.0.0 says the constants SHOULD be there.
    - Values: a number in quotes, decimal; a Version, a DomainType, a Hash32, an Address and other byte strings `0x` and lower case hex; a text in quotes; `BLOB_SCHEDULE` `[{"EPOCH":…,"MAX_BLOBS_PER_BLOCK":…},…]` in the config's order.
  - getForkSchedule: `{"data":[{"previous_version":…,"current_version":…,"epoch":…},…]}`: phase0, with `GENESIS_FORK_VERSION` as both versions and epoch 0; then each fork from altair to fulu whose epoch in the node's config is below 2^64 - 1, with the version of the fork before it in the list as `previous_version`.
  - getDepositContract: `{"data":{"chain_id":…,"address":…}}`: `DEPOSIT_CHAIN_ID` and `DEPOSIT_CONTRACT_ADDRESS` of the node's config.
  - The block of a `block_id`, on the chain: the head's `NodeBlock` and its ancestors by `parent_root` among the node's imported blocks, then, below the lowest of them, the blocks of the `Db`:
    - `head`: the head.
    - `finalized`: the block of the store's finalized checkpoint root.
    - `genesis`: as the slot 0.
    - A slot: the block of that slot on the chain; none for a slot with no block on the chain, or past the head's slot.
    - A root: the node's imported block of that root, on the chain or not; else the `Db`'s block of that root.
    - None: 404.
    - `canonical`: the block is on the chain.
    - `finalized`: on the chain, at most at the slot of the block of the store's finalized checkpoint root.
    - `execution_optimistic`: its `payload_status` is `PAYLOAD_STATUS_NOT_VALIDATED`; false for a block of the `Db`.
    - Its bytes: those of its `NodeBlock`, or its `Db` record; the anchor's block has none until the backfill takes it.
  - The state of a `state_id`: a state the node keeps, at a slot:
    - `head`: the head's post-state, at the head's slot.
    - `genesis`: as the slot 0.
    - `finalized` and `justified`: the store's finalized checkpoint, or its current justified checkpoint: the state of its `NodeCheckpoint` when the node keeps one, else the post-state of the block of its root, at the first slot of its epoch.
    - A slot: the post-state of the block of the chain at or below that slot, at that slot; none past the store's slot.
    - A root: the slot of the chain whose state has that root: the head's post-state's own hash_tree_root, or an entry of its `state_roots`, for the slots from the head's slot - `SLOTS_PER_HISTORICAL_ROOT` to the head's; then as that slot.
    - A root of none of them: 404.
    - A block above F's slot with no post-state gets it again first (node.md, the rebuild).
    - A block at or below F's slot with none: for a `state_id` of a slot of a getState operation, and for the state of getProposerDuties and getAttesterDuties, the replay (node.md) from the nearest of the base state and the `Db`'s state records (`--archive`, app.md), for a block at or above `base_slot` or at or above the lowest state record; else 404.
    - None: 404.
    - At a slot past the post-state's: a copy of it, across the fork boundaries to that slot (node.md, the crossing), then process_slots to that slot.
    - `finalized`: its slot is at most the first slot of the epoch of the store's finalized checkpoint.
    - `execution_optimistic`: that of the block of its post-state or checkpoint.
  - getBlockRoot: the block of `block_id`: `{"execution_optimistic":…,"finalized":…,"data":{"root":…}}`.
  - getBlockHeader: the block of `block_id`.
    - The header: lantern_node_block_header of the block's bytes.
    - With none, the `latest_block_header` of its post-state, with the post-state's hash_tree_root as `state_root` when that is zero, and a zero signature; with no post-state either, 404.
    - `{"execution_optimistic":…,"finalized":…,"data":{"root":…,"canonical":…,"header":{"message":{"slot":…,"proposer_index":…,"parent_root":…,"state_root":…,"body_root":…},"signature":…}}}`.
  - getBlockV2: the bytes of the block of `block_id`; with none, 404.
  - getBlockHeaders: `{"execution_optimistic":…,"finalized":…,"data":[…]}`, an item for each block of the query, each the `data` of getBlockHeader of that block, `{"root":…,"canonical":…,"header":…}`, with `,` between.
    - The query: its `slot` and its `parent_root`, of those given; with neither, the head's slot as `slot`.
    - First, with `NODE_FLAG_DB`, the `Db`'s block C of the query, when one is there:
      - With `parent_root` R: R the root of the node's imported block on the chain, or of the `Db`'s block, at slot r; C the block of the first slot above r whose block is in the `Db`, while the slots are below the lowest block of the chain the node keeps; with `slot`, only when C's slot is `slot`.
      - With `slot` alone: the `Db`'s block of `slot`, when `slot` is below the lowest block of the chain the node keeps.
    - Then each of the node's imported blocks, in the order of their `NodeBlock` entries, of the slot `slot` and the `parent_root` `parent_root`, of those given; a block with no bytes and no post-state is left out.
    - `execution_optimistic`: true when an item's block is optimistic; `finalized`: true when the answer has an item and each item's block is finalized; each as getBlockHeader gives them.
    - Streamed, an item a chunk: the items' blocks are each a block's bytes.
  - getBlindedBlock: the block of `block_id` blinded (lantern_node_blinded_block; with none, 404): `Eth-Consensus-Version` and `version` the fork of the block's slot, `{"version":"<fork>","execution_optimistic":…,"finalized":…,"data":<SignedBlindedBeaconBlock>}`, or with an SSZ `response` its SSZ bytes.
  - From bellatrix the `SignedBlindedBeaconBlock` of the fork (include/types.inc), whose body has the `ExecutionPayloadHeader` of the block's payload in its place; before bellatrix the block itself, as the spec's `Phase0.SignedBeaconBlock` and `Altair.SignedBeaconBlock` answers.
  - Streamed, as getBlockV2.
  - getBlockAttestationsV2: the `attestations` of the body of the block of `block_id` (with none, 404): `Eth-Consensus-Version` and `version` the fork of the block's slot, `{"version":"<fork>","execution_optimistic":…,"finalized":…,"data":[…]}`, the JSON of the fork's `Attestations` list (include/descriptors.inc).
  - Streamed, as getBlockV2.
  - JSON only: the spec gives no SSZ answer.
  - getStateRoot: the hash_tree_root of the state of `state_id`: `{"execution_optimistic":…,"finalized":…,"data":{"root":…}}`.
  - getStateFork: the `fork` of the state of `state_id`: `{"execution_optimistic":…,"finalized":…,"data":{"previous_version":…,"current_version":…,"epoch":…}}`.
  - getStateFinalityCheckpoints: lantern_node_state_checkpoints of the state of `state_id`: `{"execution_optimistic":…,"finalized":…,"data":{"previous_justified":{"epoch":…,"root":…},"current_justified":{…},"finalized":{…}}}`.
  - getStateRandao: lantern_node_randao of the state of `state_id` and `epoch` (the state's epoch when not given): `{"execution_optimistic":…,"finalized":…,"data":{"randao":…}}`.
  - An epoch whose mix the state does not hold: 400.
  - getEpochSyncCommittees: lantern_node_sync_committee of the state of `state_id` and `epoch` (the state's epoch when not given): `{"execution_optimistic":…,"finalized":…,"data":{"validators":[<index>,…],"validator_aggregates":[[<index>,…],…]}}`, the members' indices in order, then SYNC_COMMITTEE_SUBNET_COUNT slices of SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT of them, the subcommittees of the sync_committee_{subnet_id} topics.
  - A state before altair, or an epoch of neither the state's sync committee period nor the next: 400.
  - getPendingDeposits, getPendingPartialWithdrawals and getPendingConsolidations: the state's `pending_deposits`, `pending_partial_withdrawals` or `pending_consolidations` (lantern_node_pending): `Eth-Consensus-Version` and `version` the fork of the state's slot, `{"version":"<fork>","execution_optimistic":…,"finalized":…,"data":[<item>,…]}`; with an SSZ `response`, the SSZ bytes of the list.
  - Streamed, as getStateValidators: a list may hold millions of items.
  - A state before electra: 400 (the spec's description).
  - getProposerLookahead: lantern_node_proposer_lookahead of the state of `state_id`: `Eth-Consensus-Version` and `version` the fork of the state's slot, `{"version":"<fork>","execution_optimistic":…,"finalized":…,"data":[<index>,…]}`; with an SSZ `response`, the SSZ bytes of the `List[ValidatorIndex, (MIN_SEED_LOOKAHEAD + 1) * SLOTS_PER_EPOCH]` of them.
  - A state before fulu: 400 (the spec's description).
  - getStateV2: the SSZ bytes of the state of `state_id`, by lantern_node_state_bytes.
  - The answer of getBlockV2 and getStateV2 is streamed (node.md, `NodeApi`): it goes in chunks, from the SSZ bytes of the block or the state.
    - The fork: that of the slot of the block or the state, by its name: `phase0`, `altair`, `bellatrix`, `capella`, `deneb`, `electra` or `fulu`.
    - After the status line: `Content-Type: application/octet-stream` CRLF for SSZ (`response` `API_TYPE_SSZ`), else `Content-Type: application/json` CRLF; `Eth-Consensus-Version: ` and the fork's name, CRLF; then `Content-Length`, `Transfer-Encoding: chunked` CRLF, or neither, as below; then `Connection` as for a response in one piece; CRLF.
    - SSZ: `Content-Length` of the SSZ bytes; the body is the bytes.
    - JSON: the body is `{"version":"<fork>","execution_optimistic":…,"finalized":…,"data":<data>}`, its data the JSON of the SSZ bytes by lantern_json_encode_ssz with the fork's `SignedBeaconBlock` or `BeaconState`; the values those of the block or the state.
    - JSON whose whole body is in the first chunk: `Content-Length`.
    - Else, over HTTP/1.1, `Transfer-Encoding: chunked`: each chunk of the stream holds the body's bytes in one chunk of RFC 9112 section 7.1, its size in 4 lower case hex digits, CRLF, the bytes, CRLF; the last also `0` CRLF CRLF.
    - Over HTTP/1.0, neither field and `Connection: close`: the connection closes after the body.
  - getBlobSidecars and getDebugDataColumnSidecars: the sidecars of the block of `block_id` (with none, 404) that the node holds, in index order, of the `indices` given (an index below 128; others match none): its `NodeBlob` entries of the block's root in `NODE_BLOB_VALID`, else, with `NODE_FLAG_DB`, the `Db`'s sidecar records of the block's slot.
    - getBlobSidecars: a block whose slot's fork is deneb or electra, its `BlobSidecar` items; another: 400 (the spec's versions: deneb and electra). getDebugDataColumnSidecars: a block whose slot's fork is fulu or later, its `DataColumnSidecar` items; another: 400 (the spec's version: fulu).
    - Streamed, as getStateV2, with `Eth-Consensus-Version`: the JSON body is `{"version":"<fork>","execution_optimistic":…,"finalized":…,"data":[<the items, with , between>]}`, each item the JSON of its SSZ bytes by lantern_json_encode_ssz with the fork's type, the values those of the block; the SSZ body the items' SSZ bytes, one after another.
    - An SSZ body takes `Content-Length` when it is whole in the first chunk, else the coding of a JSON body that is not.
  - The light client data (light-client.md, the `LcStore` of the node, node.md): getLightClientBootstrap, getLightClientUpdatesByRange, getLightClientFinalityUpdate and getLightClientOptimisticUpdate, from altair.
    - getLightClientBootstrap: the `LightClientBootstrap` of `block_root` that the store holds (an epoch boundary block it finalized, or the anchor's block); with none, 404 `{"code":404,"message":"NOT_FOUND"}`. getLightClientFinalityUpdate and getLightClientOptimisticUpdate: the store's latest finality update, or its optimistic update; with none, 404.
    - These three: `Eth-Consensus-Version` the object's fork (that of its `attested_header.beacon.slot`, a bootstrap's `header.beacon.slot`); JSON `{"version":"<fork>","data":<data>}`, the data the JSON of its SSZ bytes by lantern_json_encode_ssz with the fork's type; SSZ its bytes.
    - getLightClientUpdatesByRange: the store's best update of each period from `start_period`, at most the lower of `count` and `MAX_REQUEST_LIGHT_CLIENT_UPDATES`: from the earliest it holds in that range, in period order, up to the first period of none (the spec: at least the earliest known result, in consecutive order).
    - JSON: `[{"version":"<fork>","data":<data>},…]`.
    - SSZ: for each, its `response_chunk_len` (u64 little endian: 4 + its bytes), its context compute_fork_digest of the epoch of its `attested_header.beacon.slot`, then its SSZ bytes.
    - One answer with `Content-Length` and no `Eth-Consensus-Version`: at most `MAX_REQUEST_LIGHT_CLIENT_UPDATES` updates.
  - getBlobs: the blobs of the block of `block_id` (with none, 404), in the order of its `blob_kzg_commitments`; with `versioned_hashes` items, only each blob whose commitment's kzg_commitment_to_versioned_hash (deneb beacon-chain.md) is an item.
    - A block whose slot's fork is before deneb: no blob.
    - Deneb and electra: the `blob` of each sidecar of the block that the node holds, as getBlobSidecars finds them, in index order.
    - Fulu and later: blob i is cell i of each of the columns 0 to `NUMBER_OF_COLUMNS` / 2 - 1, in column order, from the column sidecars the node holds, as getDebugDataColumnSidecars finds them; the count of blobs is the count of the sidecars' `kzg_commitments`.
    - The first half of the cells of an extended blob is the blob. asm-crypto kzg-cells.md: the extended blob holds the values of the blob's polynomial at the 8192-th roots of unity in bit-reversed order, so its first 4096 values are those at the 4096-th roots, in bit-reversed order: the blob's.
    - A fulu block with no column sidecar the node holds: no blob.
    - With some, but not each of the columns 0 to `NUMBER_OF_COLUMNS` / 2 - 1: 404.
    - A supernode (`NODE_FLAG_SUPERNODE`, app.md `--supernode`) holds every column of the blocks it imports, the ones it rebuilds from half of them too (node.md, the reconstruction).
    - Another node holds the columns of max(`SAMPLES_PER_SLOT`, `custody_count`) custody groups (node.md, validator custody).
    - The spec asks for blobs from supernodes only.
    - Streamed, as getStateValidators, with no `Eth-Consensus-Version`: the JSON body is `{"execution_optimistic":…,"finalized":…,"data":[<the blobs, with , between>]}`, each blob `"0x"` and the lower case hex of its bytes in quotes; the SSZ body the blobs back to back, the bytes of `List[Blob, MAX_BLOB_COMMITMENTS_PER_BLOCK]`.
    - `execution_optimistic` and `finalized` of the block, as getBlobSidecars.
    - An SSZ body takes `Content-Length` when it is whole in the first chunk, else the coding of a JSON body that is not.
  - The validators of the state of `state_id`: getStateValidators, postStateValidators, getStateValidator, getStateValidatorBalances, postStateValidatorBalances and postStateValidatorIdentities.
    - A validator's status at the epoch of the state's slot: the first that holds of `withdrawal_done` (`withdrawable_epoch` at most the epoch, `effective_balance` 0), `withdrawal_possible` (`withdrawable_epoch` at most the epoch), `exited_slashed` and `exited_unslashed` (`exit_epoch` at most the epoch; `slashed` or not), `active_slashed` and `active_exiting` (`activation_epoch` at most the epoch, `exit_epoch` below `FAR_FUTURE_EPOCH`; `slashed` or not), `active_ongoing` (`activation_epoch` at most the epoch), `pending_initialized` (`activation_eligibility_epoch` `FAR_FUTURE_EPOCH`), else `pending_queued`.
    - These are the conditions of the validator status page that beacon-APIs `ValidatorStatus` names; the page calls the balance of the two withdrawal statuses `balance`, and Lighthouse v8.3.3 reads `effective_balance` there, as lantern does.
    - The validators that answer, in index order, each once: with no `id` item, every validator of the state; else each whose index is an index item or whose `pubkey` is a public key item.
    - With `status` bits, only those whose status has its bit.
    - An item of getStateValidators and postStateValidators: `{"index":…,"balance":…,"status":"<status>","validator":<the JSON of the Validator>}`, `balance` the validator's entry of `balances`.
    - Of the two balance operations: `{"index":…,"balance":…}`.
    - Of postStateValidatorIdentities: `{"index":…,"pubkey":…,"activation_epoch":…}`.
    - getStateValidator: the validator of `validator_id`, as an item of getStateValidators: `{"execution_optimistic":…,"finalized":…,"data":<item>}`; with none, 404.
    - The other five are streamed, as getStateV2 but with no `Eth-Consensus-Version`: the JSON body is `{"execution_optimistic":…,"finalized":…,"data":[<the items, with , between>]}`, the values those of the state.
    - postStateValidatorIdentities as SSZ: `Content-Length` of 64 bytes for each item: its index (u64), `pubkey`, and `activation_epoch` (u64), in order, as Lighthouse v8.3.3 writes its `Vec<ValidatorIdentityData>`; the spec names no type.
  - getEpochCommittees: the committees of the state of `state_id`.
    - The epoch: `epoch`, else that of the state's slot. 400 when it is above the state's epoch + 1, or when epoch - MIN_SEED_LOOKAHEAD - 1 (0 when below) is below the state's epoch + 1 - EPOCHS_PER_HISTORICAL_VECTOR (0 when below), so that the RANDAO mix of its seed is not in the state.
    - Lighthouse v8.3.3 gives 400 for both (`CommitteeCache::initialized`).
    - With `slot`, 400 when the slot is not of the epoch.
    - With `index`, 400 when it is get_committee_count_per_slot of the state and the epoch, or more.
    - The checks go in that order.
    - An item for each slot of the epoch (or `slot`), in order, and in each for each index from 0 below get_committee_count_per_slot (or `index`): `{"index":…,"slot":…,"validators":[…]}`, the members of get_beacon_committee of the state, the slot and the index, in order.
    - Streamed, as getStateValidators: `{"execution_optimistic":…,"finalized":…,"data":[<the items, with , between>]}`, the values those of the state.
  - getBlockRewards and getSyncCommitteeRewards: the proposer's and the sync committee's rewards of the block of `block_id`.
  - The spec describes the fields only; these values are those of process_block of the block's fork, as Lighthouse v8.3.3 reads them (beacon_block_reward.rs, sync_committee_rewards.rs).
    - The block: as for getBlockV2; with none, or with no bytes, 404.
    - The pre-state P: the post-state of the node's `NodeBlock` of the block's `parent_root`, brought to the block's slot as a lookup brings a state (node.md, the crossing, then process_slots).
    - No such parent, or one with no post-state: 404, as Lighthouse v8.3.3 answers when the parent's state is not available.
    - `execution_optimistic` and `finalized`: those of the block, as for getBlockHeader.
  - getBlockRewards: `{"execution_optimistic":…,"finalized":…,"data":{"proposer_index":…,"total":…,"attestations":…,"sync_aggregate":…,"proposer_slashings":…,"attester_slashings":…}}`, in Gwei.
    - `proposer_index`: the block's.
    - `proposer_slashings`: for each proposer slashing of the body, the `whistleblower_reward` of its slash_validator: its validator's `effective_balance` in P // `WHISTLEBLOWER_REWARD_QUOTIENT` (`WHISTLEBLOWER_REWARD_QUOTIENT_ELECTRA` from electra). slash_validator with no whistleblower pays the proposer all of it.
    - `attester_slashings`: the same for each validator that process_attester_slashing slashes: of the sorted intersection of the attesting indices of the slashing's two attestations, each that is slashable (is_slashable_validator at the epoch of P) and that no earlier slashing of the body slashed.
    - Lighthouse v8.3.3 counts a validator that an earlier slashing of the same body slashed once more; process_block pays it once.
    - `sync_aggregate`: from altair, the count of the set `sync_committee_bits` of the body times the `proposer_reward` of process_sync_aggregate at P; 0 before altair.
    - `attestations`, from altair: the sum of process_attestation's `proposer_reward` at P for each attestation of the body in order: `proposer_reward_numerator` // ((`WEIGHT_DENOMINATOR` - `PROPOSER_WEIGHT`) * `WEIGHT_DENOMINATOR` // `PROPOSER_WEIGHT`), with each flag an earlier attestation of the body set counted as set.
    - `attestations`, in phase0: the proposer rewards of get_inclusion_delay_deltas for the attestations of the body, paid by the process_epoch at the end of the epoch after the attestation's target epoch.
      - The state E of an attestation of target epoch t: that of the chain at the last slot of epoch t + 1, as for a `state_id` of that slot, and past the store's slot too: the head's post-state brought to it, as Lighthouse v8.3.3 `state_at_slot` does.
      - With none: 404 (the spec: "required state not found").
      - An E whose fork is altair or later: no reward.
      - The upgrade turns those attestations into participation flags (altair fork.md, translate_participation).
      - For each attesting index of the attestation (get_attesting_indices at P), the first time it is one of an attestation of that target epoch in the body: get_base_reward(E, index) // `PROPOSER_REWARD_QUOTIENT`, when the validator is not slashed in E and no attestation of E's `previous_epoch_attestations` with a lower `inclusion_delay` has the index among its attesting indices.
      - Lighthouse v8.3.3 pays a validator once in a body across both target epochs; get_inclusion_delay_deltas of each epoch pays the proposer for each.
    - `total`: the sum of the four.
  - getSyncCommitteeRewards: the balance changes of process_sync_aggregate at P for the body's `sync_aggregate`.
  - A block before altair: 400; it has no sync aggregate.
    - The places: for each pubkey of P's `current_sync_committee`, in order, the index of the validator with that pubkey, as process_sync_aggregate finds them.
    - From the balances of P, in place order: a place whose bit is set adds `participant_reward` to its validator and `proposer_reward` to the proposer; another takes `participant_reward` from its validator, down to 0 at the least (decrease_balance).
    - `participant_reward` and `proposer_reward` are those of process_sync_aggregate at P.
    - A member's reward: its balance after the places less its balance in P; for the proposer, less the proposer rewards it took.
    - Lighthouse v8.3.3 starts from the balances of P, before the other changes of process_block.
    - The items: each member once, in validator index order; with `id` items, each member whose index or `pubkey` is an item.
    - `{"execution_optimistic":…,"finalized":…,"data":[{"validator_index":…,"reward":…},…]}`; `reward` a signed decimal in a string, with `-` before a value below 0.
  - getAttestationsRewards: the rewards and penalties process_rewards_and_penalties pays for the attestations of `epoch`.
  - The spec describes the fields only; these values are those of process_epoch of the fork of S, as Lighthouse v8.3.3 reads them (attestation_rewards.rs).
    - The state S: that of the chain at the last slot of `epoch` + 1, as for a `state_id` of that slot; none (past the store's slot): 404.
    - On a copy of it, process_justification_and_finalization, and from altair process_inactivity_updates: the steps of process_epoch before process_rewards_and_penalties.
    - `execution_optimistic` and `finalized`: those of S, as for a state read.
    - `ideal_rewards`: an item for each effective balance from `EFFECTIVE_BALANCE_INCREMENT` to the largest of the fork of `epoch` (`MAX_EFFECTIVE_BALANCE`; `MAX_EFFECTIVE_BALANCE_ELECTRA` from electra), in steps of `EFFECTIVE_BALANCE_INCREMENT`, ascending: `{"effective_balance":…,"head":…,"target":…,"source":…,"inactivity":…}`, with `"inclusion_delay":…` after `source` when S is of phase0.
    - The values of a validator of that effective balance that voted for all three, in time:
      - From altair: each flag's reward of get_flag_index_deltas: base_reward (the effective balance // `EFFECTIVE_BALANCE_INCREMENT` * get_base_reward_per_increment(S)) * the flag's weight * unslashed_participating_increments // (active_increments * `WEIGHT_DENOMINATOR`); 0 in an inactivity leak (is_in_inactivity_leak).
      - `inactivity` 0.
      - Phase0: base_reward, the effective balance * `BASE_REWARD_FACTOR` // integer_squareroot(get_total_active_balance(S)) // `BASE_REWARDS_PER_EPOCH`. head, target and source: the reward of get_attestation_component_deltas of an unslashed attester, with the attesting balance of the matching head, target or source attestations of the previous epoch: base_reward in an inactivity leak (get_finality_delay above `MIN_EPOCHS_TO_INACTIVITY_PENALTY`), else base_reward * (attesting_balance // `EFFECTIVE_BALANCE_INCREMENT`) // (get_total_active_balance(S) // `EFFECTIVE_BALANCE_INCREMENT`). inclusion_delay: base_reward - get_proposer_reward, the attester's part at a delay of 1. inactivity: in a leak, -(`BASE_REWARDS_PER_EPOCH` * base_reward - get_proposer_reward); else 0.
    - `total_rewards`: an item for each validator: `{"validator_index":…,"head":…,"target":…,"source":…,"inactivity":…}`, with `"inclusion_delay":…` after `source` when S is of phase0.
      - head, target and source: the validator's reward less its penalty of get_flag_index_deltas of the flag (from altair); of get_head_deltas, get_target_deltas and get_source_deltas (phase0).
      - inactivity: minus its penalty of get_inactivity_penalty_deltas.
      - inclusion_delay (phase0): its reward of get_inclusion_delay_deltas as an attester, (base_reward - get_proposer_reward) // the inclusion delay of its earliest attestation; the proposer rewards it takes as a proposer are not part of it.
      - The validators: with no `id` item, each of get_eligible_validator_indices(S), in index order; else each validator of S whose index or `pubkey` is an item, in index order, each once, all its values 0 when it is not eligible.
    - Each value a signed decimal in a string, `-` before a value below 0.
    - Streamed, as getStateValidators: `{"execution_optimistic":…,"finalized":…,"data":{"ideal_rewards":[…],"total_rewards":[…]}}`.
  - getProposerDuties: the proposers of `epoch`.
    - 503 while the node syncs (`is_syncing`), beacon-APIs `CurrentlySyncing`; Lighthouse v8.3.3 refuses its duty operations then too.
    - 400 for an epoch above the epoch of `current_slot` + 1.
    - The state: that of the chain at the epoch's first slot, as for a `state_id` of that slot; a first slot past the store's slot (the next epoch) takes the head's post-state brought to it.
    - With none: 404, as Lighthouse v8.3.3 answers when its state lookup of the slot finds none.
    - `{"dependent_root":…,"execution_optimistic":…,"data":[…]}`, `execution_optimistic` that of the state; for each slot s of the epoch above 0, in order, `{"pubkey":…,"validator_index":…,"slot":…}` of get_beacon_proposer_index of the state at s: from fulu `proposer_lookahead[s % SLOTS_PER_EPOCH]`; before, compute_proposer_index of the epoch's active validators with sha256(get_seed(state, epoch, DOMAIN_BEACON_PROPOSER) + uint_to_bytes(s)).
    - These hold for any s of the epoch from the state at its first slot.
    - Slot 0 never has an item: its block is the genesis block, which no validator proposes.
    - Nimbus v26.10.2, Prysm and Teku leave it out; Lighthouse v8.3.3 and Lodestar list it.
    - The reason: Nimbus's validator client asks produceBlockV3 for each slot it is given.
    - On the 400 of slot 0 it stops using the node for that slot, and misses that slot's attestations.
    - `dependent_root`: get_block_root_at_slot(state, the first slot - 1); for epoch 0, the genesis block's root, hash_tree_root of the state's `latest_block_header` with the state's hash_tree_root as its `state_root`.
  - getProposerDutiesV2 (v5.0.0-beta.0): as getProposerDuties, but `dependent_root` get_block_root_at_slot(state, compute_start_slot_at_epoch(epoch - 1) - 1), the spec's description, one epoch earlier than getProposerDuties.
  - On underflow (epoch 0 and 1), the genesis block's root: for epoch 0 as getProposerDuties gives it; for epoch 1 get_block_root_at_slot(state, 0).
  - produceAttestationData: the `AttestationData` of `slot` and `committee_index` (phase0 validator.md, Attestation data).
    - 503 while the node syncs (`is_syncing`), as getProposerDuties; 400 for a `slot` past `current_slot`.
    - The state: that of the chain at `slot`, as for a `state_id` of that slot; a `slot` at or past the head's takes the head's post-state brought to it, the spec's `head_state` processed through the empty slots to the assigned slot.
    - With none: 400, as the spec lists no 404.
    - 503 when the state's block is optimistic (`execution_optimistic`), as the spec's description asks.
    - `slot`; `index`: `committee_index` before electra, 0 from electra (electra validator.md); `beacon_block_root`: hash_tree_root of the state's `latest_block_header` with the state's hash_tree_root as `state_root` when it is zero; `source`: the state's `current_justified_checkpoint`; `target`: the epoch of `slot`, and the spec's `epoch_boundary_block_root`, the block root when `slot` is the epoch's first slot, else get_block_root(state, epoch).
    - JSON `{"data":{"slot":…,"index":…,"beacon_block_root":…,"source":…,"target":…}}`; with SSZ by `Accept`, the 128 bytes of its SSZ encoding with `Content-Type: application/octet-stream`.
    - No `Eth-Consensus-Version`: the spec lists no header for it.
  - getAttesterDuties: the committee assignments in `epoch` of the validators of the body (phase0 validator.md, get_committee_assignment).
    - 503 while the node syncs, as getProposerDuties; 400 for an epoch above the epoch of `current_slot` + 1; 400 for a body of no item, or with an item that is a public key: the spec's body is an array of at least one validator index.
    - The state: as for getProposerDuties, that of the epoch's first slot; with none, 400, as the spec lists no 404.
    - `{"dependent_root":…,"execution_optimistic":…,"data":[…]}`, `execution_optimistic` that of the state; for each item of the body in order whose validator has an assignment in the epoch, `{"pubkey":…,"validator_index":…,"committee_index":…,"committee_length":…,"committees_at_slot":…,"validator_committee_index":…,"slot":…}`: the member's place in the committee of get_beacon_committee, and get_committee_count_per_slot(state, epoch).
    - An index the state does not have, or of a validator with no assignment in the epoch, gives no item; the spec names no error for it.
    - `dependent_root`: get_block_root_at_slot(state, compute_start_slot_at_epoch(epoch - 1) - 1), the spec's description; on underflow the genesis block's root.
  - getSyncCommitteeDuties: the sync committee places in `epoch` of the validators of the body (altair validator.md, is_assigned_to_sync_committee).
    - 503 while the node syncs, as getProposerDuties; 400 for an epoch whose sync committee period is above that of the epoch of `current_slot` + 1, the spec's description; 400 for a body of no item, or with an item that is a public key: the spec's body is an array of at least one validator index.
    - The state: the head's post-state when its fork is altair or later and the epoch's sync committee period is that of the head's slot or the next; else, as for getAttesterDuties, that of the epoch's first slot (none: 400).
    - The committee: lantern_node_sync_committee of the state and the epoch; with no answer, as for a state before altair, 400.
    - `{"execution_optimistic":…,"data":[…]}`, `execution_optimistic` that of the state; for each item of the body in order whose validator is in the committee, `{"pubkey":…,"validator_index":…,"validator_sync_committee_indices":[…]}`: its places in the committee, ascending.
    - An index the state does not have, or of a validator not in the committee, gives no item.
  - getLiveness: whether each validator of the body was seen live in `epoch`, from its messages "on the network, in the beacon chain, from its API" (the spec's description).
    - 503 while the node syncs, as getProposerDuties.
    - 400 for an epoch below the previous epoch of `current_slot`, or above its next epoch: the spec asks a node to "support the current and previous epoch"; the next epoch answers too, so that a client whose clock is ahead at an epoch's edge gets an answer.
    - 400 for a body of no item, or with an item that is a public key: the spec's body is an array of at least one validator index.
    - The state: the head's post-state at the head's slot, as for a `state_id` of `head` (none: 500).
    - `{"data":[…]}`: for each item of the body in order, `{"index":…,"is_live":…}`.
    - `is_live` is false for an index the state does not have.
    - Else it is true when one of these holds:
      - In the beacon chain, for `epoch` the state's current epoch: from altair, the validator's `current_epoch_participation` flags are not 0; in phase0, the index is among get_attesting_indices of an attestation of `current_epoch_attestations`.
      - In the beacon chain, for `epoch` the state's previous epoch: the same of `previous_epoch_participation` or `previous_epoch_attestations`.
      - On the network and from the API: the node's `Seen` holds a `SEEN_ATTESTATION` or `SEEN_AGGREGATOR_EPOCH` key of `epoch` and the index, or a `SEEN_PROPOSER_SLOT` key of a slot of `epoch` and the index (networking.md, `SeenKey`).
      - The gossip checks of a message, from the network or from a pool POST, add these keys.
    - Sync committee messages and contributions never make a validator live.
    - The beacon nodes of Lighthouse v8.3.3, Nimbus v26.10.2, Teku, Prysm and Lodestar count only attestations, aggregates and blocks.
    - The reason: a validator client's doppelganger check counts only its own attestations and blocks.
    - Nimbus v26.10.2's client stops when a validator of its own is live in an epoch where it sent neither.
  - produceBlockV3: an unsigned block of `slot` for its proposer (validator.md of each fork, Block proposal), with the payload of the node's execution engine, or from bellatrix with a builder (app.md `--builder`) the header of the builder's bid (below).
  - Without a builder the block is never blinded and `builder_boost_factor` changes nothing (the spec: without a builder the node "MUST respond with a full block").
    - 503 while the node syncs (`is_syncing`), beacon-APIs `CurrentlySyncing`, as getProposerDuties.
    - 400: a `slot` at or below the head's slot, or above `current_slot` + 1; a `randao_reveal` that is no `Signature`; with `skip_randao_verification`, a `randao_reveal` other than the point at infinity (`0xc0` and 95 zero bytes, the spec's parameter); without it, a `randao_reveal` that fails the check of process_randao for the proposer of `slot` in the state below; a `graffiti` that is no 32-byte `Bytes32`; a `builder_boost_factor` past 2^64 - 1.
    - The state: the head's post-state brought to `slot`, as for produceAttestationData.
    - Its proposer: get_beacon_proposer_index of that state.
    - The body, in the field order of the fork's `BeaconBlockBody`:
      - `randao_reveal` and `graffiti` (zero bytes without the parameter).
      - `eth1_data`: get_eth1_vote (phase0 and electra `validator.md`) with `eth1_chain` the blocks the eth1 follower holds (node.md); with no follower, an empty chain, whose vote is the state's `eth1_data`.
      - `deposits`: the expected count (phase0 `validator.md`: min(`MAX_DEPOSITS`, `eth1_data.deposit_count` - `eth1_deposit_index`), with the `eth1_data` after this block's vote; electra: get_eth1_pending_deposit_count; none from fulu), each from the eth1 follower with its proof.
      - When the follower lacks one, no valid block is possible: 500.
      - `proposer_slashings`, `attester_slashings`, `voluntary_exits` and `bls_to_execution_changes` (from capella): the pool's entries of the kind, in the pool's order, at most `MAX_PROPOSER_SLASHINGS`, `MAX_ATTESTER_SLASHINGS` (`MAX_ATTESTER_SLASHINGS_ELECTRA` from electra), `MAX_VOLUNTARY_EXITS` and `MAX_BLS_TO_EXECUTION_CHANGES`; attester slashings of the fork's type only.
      - Two operations of one block must not clash: an attester slashing goes only with an index in both attestations that no proposer slashing of the block slashes, and a voluntary exit only for a validator that no slashing of the block slashes.
      - `attestations`: for each `AttestationData` of the pool's attestations that process_attestation's checks of slot and target allow at the state (its target epoch the state's current or previous epoch, `data.slot` + `MIN_ATTESTATION_INCLUSION_DELAY` at most the state's slot, before deneb at most `SLOTS_PER_EPOCH` older, and `source` the state's justified checkpoint of that epoch), the aggregate of its attesters as getAggregatedAttestationV2 builds it; from electra, the aggregates of one `data` of every committee joined by compute_on_chain_aggregate (electra `validator.md`).
      - In order of `data.slot` descending, then the pool's order of each data's first attestation; at most `MAX_ATTESTATIONS` (`MAX_ATTESTATIONS_ELECTRA` from electra).
      - `sync_aggregate` (from altair): process_sync_committee_contributions (altair `validator.md`) of the contribution of each subcommittee, as produceSyncCommitteeContribution builds it from the pool's messages of `slot` - 1 with the block's `parent_root`, those with a participant; with none, no bit and the point at infinity.
      - `execution_payload` (from bellatrix): of engine_getPayload of the fork's version for the payload the node prepared for `slot` on the head (node.md, Payload preparation), prepared now when there is none, with the fee recipient of the proposer's `NodeProposer` entry, else zero bytes.
      - Before the merge (bellatrix, a state with no payload header), the empty payload.
      - `blob_kzg_commitments` (from deneb): the `commitments` of its `blobs_bundle`.
      - `execution_requests` (from electra): lantern_get_execution_requests of its request lists.
    - The block: `slot`, the proposer's index, `parent_root` hash_tree_root of the state's `latest_block_header`, the body, and `state_root` the hash_tree_root of the state after process_block of the block, with no randao signature check when `skip_randao_verification` is given (the spec's compute_new_state_root runs the rest).
    - A block that process_block rejects: 500.
    - `execution_payload_value`: the `blockValue` of the engine's result, 0 for engine_getPayloadV1 and before bellatrix.
    - `consensus_block_value`: the proposer's balance after process_block less its balance before, plus the amounts of the payload's withdrawals to the proposer, at least 0, in Wei (Gwei times 10^9), the spec's "Consensus rewards paid to the proposer for this block".
    - The answer: `Eth-Consensus-Version` the fork of `slot`, `Eth-Execution-Payload-Blinded: false`, `Eth-Execution-Payload-Value` and `Eth-Consensus-Block-Value` in decimal.
    - JSON `{"version":"<fork>","execution_payload_blinded":false,"execution_payload_value":"…","consensus_block_value":"…","data":…}`, `data` the fork's `BeaconBlock` before deneb and from deneb lantern's `BlockContents` of the block, the bundle's `proofs` as `kzg_proofs` and its `blobs`; with SSZ by `Accept`, the SSZ bytes of that value.
    - The builder (builder-specs v0.6.1, bellatrix `validator.md`, Block proposal, and the Builder API), from bellatrix with a builder and a head of a payload (its `block_hash` not zero): a getHeader of `slot`, the head's `block_hash` and the proposer's public key, beside the engine's payload, when all of these hold:
      - `builder_boost_factor` is not 0 (100 without the parameter).
      - The proposer has a registration (registerValidator, below): builder-specs, the bid's `fee_recipient` is that of the validator's latest registration.
      - The head is not optimistic (its `execution_optimistic` false).
      - The chain is healthy, by Lighthouse v8.3.3's default checks (builder-specs, Liveness failsafe: the conditions are the implementation's): `slot` - 1 - the head's slot is at most `BUILDER_FALLBACK_SKIPS` (3); compute_epoch_at_slot(`slot`) - the state's `finalized_checkpoint.epoch` is at most `BUILDER_FALLBACK_EPOCHS_SINCE_FINALIZATION` (3); of the slots from max(`slot` - `SLOTS_PER_EPOCH`, 0) below `slot`, at most `BUILDER_FALLBACK_SKIPS_PER_EPOCH` (8) are skipped (a slot s above 0 whose `block_roots` entry in the state is that of s - 1).
      - Each difference is 0 when it would be below 0.
    - The bid waits at most `BUILDER_PROPOSAL_DELAY_TOLERANCE` (1 s) from the getHeader (builder-specs: after it, the builder flow is aborted for the local block).
    - An answer other than 200, or none in time: the local block.
    - The bid, in the answer's JSON `{"version":"<fork>","data":…}` (other members are skipped): valid when `version` is the fork of `slot`, `data` is the fork's `SignedBuilderBid`, and its header passes:
      - process_bid (builder-specs bellatrix `validator.md`): `parent_hash` is the state's `latest_execution_payload_header.block_hash`; `fee_recipient` is the registration's; bls.Verify of the bid's `pubkey`, compute_signing_root(the `BuilderBid`, compute_domain(`DOMAIN_APPLICATION_BUILDER`)) (the config's `GENESIS_FORK_VERSION` and a zero root) and its `signature`.
      - The checks of process_execution_payload that need no transactions, so the block is valid: `prev_randao` is get_randao_mix(state, the state's current epoch); `timestamp` is compute_time_at_slot(state, `slot`); from capella `withdrawals_root` is the hash_tree_root of get_expected_withdrawals(state); from deneb the bid's `blob_kzg_commitments` are at most the fork's limit (`MAX_BLOBS_PER_BLOCK`, `MAX_BLOBS_PER_BLOCK_ELECTRA`, from fulu get_blob_parameters).
      - An invalid bid: the local block.
    - The choice (beacon-APIs, `builder_boost_factor`): with a valid bid, the local block when `execution_payload_value` of the engine >= `builder_boost_factor` * (the bid's `value` // 100), the product at most 2^256 - 1 (saturating); else the blinded block.
    - The blinded block: the fork's `BlindedBeaconBlock` of the same slot, proposer, parent and body, with the bid's header in place of the payload, from deneb the bid's `blob_kzg_commitments`, from electra its `execution_requests`.
    - `state_root`: the hash_tree_root of the state after process_block of the block with the bid's payload, as the builder's full block gives it: process_block of the block with a payload of the header's fields, no transactions and get_expected_withdrawals(state) as `withdrawals`, then the state's `latest_block_header.body_root` the hash_tree_root of the blinded body and its `latest_execution_payload_header.transactions_root` the header's (process_block_header and process_execution_payload write the roots of the body and of the payload, whose other fields are the bid's).
    - The blinded answer: `Eth-Execution-Payload-Blinded: true`, `Eth-Execution-Payload-Value` the bid's `value`, `Eth-Consensus-Block-Value` as above.
    - JSON `{"version":"<fork>","execution_payload_blinded":true,"execution_payload_value":"…","consensus_block_value":"…","data":…}`, `data` the `BlindedBeaconBlock`; with SSZ by `Accept`, its SSZ bytes.
  - publishBlockV2: a signed block for the network and the node (each fork's validator.md, Broadcast; deneb and later, the sidecars).
    - The body: the fork's `SignedBeaconBlock` before deneb; from deneb lantern's `SignedBlockContents`: `signed_block`, `kzg_proofs` (the bundle's proofs type) and `blobs`.
    - JSON, or SSZ by `Content-Type`.
    - `consensus_version` names the fork of that type.
    - 503 while the node syncs (`is_syncing`), as produceBlockV3.
    - 400: a body that is no such value; a `consensus_version` that is not the fork of the block's slot; deneb and electra, a count of `kzg_proofs` or `blobs` other than that of the body's `blob_kzg_commitments`; fulu, a count of `blobs` other than it, or of `kzg_proofs` other than `CELLS_PER_EXT_BLOB` times it; a block or a sidecar that fails the checks of `broadcast_validation` (below).
    - Nothing goes out.
    - A block whose root the node holds (a `NodeBlock` of that root, of any status but `NODE_BLOCK_INVALID`): 200, and nothing goes out (the block went out before, or came in from the network).
    - The sidecars: deneb and electra get_blob_sidecars (deneb validator.md) of the block, `blobs` and `kzg_proofs`; fulu get_data_column_sidecars_from_block (fulu validator.md) of the block and, for each blob, compute_cells of it and its `CELLS_PER_EXT_BLOB` proofs of `kzg_proofs` in order.
    - `broadcast_validation` `gossip` (1): the checks of the beacon_block topic (p2p-interface.md of the fork, lantern_validate_beacon_block_gossip) at the node's head, and of each sidecar's topic (blob_sidecar, data_column_sidecar) with the same states; a result but `LANTERN_VALID` fails.
    - `consensus` (2): also the state transition of the block on its parent's post-state, with the signature checks and execution_valid 1 (the payload's transactions are the execution engine's, at the import), whose state root is the block's.
    - `consensus_and_equivocation` (3): also no other block of the same proposer and slot that the node saw; the beacon_block topic's check of `proposer_slots`, which `gossip` already runs, is that check.
    - Then the publish of the block on beacon_block and of each sidecar on its subnet's topic (deneb compute_subnet_for_blob_sidecar, fulu compute_subnet_for_data_column_sidecar), and the block and its sidecars go to the node as from the network: a `NodeBlock` with its data available, and the sidecars the node keeps (each blob sidecar; the column sidecars of `columns`).
    - The answer, once the block's import ends: 200 when the node imported it; 202 when it is invalid, after the publish (beacon-APIs: "successfully broadcast but failed integration").
    - No body.
  - publishBlindedBlockV2 (beacon-APIs; builder-specs v0.6.1, submitBlindedBlockV2): before bellatrix (`consensus_version` phase0 or altair) a `SignedBeaconBlock`, answered as publishBlockV2.
  - From bellatrix the fork's `SignedBlindedBeaconBlock`, JSON or SSZ by `Content-Type`:
    - 503 while the node syncs (`is_syncing`), as publishBlockV2.
    - 400: a body that is no such value; a `consensus_version` that is not the fork of the block's slot; a header whose `block_hash` is zero (a block before the merge, which lantern never makes blinded); a block that fails the checks of `broadcast_validation` (below).
    - Nothing goes out.
    - A block whose root the node holds (a `NodeBlock` of that root, of any status but `NODE_BLOCK_INVALID`): 200, and nothing goes out.
    - The root of a blinded block is that of its full block.
    - `broadcast_validation` `gossip` (1): the checks of the beacon_block topic (p2p-interface.md of the fork) on the blinded block (lantern_validate_blinded_block_gossip): those of the payload on its header's `timestamp`, the blob count on its `blob_kzg_commitments`, the signature on the hash_tree_root of the `BlindedBeaconBlock`.
    - `consensus` (2): also the blinded transition of the block on its parent's post-state at its slot (beacon-APIs: "full consensus checks, including validation of all signatures and blocks fields except for the execution payload transactions"): process_block with the signature checks and execution_valid 1 of the block with the stand-in payload of produceBlockV3's blinded block (the header's fields, no transactions, get_expected_withdrawals), the state's `latest_block_header.body_root` then the hash_tree_root of the blinded body and its `latest_execution_payload_header.transactions_root` the header's; its hash_tree_root must be the block's `state_root`.
    - `consensus_and_equivocation` (3): as publishBlockV2.
    - Then, with a builder: submitBlindedBlockV2 to it, `POST /eth/v2/builder/blinded_blocks` with `Eth-Consensus-Version` the fork and the block's JSON as the body (builder-specs: the builder publishes the full block and its blobs).
    - The builder's 202: 200, no body (Lighthouse v8.3.3 answers 200 when the builder takes the block).
    - Another status or a failed call: 500.
    - With no builder: 500.
    - The node imports the full block when it comes over gossip.
  - submitBeaconCommitteeSelections and submitSyncCommitteeSelections: 501.
  - The spec gives them to a distributed validator middleware: "Consensus clients need not support this endpoint and may return a 501."
  - eventstream: the events of `topics`, as server-sent events: the event stream format of the WHATWG HTML standard, section 9.2.
    - The head: `HTTP/1.1 200 OK` CRLF, `Content-Type: text/event-stream` CRLF, `Cache-Control: no-cache` CRLF (the two fields Lighthouse v8.3.3 sends through warp's `sse::reply`); then over HTTP/1.1 `Transfer-Encoding: chunked` CRLF, and `Connection: close` CRLF when the request has `Connection: close`; over HTTP/1.0, with or without `keep-alive`, `Connection: close` CRLF; CRLF.
    - Each event: `event: <topic>` LF `data: <JSON>` LF LF, the layout of the spec's examples.
    - Over HTTP/1.1 each event is one chunk of RFC 9112 section 7.1, its size in 4 lower case hex digits.
    - The answer has no end.
    - The client closes the connection, or the node closes it when the stream falls behind (node.md, `NodeApi`).
    - The topics with events: `block`, `head`, `head_v2`, `finalized_checkpoint`, `chain_reorg`, `block_gossip`, `blob_sidecar`, `data_column_sidecar`, `payload_attributes`, and the operation topics `attestation`, `single_attestation`, `voluntary_exit`, `bls_to_execution_change`, `proposer_slashing`, `attester_slashing` and `contribution_and_proof`.
    - block: a block the node imports: `{"slot":…,"block":…,"execution_optimistic":…}`, the block's slot and root.
    - `execution_optimistic` is true when the payload status the import takes is `PAYLOAD_STATUS_NOT_VALIDATED`.
    - head: the node's head when it changes: `{"slot":…,"block":…,"state":…,"epoch_transition":…,"previous_duty_dependent_root":…,"current_duty_dependent_root":…,"execution_optimistic":…}`.
      - `slot` and `block`: the head block's slot and root.
      - `state`: hash_tree_root of its post-state.
      - `epoch_transition`: true when the epoch of the head's slot is above that of the old head's slot, as Lighthouse v8.3.3 sets it (beacon_chain.rs); the spec names the field only.
      - The dependent roots of the spec's description, from the post-state: get_block_root_at_slot(state, compute_start_slot_at_epoch(epoch - 1) - 1) and get_block_root_at_slot(state, compute_start_slot_at_epoch(epoch) - 1), epoch that of the state's slot.
      - On underflow, the genesis block root: get_block_root_at_slot(state, 0) when the state's slot is above 0, else hash_tree_root of the state's `latest_block_header` with the state's hash_tree_root as its `state_root`.
      - `execution_optimistic`: from the head block's payload status, as for block.
    - head_v2 (v5.0.0-beta.0): with each head event, `{"version":…,"data":{"slot":…,"block":…,"state":…,"payload_status":"full","epoch_transition":…,"current_epoch_dependent_root":…,"next_epoch_dependent_root":…,"execution_optimistic":…}}`.
      - `version`: the fork of the head's slot.
      - The other values are the head event's: `current_epoch_dependent_root` its `previous_duty_dependent_root` and `next_epoch_dependent_root` its `current_duty_dependent_root`, the same slots of the spec's description.
      - `payload_status`: `full`, as a block holds its payload in each fork up to fulu; Prysm v7.3.1 sends `full` before gloas too.
    - execution_payload_available (v5.0.0-beta.0): an event of the gloas fork.
    - An entry may name it; its events come from its other topics.
    - chain_reorg: at a head event, when the new head's chain does not have the old head at the old head's slot, or the old head's slot is not below the new head's (the old head is the head of the last head event): `{"slot":…,"depth":…,"old_head_block":…,"new_head_block":…,"old_head_state":…,"new_head_state":…,"epoch":…,"execution_optimistic":…}`.
    - The spec names the fields only; these are the values Lighthouse v8.3.3 gives (canonical_head.rs, detect_reorg and find_reorg_slot).
      - `slot` and `epoch`: the new head's slot and its epoch.
      - `old_head_block` and `new_head_block`: the roots of the two heads; `old_head_state` and `new_head_state`: the state roots of their blocks.
      - `depth`: the old head's slot less the highest slot, at most the lower of the two heads' slots, at which both chains have the same block root; a chain's root at a slot is that of its block of the highest slot at or below it.
      - `execution_optimistic`: from the new head's payload status, as for block.
    - block_gossip: a block that passes the checks of the beacon_block topic, from the network, or from publishBlockV2 once its checks pass (each `broadcast_validation` level runs them): `{"slot":…,"block":…}`, the block's slot and root.
    - blob_sidecar: a `BlobSidecar` that passes the checks of its blob_sidecar topic, from the network, or from publishBlockV2 for each sidecar it publishes: `{"block_root":…,"index":…,"slot":…,"kzg_commitment":…,"versioned_hash":…}`.
    - `block_root`: hash_tree_root of its `signed_block_header.message`; `slot`: that header's slot; `versioned_hash`: kzg_commitment_to_versioned_hash of its `kzg_commitment` (deneb beacon-chain.md).
    - data_column_sidecar: a `DataColumnSidecar` that passes the checks of its data_column_sidecar topic, from the network, or from publishBlockV2 for each sidecar it publishes: `{"block_root":…,"index":…,"slot":…,"kzg_commitments":[…]}`, `block_root` and `slot` as for blob_sidecar.
    - payload_attributes: each payload preparation of the node (node.md, Payload preparation) that makes its engine_forkchoiceUpdated request (the spec: the node "has computed new payload attributes"): `{"version":"<fork>","data":{"proposer_index":…,"proposal_slot":…,"parent_block_number":…,"parent_block_root":…,"parent_block_hash":…,"payload_attributes":{…}}}`.
      - `version`: the fork of `proposal_slot`, the slot of the block to build.
      - `proposer_index`: get_beacon_proposer_index of the state at that slot.
      - `parent_block_root`: the head's root, on which the block builds.
      - `parent_block_number` and `parent_block_hash`: the `block_number` and `block_hash` of the state's `latest_execution_payload_header`.
      - `payload_attributes`: those of lantern_get_payload_attributes, in the spec's beacon API encoding of `PayloadAttributesV<N>` (snake_case names, quoted decimal integers): `timestamp`, `prev_randao`, `suggested_fee_recipient`; from capella `withdrawals`, each `{"index":…,"validator_index":…,"address":…,"amount":…}`; from deneb `parent_beacon_block_root`.
    - The operation topics: an operation that passes the gossip validation of its gossip topic (lantern_node_gossip gives `LANTERN_VALID`), from the network or from a pool POST (the spec: "from P2P or API"): the JSON of its SSZ bytes, by lantern_json_encode_ssz with the type of the fork of that validation.
      - attestation: an `Attestation` of beacon_attestation, before electra. single_attestation: a `SingleAttestation` of beacon_attestation, from electra; the topic's messages have that type from electra.
      - voluntary_exit: a `SignedVoluntaryExit`. bls_to_execution_change: a `SignedBLSToExecutionChange`. proposer_slashing: a `ProposerSlashing`. attester_slashing: the fork's `AttesterSlashing`. contribution_and_proof: a `SignedContributionAndProof` of sync_committee_contribution_and_proof.
      - An operation that its validation ignores, as one the node has seen, gives no event.
    - light_client_finality_update and light_client_optimistic_update: the store's latest finality update when it is new, as altair light-client `p2p-interface.md` forwards one (a finalized slot above all forwarded before, or the same with a supermajority the last did not have), and its optimistic update when its attested slot is above all forwarded before: `{"version":"<fork>","data":<data>}`, as getLightClientFinalityUpdate and getLightClientOptimisticUpdate.
    - finalized_checkpoint: the store's finalized checkpoint, when its epoch rises: `{"block":…,"state":…,"epoch":…,"execution_optimistic":…}`, the checkpoint's root and epoch, and the `state_root` of that block.
    - Lighthouse v8.3.3 sends the finalized block's `state_root` there; the spec names the field only.
    - `execution_optimistic`: from the block's payload status, as for block.
  - The pools (node.md, `NodePool`): voluntary exits, BLS to execution changes, proposer slashings, attester slashings and attestations, each kept as its SSZ bytes once it passes its gossip validation, from gossip or from the POSTs below.
  - An operation goes when it no longer passes it at a later head; an attestation goes once its epoch is before the previous epoch of the store's slot.
    - The attestations are those of the subnets the node subscribes to and those of submitPoolAttestationsV2, each with one attester.
    - Aggregates do not join the pool.
    - The pool also keeps sync committee messages, from the sync_committee subnets the node subscribes to and from submitPoolSyncCommitteeSignatures, each with its slot and the subnets it is valid on, until the store's slot is past its slot + 1.
    - No pool GET answers them.
  - getPoolVoluntaryExits, getPoolBLSToExecutionChanges and getPoolProposerSlashings: `{"data":[<the JSON of each pool entry of the kind, in the pool's order, with , between>]}`.
  - getPoolAttesterSlashingsV2: `Eth-Consensus-Version` and `version` the fork of the store's slot; `{"version":"<fork>","data":[…]}` of the pool's attester slashings of that fork's `AttesterSlashing` type (electra's from electra on, phase0's before).
  - The spec names neither the version nor which slashings answer; this is the fork whose type the node decodes at its slot.
  - getPoolAttestationsV2: `Eth-Consensus-Version` and `version` the fork of the store's slot; `{"version":"<fork>","data":[…]}` of the pool's attestations of that fork's attestation type, with `data.slot` equal to `slot` and the committee index equal to `committee_index` when those are given.
  - From electra the pool keeps each attestation as the `SingleAttestation` it came as, and the answer gives the electra `Attestation` of it: `aggregation_bits` of its committee's length with its attester's bit, `committee_bits` with its committee index's bit, as the spec's `Attestation` of one attester has them (the response's type).
  - getAggregatedAttestationV2: the aggregate of the pool's attestations of the attestation type of the fork of the store's slot with `data.slot` `slot`, the committee index `committee_index` and a `data` whose hash_tree_root is `attestation_data_root`, in pool order: each whose attester's place in its committee no attestation before it took joins, its place's bit set in `aggregation_bits` (of its committee's length) and its signature added by crypto_bls_aggregate.
    - None: 404; a `data.beacon_block_root` of a block whose `payload_status` is `NOT_VALIDATED`: 503 (the spec's description).
    - `Eth-Consensus-Version` and `version` the fork; `{"version":"<fork>","data":<Attestation>}`, the JSON of the fork's `Attestation`, or with an SSZ `response` its SSZ bytes.
    - From electra the electra `Attestation`, `committee_bits` with the bit of `committee_index`.
  - produceSyncCommitteeContribution: the `SyncCommitteeContribution` of the pool's sync committee messages of `slot`, valid on the subnet `subcommittee_index`, with `beacon_block_root`, in pool order (altair validator.md, Construct sync committee contribution): for each whose places in the subcommittee (lantern_node_sync_positions of the head's post-state) no message before it took, the bit of each place is set and its signature added by crypto_bls_aggregate once for each place.
    - A `subcommittee_index` not below `SYNC_COMMITTEE_SUBNET_COUNT`: 400.
    - None: 404; a `beacon_block_root` of a block whose `payload_status` is `NOT_VALIDATED`: 503 (the spec's description).
    - A head with no post-state: 500.
    - `{"data":<SyncCommitteeContribution>}`, JSON only (the spec gives no SSZ response).
  - The five are streamed, as getStateValidators: one chunk or more per entry, from the entry's SSZ bytes by lantern_json_encode_ssz of its type.
  - submitPoolVoluntaryExit, submitPoolProposerSlashings, submitPoolAttesterSlashingsV2 and submitPoolBLSToExecutionChange: the body, JSON of `SignedVoluntaryExit`, `ProposerSlashing`, the `AttesterSlashing` of the fork of the store's slot, or a JSON array of `SignedBLSToExecutionChange`, each item decoded by lantern_json_decode (the spec sets no limit on the items; the body's own limit bounds them).
  - A body that is no JSON of its type, or an array with an item that is not: 400 `{"code":400,"message":"BAD_REQUEST"}`, and no operation goes on.
    - Each operation, in the list's order: the gossip validation of its topic (lantern_node_gossip, with the node's `Seen`, as a gossip message is checked).
    - Valid: it joins the pool and goes out on its topic (node.md, the publish).
    - Ignored, as one the node has seen: nothing more; Lighthouse v8.3.3 answers an operation it knows with success too.
    - Rejected: a failure.
    - The answer: 200 with no body when no operation fails.
    - Else 400: of the three single operations `{"code":400,"message":"BAD_REQUEST"}`; of the list, the IndexedErrorMessage of beacon-APIs, `{"code":400,"message":"BAD_REQUEST","failures":[{"index":<i>,"message":"REJECT"},…]}`, an item for each rejected operation in order, `index` its place in the list as a JSON number.
    - submitPoolAttesterSlashingsV2 requires `Eth-Consensus-Version` (the route); a fork whose `AttesterSlashing` type is not that of the store's slot: 400.
  - submitPoolAttestationsV2: a JSON array of the fork's attestation type, `Attestation` before electra and `SingleAttestation` from electra (the spec's description), or with `Content-Type: application/octet-stream` the SSZ list of them.
  - `Eth-Consensus-Version` is required (the route); a fork of the other type than the fork of the store's slot: 400.
  - A body that is no such list: 400 `{"code":400,"message":"BAD_REQUEST"}`.
    - Each attestation, in order: the gossip validation of beacon_attestation of its subnet, compute_subnet_for_attestation of the committee count of its target epoch in the head's post-state, its slot and its committee index, as phase0 validator.md places it, with the node's `Seen`.
    - Valid: it joins the pool and goes out on that subnet (the spec: the node MUST publish it); rejected: a failure; ignored: nothing more.
    - The answer: 200 with no body when none fails; else 400 with the IndexedErrorMessage of the failures, as for submitPoolBLSToExecutionChange.
  - publishAggregateAndProofsV2: a JSON array of the fork's `SignedAggregateAndProof` (phase0's before electra, electra's from electra), or with `Content-Type: application/octet-stream` the SSZ list of them (4-byte offsets, the type is of variable size).
  - `Eth-Consensus-Version` is required (the route); a fork of the other type than the fork of the store's slot: 400.
  - A body that is no such list: 400 `{"code":400,"message":"BAD_REQUEST"}`.
    - Each aggregate, in order: the gossip validation of beacon_aggregate_and_proof, with the node's `Seen`.
    - Valid: it goes out on its topic (the spec's description: "publishes them on appropriate gossipsub topic"); it joins no pool, and fork choice takes no vote from it, as from a submitted attestation.
    - Rejected: a failure; ignored: nothing more.
    - The answer: 200 with no body when none fails; else 400 with the IndexedErrorMessage of the failures, as for submitPoolBLSToExecutionChange.
  - submitPoolSyncCommitteeSignatures, from altair: a JSON array of `SyncCommitteeMessage`.
  - A body that is no such list: 400 `{"code":400,"message":"BAD_REQUEST"}`.
    - Each message, in order: the gossip validation of sync_committee of each subnet of compute_subnets_for_sync_committee(the head's post-state, its `validator_index`) (altair validator.md; lantern_node_sync_subnets), with the node's `Seen`; with no such subnet (an index past the validators, or a validator outside the sync committee), that of subnet 0, which rejects it or ignores it.
    - Valid on a subnet: it joins the pool and goes out on each subnet where it is valid (the spec's description: the node "MUST publish that sync committee signature on all applicable subnets").
    - Else rejected on a subnet: a failure.
    - Else nothing more.
    - The answer: 200 with no body when none fails; else 400 with the IndexedErrorMessage of the failures, as for submitPoolBLSToExecutionChange.
  - publishContributionAndProofs, from altair: a JSON array of `SignedContributionAndProof`.
  - A body that is no such list: 400 `{"code":400,"message":"BAD_REQUEST"}`.
    - Each, in order: the gossip validation of sync_committee_contribution_and_proof, with the node's `Seen`.
    - Valid: it goes out on its topic; it joins no pool, as an aggregate.
    - Rejected: a failure; ignored: nothing more.
    - The answer: 200 with no body when none fails; else 400 with the IndexedErrorMessage of the failures, as for submitPoolBLSToExecutionChange.
  - prepareBeaconCommitteeSubnet: a JSON array of the spec's items, decoded as lantern's `BeaconCommitteeSubscription` (`validator_index`, `committee_index`, `committees_at_slot`, `slot`, `is_aggregator`).
  - An item whose `committees_at_slot` is 0 or above `MAX_COMMITTEES_PER_SLOT`, or whose `committee_index` is not below it, or a body of no such list: 400 `{"code":400,"message":"BAD_REQUEST"}`, and none applies.
    - Each item with `is_aggregator`: the node joins beacon_attestation of compute_subnet_for_attestation(`committees_at_slot`, `slot`, `committee_index`) (phase0 validator.md) and keeps it until the store's slot is past `slot` (node.md, the subscriptions); the pool keeps the subnet's attestations, which getAggregatedAttestationV2 aggregates (the spec: "announce subnet topic subscription on gossipsub" and "aggregate attestations received on that subnet").
    - An item without it changes nothing.
    - The answer: 200 with no body.
  - prepareSyncCommitteeSubnets, from altair: a JSON array of `SyncCommitteeSubscription`, lantern's container of the spec's type (`sync_committee_indices` at most `SYNC_COMMITTEE_SIZE`).
  - An index not below `SYNC_COMMITTEE_SIZE`, or a body of no such list: 400 `{"code":400,"message":"BAD_REQUEST"}`, and none applies.
    - Each index i of each item: the node joins sync_committee of the subnet i / (SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT) and keeps it while the store's epoch is below `until_epoch` (the spec: "The final epoch (exclusive value)"); its MetaData's and record's `syncnets` are those subnets (altair p2p-interface.md).
    - The answer: 200 with no body.
  - prepareBeaconProposer: a JSON array of the spec's items, decoded as lantern's `ProposerPreparation` (`validator_index`, `fee_recipient`).
  - A body of no such list: 400 `{"code":400,"message":"BAD_REQUEST"}`, and none applies.
    - Each item: the node's `NodeProposer` entry of its `validator_index` takes its `fee_recipient` until the store's epoch + 3, exclusive (the spec: it persists "through the epoch in which the call is submitted and for a further two epochs after that"); an index the node does not know is kept too (the spec: such requests "will be accepted").
    - With no entry of its index: a free entry, one past its epoch, else a new one while the part has room; else the item is dropped.
    - The answer: 200 with no body.
  - registerValidator: a JSON array of `SignedValidatorRegistrationV1` (builder-specs v0.6.1, include/types.inc), or with `Content-Type: application/octet-stream` the SSZ list of them (items of 180 bytes).
  - A body that is no such list: 400 `{"code":400,"message":"BAD_REQUEST"}`, and none applies.
    - Each registration, in order: eligible when its `pubkey` is a validator of the head's post-state that is active or pending at the state's current epoch (builder-specs is_eligible_for_registration: is_active_validator, or `activation_epoch` above the epoch).
    - Another is filtered out (beacon-APIs: registrations of unknown or exited validators "must be filtered out and not sent to the builder network"), with no failure.
    - An eligible one becomes the registration of its validator's `NodeProposer` entry (node.md), unless that entry holds one of a later `timestamp`; with none, the first free entry, else a new one while the part has room.
    - With `NODE_FLAG_BUILDER` and an eligible one: a `NODE_BUILDER_REGISTER` call (node.md, the builder calls) of the JSON array of the eligible ones, in order.
    - The node checks no signature: the builder does (builder-specs verify_registration_signature is its processing).
    - The answer: 200 with no body, once the registrations apply.
  - Every other operation: 501.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_event`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the store in x20, rbp, s2; the scratch in x23, r14, s5; the actions in x24, r15, s6.
- Argument order: `event`.

## Function `lantern_node_api_event_count`

The NodeApi entries of eventstream.

### Signature

```
lantern_node_api_event_count() -> count
```

### Function does

- Returns the count of NodeApi entries of eventstream.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_event_count`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x12; rax, rcx, rdx; a0, a7, t0 to t3.

## Function `lantern_node_api_event_done`

Takes the end of a NODE_WORK_API_EVENT.

### Signature

```
lantern_node_api_event_done(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | `NodeEvent` of kind `NODE_EV_WORK_DONE` |

### Function does

- For `LANTERN_VALID`, sends its text to the entries of its topic (lantern_node_api_events).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_event_done`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Registers it reads, on ARM64, x86-64, RISC-V: the actions in x24, r15, s6.
- Argument order: `event`.

## Function `lantern_node_api_event_run`

The NODE_WORK_API_EVENT work of lantern_node_run.

### Signature

```
lantern_node_api_event_run(node, work, state_a, data, scratch, event, room) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `node` | input | the node |
| `work` | input | `NodeAction` of the work |
| `state_a` | input | `BeaconState` |
| `data` | input | the event's bytes |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `event` | output | `NodeEvent` |
| `room` | input | u64 in a register: the bytes of the event's buffer |

### Returns

- As lantern_node_run.

### Function does

- Writes the event's text at `NodeEvent_chunk` of the event (node.md, NODE_WORK_API_EVENT).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_event_run`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `node`, `work`, `state_a`, `data`, `scratch`, `event`, `room`.

## Function `lantern_node_api_events`

Sends an event text to the eventstream entries of its topic.

### Signature

```
lantern_node_api_events(text, topic)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `text` | input | ByteList |
| `topic` | input | u64 in a register |

### Function does

- Each NodeApi entry of eventstream of the topic gets a SEND of the text, in one chunk with `API_STREAM_CHUNKED`; its bytes join the entry's `sent` (node.md, The events).
- An entry whose `sent` would pass `NODE_API_CHUNK` gets a CLOSE and ends.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_events`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Registers it reads, on ARM64, x86-64, RISC-V: the actions in x24, r15, s6.
- Argument order: `text`, `topic`.

## Function `lantern_node_api_final_block`

Whether a slot is at most the finalized block's.

### Signature

```
lantern_node_api_final_block(slot) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `slot` | input | u64 in a register |

### Function does

- Returns 1 when the slot is at most that of the block of the store's finalized root, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_final_block`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the store in x20, rbp, s2.
- Argument order: `slot`.

## Function `lantern_node_api_find`

The NodeApi entry of a connection.

### Signature

```
lantern_node_api_find(connection) -> (index, entry)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `connection` | input | u64 in a register |

### Function does

- Returns the index of the NodeApi entry of the connection, or 2^64 - 1, and the entry.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_find`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1, x9 to x12, x16; rax, rdx, rcx, r10; a0, a1, a7, t0 to t3.
- Argument order: `connection`.

## Function `lantern_node_api_find_peer`

The NodePeer of a route's peer_id.

### Signature

```
lantern_node_api_find_peer(route) -> peer
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `route` | input | [`ApiRoute`](#type-apiroute) |

### Function does

- Returns the NodePeer whose peer ID's base58btc text is the route's peer_id, or 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 192 bytes on x86-64 (return address included), 192 bytes on ARM64, 192 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_find_peer`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Argument order: `route`.

## Function `lantern_node_api_find_validator`

The index of the validator of a ValidatorRef.

### Signature

```
lantern_node_api_find_validator(state, ref) -> index
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `ref` | input | ByteList of one [`ValidatorRef`](#type-validatorref) |

### Function does

- Returns the index of the validator in the state, or 2^64 - 1.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_find_validator`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0 to x5, x9 to x16; rax, rcx, rdx, rsi, r8, r9; a0, a1, a7, t0 to t6.
- Argument order: `state`, `ref`.

## Function `lantern_node_api_fold`

Folds a pool attestation into the aggregate of a getAggregatedAttestationV2 stream.

### Signature

```
lantern_node_api_fold(scratch, data) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `data` | input | the pool entry's bytes |

### Returns

- 0: done.
- 1: bytes that are no attestation, or a signature crypto_bls_aggregate rejects.
- 2: a short scratch.

### Function does

- Folds the bytes into the aggregate in the cursor at `NodeEvent_api` + 16 of the event (node.md, getAggregatedAttestationV2): of the fork in `sent`, a SingleAttestation (place and length from `member`) or an Attestation (place its bit, length that of its bits).
- With data of the root at byte 0, a place not taken, and the length of the aggregate: its bit at byte 272, and its signature added at byte 176 by crypto_bls_aggregate.
- The first gives the length (40), data (48) and signature; byte 32 counts them.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_fold`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the stream registers of lantern_api_stream_json.
- On ARM64 it takes the bytes in x21.
- Argument order: `scratch`, `data`.

## Function `lantern_node_api_free`

The free NodeApi entries of the node.

### Signature

```
lantern_node_api_free() -> count
```

### Function does

- Returns the capacity past the count, plus the free entries below it.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_free`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x12, x16; rax, rcx, rdx, rsi, r10; a0, a7, t0 to t3.

## Function `lantern_node_api_head_events`

Queues the head and finalized_checkpoint events at a quiet point.

### Signature

```
lantern_node_api_head_events()
```

### Function does

- With no block vote queued: a head other than `event_head`, then a finalized epoch above `event_epoch` (node.md, The events).
- Each is a NODE_WORK_API_EVENT when an entry has its topic.
- A new head first queues the light client data work, a chain_reorg before the head event, and the pool's checks at the new head.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_head_events`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the store in x20, rbp, s2; the actions in x24, r15, s6.

## Function `lantern_node_api_headers_stream`

Starts the getBlockHeaders stream.

### Signature

```
lantern_node_api_headers_stream(connection, route, flags)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `connection` | input | u64 in a register |
| `route` | input | [`ApiRoute`](#type-apiroute) |
| `flags` | input | u64 in a register: the answer flags |

### Function does

- Starts the stream of the route's query (node.md, NODE_EV_API): `filter_slot` its slot, the head's slot with neither slot nor parent_root, else 2^64 - 1.
- Its parent_root at byte 32 of the cursor and 1 at byte 64.
- `API_STREAM_OPTIMISTIC` and `API_STREAM_FINALIZED` of all its items.
- Then its first item and a NODE_WORK_API_CHUNK.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 64 bytes on x86-64 (return address included), 64 bytes on ARM64, 64 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_headers_stream`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `connection`, `route`, `flags`.

## Function `lantern_node_api_ids`

Puts the ids of a validator operation.

### Signature

```
lantern_node_api_ids(route) -> id
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `route` | input | [`ApiRoute`](#type-apiroute) |

### Function does

- Returns the new id of a BYTES_PUT of the route's ValidatorRef items (getStateValidator: its validator_id), or 0 with none (node.md, NODE_EV_API).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_ids`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `route`.

## Function `lantern_node_api_lookup`

Starts the lookup of a state_id of a root.

### Signature

```
lantern_node_api_lookup(connection, route, flags, wait) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `connection` | input | u64 in a register |
| `route` | input | [`ApiRoute`](#type-apiroute) |
| `flags` | input | u64 in a register: the answer flags |
| `wait` | input | u64 in a register: 1 for a slot whose state waits for the replay |

### Returns

- 0: started.
- 404: no head post-state.

### Function does

- A NodeApi entry with `API_STREAM_LOOKUP` and a NODE_WORK_API_LOOKUP with the head's post-state (node.md, NODE_EV_API).
- With `wait` 1: the entry with `API_STREAM_REPLAY`, the slot at `API_REPLAY_SLOT` of its cursor, and no work.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_lookup`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `connection`, `route`, `flags`, `wait`.

## Function `lantern_node_api_lookup_done`

Takes the end of a NODE_WORK_API_LOOKUP.

### Signature

```
lantern_node_api_lookup_done(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | `NodeEvent` of kind `NODE_EV_WORK_DONE` |

### Function does

- Its entry goes on with the slot found, the replay allowed (lantern_node_api_rerun).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_lookup_done`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the store in x20, rbp, s2; the scratch in x23, r14, s5; the actions in x24, r15, s6.
- Argument order: `event`.

## Function `lantern_node_api_lookup_run`

The NODE_WORK_API_LOOKUP work of lantern_node_run.

### Signature

```
lantern_node_api_lookup_run(node, work, state_a, scratch, event) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `node` | input | the node |
| `work` | input | `NodeAction` of the work |
| `state_a` | input | `BeaconState` |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `event` | output | `NodeEvent` |

### Returns

- As lantern_node_run.

### Function does

- Writes at `NodeEvent_index` of the event the slot whose state on the chain of `state_a` has the root of the NodeApi entry at the work's `arg`, or 2^64 - 1 (node.md, NODE_WORK_API_LOOKUP).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_lookup_run`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `node`, `work`, `state_a`, `scratch`, `event`.

## Function `lantern_node_api_new`

Takes a free NodeApi entry.

### Signature

```
lantern_node_api_new() -> (index, entry)
```

### Caller must

- The step checked that one is free.

### Function does

- Returns the index and the entry of a free NodeApi entry: the first free, else the next.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_new`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1, x9 to x12, x16; rax, rdx, r10; a0, a1, a7, t0 to t2.

## Function `lantern_node_api_on_chain`

Whether a block is on the chain.

### Signature

```
lantern_node_api_on_chain(entry) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | input | the `NodeBlock` entry |

### Function does

- Returns 1 when the block is on the head's chain, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_on_chain`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Argument order: `entry`.

## Function `lantern_node_api_parent`

The imported parent of a block.

### Signature

```
lantern_node_api_parent(entry) -> (index, entry)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | input | the `NodeBlock` entry |

### Function does

- Returns the NodeBlock index of its imported parent, or 2^64 - 1, and its entry.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_parent`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Argument order: `entry`.

## Function `lantern_node_api_pool_advance`

Moves a pool stream to its next entry.

### Signature

```
lantern_node_api_pool_advance(entry)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the `NodeApi` entry |

### Function does

- The stream goes to its next pool entry after `slot` (node.md, NODE_WORK_API_CHUNK): its slot, data, sent and member, a zero cursor; data 0 with none.
- Bytes it owned get a BYTES_FREE, and `API_STREAM_OWN` clears.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_pool_advance`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `entry`.

## Function `lantern_node_api_pool_stream`

Starts the stream of a pool GET.

### Signature

```
lantern_node_api_pool_stream(connection, route, flags, view)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `connection` | input | u64 in a register |
| `route` | input | [`ApiRoute`](#type-apiroute) |
| `flags` | input | u64 in a register: `API_STREAM_CLOSE` and `API_STREAM_HTTP10` |
| `view` | input | `ApiView` |

### Function does

- A NodeApi entry (node.md, NODE_EV_API): fork the store's, the filters of getPoolAttestationsV2; slot the first entry it answers, data its bytes, sent its fork, member its member; data 0 with none.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 64 bytes on x86-64 (return address included), 64 bytes on ARM64, 64 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_pool_stream`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the store in x20, rbp, s2; the actions in x24, r15, s6.
- Argument order: `connection`, `route`, `flags`, `view`.

## Function `lantern_node_api_produce`

Starts a produceBlockV3.

### Signature

```
lantern_node_api_produce(connection, route, flags, view) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `connection` | input | u64 in a register |
| `route` | input | [`ApiRoute`](#type-apiroute) |
| `flags` | input | u64 in a register: the answer flags |
| `view` | input | `ApiView` |

### Returns

- 0: started.
- Else the status of the error to answer.

### Function does

- A NodeApi entry in `NODE_PRODUCE_STATE` that owns the state of the view, a copy at the slot, with the request in its cursor, and a PRODUCE_CHECK work of it (node.md, Block production).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_produce`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `connection`, `route`, `flags`, `view`.

## Function `lantern_node_api_publish`

Starts a publishBlockV2.

### Signature

```
lantern_node_api_publish(connection, route, flags, request) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `connection` | input | u64 in a register |
| `route` | input | [`ApiRoute`](#type-apiroute) |
| `flags` | input | u64 in a register: the answer flags |
| `request` | input | [`HttpRequest`](#type-httprequest) |

### Returns

- 0: started.
- Else the status of the error to answer.

### Function does

- A NodeApi entry in `NODE_PUBLISH_DECODE`, the body's bytes as its data, and a PUBLISH_DECODE work of them (node.md, Block publishing).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_publish`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `connection`, `route`, `flags`, `request`.

## Function `lantern_node_api_publish_count`

The count of the publishBlockV2 entries.

### Signature

```
lantern_node_api_publish_count() -> count
```

### Function does

- Returns the count of the publishBlockV2 entries.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_publish_count`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x12; rax, rcx, rdx, rsi; a0, t0 to t3.

## Function `lantern_node_api_put8`

Puts 8 bytes under a new id.

### Signature

```
lantern_node_api_put8(bytes) -> id
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | 8 bytes |

### Function does

- Returns the new id of a BYTES_PUT of the 8 bytes.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_put8`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `bytes`.

## Function `lantern_node_api_reorg`

The depth of a reorg.

### Signature

```
lantern_node_api_reorg(old, new) -> (depth, entry)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `old` | input | Root: the old head |
| `new` | input | the new head's `NodeBlock` entry |

### Function does

- Returns the depth of the reorg from the old head to the new (node.md, The events: chain_reorg), or 2^64 - 1 with none: the new head's chain has the old head below the new head's slot, or a walk meets no common block.
- Also returns the old head's entry.
- The walk goes by parent_root from both, the one at the higher slot first.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_reorg`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Argument order: `old`, `new`.

## Function `lantern_node_api_rerun`

Goes on with a lookup entry.

### Signature

```
lantern_node_api_rerun(entry, slot, replay)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the `NodeApi` entry |
| `slot` | input | u64 in a register: the slot of its state_id, or 2^64 - 1 |
| `replay` | input | u64 in a register: 1 to allow the replay |

### Function does

- The entry ends, then the answer of its operation for the state_id of the slot, or 404 for 2^64 - 1 (node.md, NODE_WORK_API_LOOKUP done, and the replay).
- With `replay` 1, a state that needs the replay keeps the entry waiting: `API_STREAM_REPLAY`, the slot at `API_REPLAY_SLOT` of its cursor.
- With `API_STREAM_GONE` it ends.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 240 bytes on x86-64 (return address included), 240 bytes on ARM64, 240 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_rerun`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the store in x20, rbp, s2; the scratch in x23, r14, s5; the actions in x24, r15, s6.
- Argument order: `entry`, `slot`, `replay`.

## Function `lantern_node_api_rewards`

Starts getBlockRewards or getSyncCommitteeRewards.

### Signature

```
lantern_node_api_rewards(connection, route, flags, view) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `connection` | input | u64 in a register |
| `route` | input | [`ApiRoute`](#type-apiroute) |
| `flags` | input | u64 in a register: the answer flags |
| `view` | input | `ApiView` |

### Returns

- 0: started.
- Else the error status.

### Function does

- The block, a NodeBlock with bytes; P, its parent's post-state brought to its slot (node.md, NODE_EV_API).
- getSyncCommitteeRewards: its ids as `state_b`; getBlockRewards of a phase0 block: the E states as `state_b` and `state_c`.
- A NODE_WORK_API_ENCODE, then a STATE_FREE of each copy.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 208 bytes on x86-64 (return address included), 208 bytes on ARM64, 208 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_rewards`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the store in x20, rbp, s2; the actions in x24, r15, s6.
- Argument order: `connection`, `route`, `flags`, `view`.

## Function `lantern_node_api_rewards_state`

The state of the chain at a slot, for the rewards.

### Signature

```
lantern_node_api_rewards_state(slot) -> (status, id, copy)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `slot` | input | u64 in a register |

### Returns

- 0: the second value is the state's id, the third 1 when it is a copy.
- 404: the node keeps no such state.

### Function does

- The state as for a state_id of the slot; past the store's slot, the head's post-state brought to it (beacon-APIs getBlockRewards).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_rewards_state`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the store in x20, rbp, s2; the actions in x24, r15, s6.
- It takes the route and the view in x21 and x22, r12 and r13, s3 and s4.
- It returns three values: x0 to x2; rax, rdx, rcx; a0 to a2.
- Argument order: `slot`.

## Function `lantern_node_api_root_event`

Queues the event of a block root.

### Signature

```
lantern_node_api_root_event(topic, root, slot, values)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `topic` | input | u64 in a register: block or block_gossip |
| `root` | input | Root |
| `slot` | input | u64 in a register |
| `values` | input | u64 in a register |

### Function does

- With an entry of the topic: its text in a ByteList at the end of the scratch, after the ApiView of its values (node.md, The events).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_root_event`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the scratch in x23, r14, s5; the actions in x24, r15, s6.
- Argument order: `topic`, `root`, `slot`, `values`.

## Function `lantern_node_api_run`

The NODE_WORK_API_ENCODE work of lantern_node_run.

### Signature

```
lantern_node_api_run(node, store, work, state_a, data, scratch, event, room, seen) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `node` | input | the node |
| `store` | input | `Store` |
| `work` | input | `NodeAction` of the work |
| `state_a` | input | `BeaconState` |
| `data` | input | the bytes of the lookup |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `event` | output | `NodeEvent` |
| `room` | input | u64 in a register: the bytes of the event's buffer |
| `seen` | input | the seen of lantern_node_run |

### Returns

- As lantern_node_run.

### Function does

- Writes the response at `NodeEvent_chunk` of the event (node.md, NODE_WORK_API_ENCODE).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_run`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It takes `seen` in x8, rax, t0.
- Argument order: `node`, `store`, `work`, `state_a`, `data`, `scratch`, `event`, `room`, `seen`.

## Function `lantern_node_api_same_root`

Whether two roots are the same.

### Signature

```
lantern_node_api_same_root(a, b) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `a` | input | Bytes32 |
| `b` | input | Bytes32 |

### Function does

- Returns 1 when the 32 bytes are the same, else 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 0 bytes on ARM64.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_same_root`, local to its object. Only ARM64 have it.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It is on ARM64.
- Registers it changes, on ARM64: x0, x9 to x12.
- Argument order: `a`, `b`.

## Function `lantern_node_api_send`

Queues an API_SEND of a response.

### Signature

```
lantern_node_api_send(connection, view, status, body, flags)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `connection` | input | u64 in a register |
| `view` | input | `ApiView` |
| `status` | input | u64 in a register |
| `body` | input | u64 in a register |
| `flags` | input | u64 in a register |

### Function does

- One API_SEND of the connection with last 1 at the end of the actions: the response of lantern_api_respond; when it does not fit, the error 500.
- With `API_R_CLOSE`, then an API_CLOSE.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 64 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_send`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `connection`, `view`, `status`, `body`, `flags`.

## Function `lantern_node_api_sent`

Takes a NODE_EV_API_SENT event.

### Signature

```
lantern_node_api_sent(connection)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `connection` | input | u64 in a register |

### Function does

- An event stream's `sent` becomes 0; another stream gets its next chunk, unless one is queued.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_sent`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `connection`.

## Function `lantern_node_api_sidecar_stream`

Starts the sidecar stream of a block.

### Signature

```
lantern_node_api_sidecar_stream(connection, route, flags, view) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `connection` | input | u64 in a register |
| `route` | input | [`ApiRoute`](#type-apiroute) |
| `flags` | input | u64 in a register: the answer flags |
| `view` | input | `ApiView` |

### Returns

- 0: started.
- 400: a block whose slot's fork is not the operation's.

### Function does

- Starts the sidecar stream of the block of the view (node.md, NODE_EV_API).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 80 bytes on x86-64 (return address included), 80 bytes on ARM64, 80 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_sidecar_stream`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `connection`, `route`, `flags`, `view`.

## Function `lantern_node_api_state`

Finds the state of a state_id.

### Signature

```
lantern_node_api_state(route, view) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `route` | input | [`ApiRoute`](#type-apiroute) |
| `view` | output | `ApiView` |

### Returns

- 0: the view holds the state.
- 404: the node keeps no such state.
- 1: the request waits for the replay.

### Function does

- Writes into the view (lantern_node_api_event): look_state, a state the node keeps, at look_state_slot; head_slot the slot it goes to; head_finalized and is_optimistic.
- With `look_replay` 1, which goes to 0: a block at or below F's slot with no post-state comes from the replay (node.md).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_state`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the store in x20, rbp, s2; the actions in x24, r15, s6.
- Argument order: `route`, `view`.

## Function `lantern_node_api_state_answer`

Answers a state operation.

### Signature

```
lantern_node_api_state_answer(connection, route, flags, view) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `connection` | input | u64 in a register |
| `route` | input | [`ApiRoute`](#type-apiroute) |
| `flags` | input | u64 in a register: the answer flags |
| `view` | input | `ApiView`, its state found by lantern_node_api_state |

### Returns

- 0: answered.
- Else the status of an error.

### Function does

- The state at head_slot, then a stream or a work.
- A validator operation's ids: `look_data` when it is not 0, else the route's.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_state_answer`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `connection`, `route`, `flags`, `view`.

## Function `lantern_node_api_stream`

Starts the stream of getBlockV2, getStateV2 or a validator operation.

### Signature

```
lantern_node_api_stream(connection, route, flags, view) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `connection` | input | u64 in a register |
| `route` | input | [`ApiRoute`](#type-apiroute) |
| `flags` | input | u64 in a register: `API_STREAM_CLOSE` and `API_STREAM_HTTP10` |
| `view` | input | `ApiView`: the lookup |

### Returns

- 0: started.
- Else the status of the error to answer.

### Function does

- Starts the stream of the lookup in the view (node.md, NODE_EV_API).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_stream`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `connection`, `route`, `flags`, `view`.

## Function `lantern_node_api_submit`

Starts a pool POST.

### Signature

```
lantern_node_api_submit(connection, route, flags, request, view) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `connection` | input | u64 in a register |
| `route` | input | [`ApiRoute`](#type-apiroute) |
| `flags` | input | u64 in a register: the answer flags |
| `request` | input | [`HttpRequest`](#type-httprequest) |
| `view` | input | `ApiView` |

### Returns

- 0: queued.
- Else the status of the error to answer.

### Function does

- A BYTES_PUT of the body and a NODE_WORK_API_SUBMIT (node.md, NODE_EV_API).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 80 bytes on x86-64 (return address included), 96 bytes on ARM64, 80 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_submit`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `connection`, `route`, `flags`, `request`, `view`.

## Function `lantern_node_api_submit_done`

Takes the end of a NODE_WORK_API_SUBMIT.

### Signature

```
lantern_node_api_submit_done(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | `NodeEvent` of kind `NODE_EV_WORK_DONE` |

### Function does

- The body's bytes go (node.md, lantern_node_step).
- Each valid operation joins the pool, goes out on its topic with `NODE_FLAG_SUBSCRIBED`, and an attester slashing to fork choice.
- Then the answer to the connection.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_submit_done`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the store in x20, rbp, s2; the scratch in x23, r14, s5; the actions in x24, r15, s6.
- Argument order: `event`.

## Function `lantern_node_api_submit_run`

The NODE_WORK_API_SUBMIT work of lantern_node_run.

### Signature

```
lantern_node_api_submit_run(node, store, seen, work, state_a, data, scratch, event, room) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `node` | input | the node |
| `store` | input | `Store` |
| `seen` | input | the seen of lantern_node_run |
| `work` | input | `NodeAction` of the work |
| `state_a` | input | `BeaconState` |
| `data` | input | the body's bytes |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `event` | output | `NodeEvent` |
| `room` | input | u64 in a register: the bytes of the event's buffer |

### Returns

- As lantern_node_run.

### Function does

- Decodes the operations of the body as records at `NodeEvent_chunk` of the event, then checks each with lantern_node_gossip of the fork `arg` / 2^16 with `seen` (node.md, NODE_WORK_API_SUBMIT).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 480 bytes on x86-64 (return address included), 464 bytes on ARM64, 464 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_submit_run`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It takes `room` in x8, rax, t0.
- Argument order: `node`, `store`, `seen`, `work`, `state_a`, `data`, `scratch`, `event`, `room`.

## Function `lantern_node_api_subscribe`

Starts an eventstream.

### Signature

```
lantern_node_api_subscribe(connection, route, flags)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `connection` | input | u64 in a register |
| `route` | input | [`ApiRoute`](#type-apiroute) |
| `flags` | input | u64 in a register: the answer flags |

### Function does

- A NodeApi entry of the route's topics, and a SEND of the head with last 0; its bytes are the entry's `sent` (node.md, NODE_EV_API).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_subscribe`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `connection`, `route`, `flags`.

## Function `lantern_node_api_subscribed`

Whether an eventstream has a topic.

### Signature

```
lantern_node_api_subscribed(topic) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `topic` | input | u64 in a register |

### Function does

- Returns 1 when a NodeApi entry of eventstream has the topic, else 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_subscribed`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x13; rax, rcx, rdx, r10; a0, a7, t0 to t3.
- Argument order: `topic`.

## Function `lantern_node_api_sync_fold`

Folds a pool sync committee message into the contribution of a stream.

### Signature

```
lantern_node_api_sync_fold(scratch, data, state) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `data` | input | the pool entry's bytes: a `SyncCommitteeMessage` |
| `state` | input | `BeaconState`: the head's post-state |

### Returns

- 0: done.
- 1: bytes of another size, no state, or a signature crypto_bls_aggregate rejects.
- 2: a short scratch.

### Function does

- Folds the message into the contribution in the cursor at `NodeEvent_api` + 16 of the event (node.md, produceSyncCommitteeContribution).
- With the beacon_block_root at byte 0, and none of its places in the subcommittee `filter_index` (lantern_node_sync_positions) set in the bits at byte 144: each place is set, and its signature added at byte 48 once for each by crypto_bls_aggregate.
- Byte 32 counts them.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_sync_fold`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the stream registers of lantern_api_stream_json.
- On ARM64 it takes the bytes in x21 and the state in x20.
- Argument order: `scratch`, `data`, `state`.

## Function `lantern_node_api_validators_prep`

Selects the validators of a chunk of a validator stream.

### Signature

```
lantern_node_api_validators_prep(scratch, state, data) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `state` | input | `BeaconState` |
| `data` | input | ByteList of [`ValidatorRef`](#type-validatorref) items, or 0 |

### Returns

- 0: the cursor is ready.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Function does

- At the cursor at `NodeEvent_api` + 16 of the event (node.md, NODE_WORK_API_CHUNK): +16 a bitmap, in `scratch`, of the validators of the state that the items name (0 with no data); +24 the epoch of the state's slot; +40 the count of the validators selected.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 80 bytes on x86-64 (return address included), 80 bytes on ARM64, 80 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_validators_prep`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the stream registers of lantern_api_stream_json.
- On ARM64 it takes the state in x20 and the data in x21.
- Argument order: `scratch`, `state`, `data`.

## Function `lantern_node_api_view`

Fills an ApiView from the node and the store.

### Signature

```
lantern_node_api_view(view)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `view` | output | `ApiView` |

### Function does

- Writes the values of the view that the node and the store give (lantern_node_api_event); the header and the checkpoints zero.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_view`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the store in x20, rbp, s2.
- Argument order: `view`.

## Function `lantern_node_blob_advance`

Moves a blob stream past an item.

### Signature

```
lantern_node_blob_advance(entry)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the `NodeApi` entry |

### Function does

- After a chunk that ended its item (node.md, NODE_EV_API, the blob stream): deneb and electra, the sidecar from `member` + 1 on.
- Fulu: the next cell, of blob `filter_slot` + 1 and column 0 after `API_STREAM_BLOB_SKIP` or the first half's last column, else of column `member` + 1, with `sent` 0.
- `API_STREAM_BLOB_SKIP` clears.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_blob_advance`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Argument order: `entry`.

## Function `lantern_node_headers_next`

The next item of a getBlockHeaders stream.

### Signature

```
lantern_node_headers_next(entry, position) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the `NodeApi` entry |
| `position` | input | u64 in a register |

### Function does

- Finds the item at or after the position (node.md, NODE_EV_API, an item of getBlockHeaders): position 0 the Db's block of the query, i + 1 the NodeBlock at index i.
- Writes its slot (the position), data, state, member (1 on the chain, + 2 optimistic, + 4 finalized) and its root at byte 0 of the cursor.
- Returns 1, or 0 with data and state 0 for none.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_headers_next`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the store in x20, rbp, s2.
- Argument order: `entry`, `position`.

## Function `lantern_node_op_event`

Queues the event of a valid operation.

### Signature

```
lantern_node_op_event(topic, bytes, fork)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `topic` | input | u64 in a register: the gossip topic |
| `bytes` | input | u64 in a register: the BufferId of its bytes |
| `fork` | input | u64 in a register |

### Function does

- A NODE_WORK_API_EVENT of its event topic when an entry has the topic (node.md, The events).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_op_event`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `topic`, `bytes`, `fork`.

## Function `lantern_node_pool_attestation`

The electra Attestation of a pool SingleAttestation.

### Signature

```
lantern_node_pool_attestation(scratch, single, member) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `single` | input | ByteList: a `SingleAttestation` |
| `member` | input | u64 in a register |

### Returns

- 0: the Attestation is a ByteList at the end of `scratch`.
- 1: bytes of another size, a place not below the length, a length above `MAX_VALIDATORS_PER_COMMITTEE`, or a committee_index not below `MAX_COMMITTEES_PER_SLOT`.
- 2: `scratch` has fewer than `NODE_POOL_ATTESTATION_ROOM` bytes.

### Function does

- Writes aggregation_bits of the length `member` / 2^16 with the bit of the place `member` % 2^16, data, signature, and committee_bits with the bit of committee_index (node.md, NODE_WORK_API_CHUNK, the pool streams).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 64 bytes on x86-64 (return address included), 64 bytes on ARM64, 64 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_pool_attestation`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `scratch`, `single`, `member`.

## Function `lantern_node_pool_kind`

The lantern_node_json kind of a pool operation.

### Signature

```
lantern_node_pool_kind(topic) -> kind
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `topic` | input | u64 in a register: the gossip topic |

### Function does

- Returns the lantern_node_json kind of the pool operation of the topic.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_pool_kind`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64 and RISC-V: x0, x9; a0, t0.
- Argument order: `topic`.

## Function `lantern_node_pool_next`

The next pool entry a pool stream answers.

### Signature

```
lantern_node_pool_next(from, entry) -> (index, pool)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `from` | input | u64 in a register: a pool index |
| `entry` | input | the `NodeApi` entry |

### Function does

- Returns the index of the first pool entry from `from` that the stream answers, and the entry (node.md, NODE_EV_API): of its topic; for getPoolAttesterSlashingsV2 and getPoolAttestationsV2, of the type of its fork; for getPoolAttestationsV2, of its filters.
- Returns 2^64 - 1 with none.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_pool_next`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Registers it changes, on ARM64, x86-64, RISC-V: x0 to x2, x9 to x14; rax, rdx, rcx, r8 to r11; a0, a1, a7, t0 to t6.
- Argument order: `from`, `entry`.

## Function `lantern_node_produce_answer`

Starts the answer of a produceBlockV3 entry.

### Signature

```
lantern_node_produce_answer(entry)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the `NodeApi` entry, its block's bytes its data |

### Function does

- Queues its first chunk.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_produce_answer`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `entry`.

## Function `lantern_node_produce_bid_go`

Moves a produceBlockV3 entry on from NODE_PRODUCE_BID.

### Signature

```
lantern_node_produce_bid_go(entry)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the `NodeApi` entry, in `NODE_PRODUCE_BID` with no call in flight |

### Function does

- With the builder's answer at `PRODUCE_BID`, a PRODUCE_BID work of it; else the build (node.md, Block production).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_produce_bid_go`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `entry`.

## Function `lantern_node_produce_build`

Starts the build of a produceBlockV3 entry.

### Signature

```
lantern_node_produce_build(entry)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the `NodeApi` entry |

### Function does

- `NODE_PRODUCE_BUILD` and its PRODUCE_BLOCK work of the copy, the engine's result, the draft, and the bid at `PRODUCE_BID` as `state_c` (node.md, Block production).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_produce_build`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `entry`.

## Function `lantern_node_produce_done`

Takes the end of a work of block production.

### Signature

```
lantern_node_produce_done(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | `NodeEvent` of kind `NODE_EV_WORK_DONE` |

### Function does

- The produceBlockV3 entry at its target goes on, or answers its error (node.md, Block production).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_produce_done`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the store in x20, rbp, s2; the scratch in x23, r14, s5; the actions in x24, r15, s6.
- Argument order: `event`.

## Function `lantern_node_produce_due`

Moves on the produceBlockV3 entries that wait for a bid.

### Signature

```
lantern_node_produce_due()
```

### Function does

- At a quiet point, each entry in `NODE_PRODUCE_BID` with no work in flight (node.md, Block production): a header call in flight past `BUILDER_PROPOSAL_DELAY_TOLERANCE_MS` answers no entry.
- With no call in flight, the entry goes on while the actions have room for two works.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_produce_due`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.

## Function `lantern_node_produce_fail`

Answers an error to a produceBlockV3 entry and ends it.

### Signature

```
lantern_node_produce_fail(entry, status)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the `NodeApi` entry |
| `status` | input | u64 in a register: the error |

### Function does

- Answers the error, then ends the entry: its draft and engine result go, and its state with `API_STREAM_OWN_STATE`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_produce_fail`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `entry`, `status`.

## Function `lantern_node_produce_next`

Queues the next work of a produceBlockV3 entry in NODE_PRODUCE_FOLD.

### Signature

```
lantern_node_produce_next(entry)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the `NodeApi` entry |

### Function does

- A PRODUCE_FOLD of the next kept pool entry of the kind at cursor + 144, from index `filter_slot`, the kinds in the order of `api_produce_kinds`.
- After the last: `NODE_PRODUCE_BUILD` and its PRODUCE_BLOCK.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_produce_next`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `entry`.

## Function `lantern_node_produce_release`

Frees the draft and engine result of a produceBlockV3 entry.

### Signature

```
lantern_node_produce_release(entry)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the `NodeApi` entry |

### Function does

- The draft and the engine's result go.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_produce_release`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `entry`.

## Function `lantern_node_proposer_put`

Keeps a ProposerPreparation.

### Signature

```
lantern_node_proposer_put(preparation)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `preparation` | input | a `ProposerPreparation` |

### Function does

- The NodeProposer of its validator_index takes its fee_recipient, and the store's epoch + 3 as until_epoch (beacon-APIs prepareBeaconProposer).
- With none: the first entry whose until_epoch is at most that epoch, else a new one when the part has room; else none.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_proposer_put`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the store in x20, rbp, s2.
- Argument order: `preparation`.

## Function `lantern_node_publish`

Publishes SSZ bytes on a gossip topic.

### Signature

```
lantern_node_publish(topic, bytes, subnet)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `topic` | input | u64 in a register |
| `bytes` | input | ByteList |
| `subnet` | input | u64 in a register |

### Function does

- A LIBP2P_EVENT_PUBLISH at the end of `p2p_out`; none when it does not fit (node.md, the publish).
- Its data compresses in place, its ByteList head in the 24 bytes before the data.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 336 bytes on x86-64 (return address included), 304 bytes on ARM64, 304 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_publish`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the store in x20, rbp, s2.
- Argument order: `topic`, `bytes`, `subnet`.

## Function `lantern_node_publish_answer`

Answers a publishBlockV2 entry and ends it.

### Signature

```
lantern_node_publish_answer(entry, status)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the `NodeApi` entry |
| `status` | input | u64 in a register: 200, 202, or an error |

### Function does

- Answers the status, then ends the entry; with `API_STREAM_GONE`, no answer.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_publish_answer`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `entry`, `status`.

## Function `lantern_node_publish_check_work`

Queues the PUBLISH_CHECK of a publishBlockV2 entry.

### Signature

```
lantern_node_publish_check_work(entry) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the `NodeApi` entry |

### Returns

- 0: the work went.
- 400: no post-state of the parent.
- 500: no head post-state.

### Function does

- Queues the check (node.md, NODE_PUBLISH_CHECK).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_publish_check_work`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `entry`.

## Function `lantern_node_publish_done`

Takes the end of a work of block publishing.

### Signature

```
lantern_node_publish_done(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | `NodeEvent` of kind `NODE_EV_WORK_DONE` |

### Function does

- The publishBlockV2 entry at its target goes on, or answers (node.md, Block publishing).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_publish_done`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the store in x20, rbp, s2; the scratch in x23, r14, s5; the actions in x24, r15, s6.
- Argument order: `event`.

## Function `lantern_node_publish_drop`

Frees the ids of a publishBlockV2 entry but the block's bytes.

### Signature

```
lantern_node_publish_drop(entry)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the `NodeApi` entry |

### Function does

- Its body and sidecars go.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_publish_drop`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `entry`.

## Function `lantern_node_publish_end`

Ends a publishBlockV2 entry.

### Signature

```
lantern_node_publish_end(entry)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the `NodeApi` entry |

### Function does

- The entry ends with its ids; its builder call in flight answers no entry.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_publish_end`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `entry`.

## Function `lantern_node_publish_poll`

Answers the publishBlockV2 entries whose import ended.

### Signature

```
lantern_node_publish_poll()
```

### Function does

- After the head (node.md, NODE_PUBLISH_IMPORT), each entry whose block's import ended answers: 200 for a block the node imported, 202 for another.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_publish_poll`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.

## Function `lantern_node_publish_sidecar_done`

Takes the end of a valid PUBLISH_SIDECAR of a publishBlockV2 entry.

### Signature

```
lantern_node_publish_sidecar_done(entry, event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the `NodeApi` entry |
| `event` | input | `NodeEvent` of kind `NODE_EV_WORK_DONE` |

### Function does

- The sidecar stays as a NodeBlob when the node keeps it (each blob sidecar; the column sidecars it samples).
- It goes out on its subnet's topic with `NODE_FLAG_SUBSCRIBED`.
- Then the next sidecar.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_publish_sidecar_done`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the scratch in x23, r14, s5; the actions in x24, r15, s6.
- Argument order: `entry`, `event`.

## Function `lantern_node_publish_sidecar_work`

Queues the PUBLISH_SIDECAR of the next sidecar.

### Signature

```
lantern_node_publish_sidecar_work(entry)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the `NodeApi` entry in `NODE_PUBLISH_IMPORT` |

### Function does

- Queues the PUBLISH_SIDECAR of the next sidecar (cursor + 40).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_publish_sidecar_work`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `entry`.

## Function `lantern_node_publish_sidecars_work`

Queues the PUBLISH_SIDECARS of a publishBlockV2 entry.

### Signature

```
lantern_node_publish_sidecars_work(entry)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the `NodeApi` entry |

### Function does

- A BYTES_NEW of the sidecars' room, its id the entry's `filter_index`, then the work (node.md, NODE_PUBLISH_SIDECARS).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_publish_sidecars_work`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `entry`.

## Function `lantern_node_recon_sidecar_done`

Takes the end of a PUBLISH_SIDECAR of the reconstruction.

### Signature

```
lantern_node_recon_sidecar_done(event)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | `NodeEvent` of kind `NODE_EV_WORK_DONE` |

### Function does

- `recon_state` 2 (node.md, the reconstruction).
- A valid sidecar stays as a NodeBlob when the node lacks it, and goes out on its subnet's topic with `NODE_FLAG_SUBSCRIBED`, for a column of `columns` and `recon_slot` above F's slot.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_recon_sidecar_done`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the store in x20, rbp, s2; the actions in x24, r15, s6.
- Argument order: `event`.

## Function `lantern_node_replay_block`

Queues the REPLAY work of a block of the replay.

### Signature

```
lantern_node_replay_block(data, slot)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `data` | input | u64 in a register: the BufferId of the block's bytes |
| `slot` | input | u64 in a register: the block's slot |

### Function does

- The copy of the replay in flight crosses the fork boundaries to the slot, then a NODE_WORK_REPLAY of it with the block's bytes (node.md, the replay).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_replay_block`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `data`, `slot`.

## Function `lantern_node_replay_due`

Queues the next blocks of the replay in flight.

### Signature

```
lantern_node_replay_due()
```

### Function does

- At most `NODE_REPLAY_CHUNK`, the first always and the others while the actions have room for 1024 bytes more (node.md, the replay).
- The Db's blocks below `db_next_slot`, then the NodeBlock path from `replay_root`, a list at the end of the scratch.
- Once it is queued whole, `replay_state` takes the copy and the entries that wait run again.
- A block it cannot find ends it, and they run again with no replay.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_replay_due`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the store in x20, rbp, s2; the scratch in x23, r14, s5; the actions in x24, r15, s6.

## Function `lantern_node_replay_get`

The post-state of a block at a slot by the replay.

### Signature

```
lantern_node_replay_get(root, slot) -> (id, slot)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `root` | input | Bytes32, or 0 for the base |
| `slot` | input | u64 in a register |

### Function does

- Returns a copy of the post-state of the block of the root at the slot, at or below F's slot and at or above `base_slot`, and its slot (node.md, the replay).
- Returns 1 when the request waits for the replay, 0 for none.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_replay_get`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- On ARM64 it reads the view in x22.
- Argument order: `root`, `slot`.

## Function `lantern_node_sidecar_next`

The next sidecar of a sidecar stream.

### Signature

```
lantern_node_sidecar_next(entry, index) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | the `NodeApi` entry |
| `index` | input | u64 in a register |

### Function does

- Finds the sidecar from the index on (node.md, NODE_EV_API, a sidecar of a sidecar stream): member, data, `sent` 0 and a zero cursor.
- Returns 1, or 0 with data 0 for none.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_sidecar_next`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Argument order: `entry`, `index`.

## Function `lantern_node_sidecar_of`

The data of a sidecar of a block.

### Signature

```
lantern_node_sidecar_of(root, slot, index) -> data
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `root` | input | Bytes32 |
| `slot` | input | u64 in a register |
| `index` | input | u64 in a register |

### Function does

- Returns the data of the sidecar of the index of the block, as a sidecar stream finds it (node.md): the `NODE_BLOB_VALID` entry's bytes, else with `NODE_FLAG_DB` the `NODE_DB_REF` of the Db's record; 0 with none.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_sidecar_of`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Argument order: `root`, `slot`, `index`.

## Function `lantern_node_submit_check`

Checks the records of a NODE_WORK_API_SUBMIT.

### Signature

```
lantern_node_submit_check(event, size) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | `NodeEvent` of kind `NODE_EV_WORK_DONE` |
| `size` | input | u64 in a register |

### Function does

- Returns 0 when the event holds its records inside it (node.md): a ByteList at `NodeEvent_chunk` of offset 24, and `NodeEvent_index` records in its bytes, each a code and a ByteList of offset 24 whose size is a multiple of 8.
- Else returns 1.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_submit_check`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x15; rax, rdx, rsi; a0 to a6.
- Argument order: `event`, `size`.

## Function `lantern_node_submit_copy`

Copies bytes as a record of lantern_node_api_submit_run.

### Signature

```
lantern_node_submit_copy(bytes, length) -> (status, next)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | `length` bytes |
| `length` | input | u64 in a register |

### Returns

- 0: the record is written.
- 2: too little room.

### Function does

- Writes the record: code and subnet 0, then a ByteList of the bytes, its size to a multiple of 8.
- Gives the next record.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 32 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_submit_copy`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It takes the record and the event's end in x27 and x26, r9 and r10, a5 and a6.
- It gives the next record in x27, rdx, a1.
- Argument order: `bytes`, `length`.

## Function `lantern_node_submit_decode`

Decodes a JSON operation as a record of lantern_node_api_submit_run.

### Signature

```
lantern_node_submit_decode(text, end, kind, fork, fault) -> (status, next)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `text` | input | the JSON text |
| `end` | input | its end |
| `kind` | input | u64 in a register |
| `fork` | input | u64 in a register |
| `fault` | output | [`JsonFault`](#type-jsonfault) |

### Returns

- 0: the record is written.
- 1: the text is no such value.
- 2: too little room.

### Function does

- Decodes the text by lantern_node_json_decode into the record: code and subnet 0, then a ByteList of the SSZ bytes, its size to a multiple of 8.
- Gives the next record.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_submit_decode`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It takes the record and the event's end in x27 and x26, r9 and r10, a5 and a6.
- It reads the scratch in x24, r15, s6.
- It gives the next record in x27, rdx, a1.
- Argument order: `text`, `end`, `kind`, `fork`, `fault`.

## Function `lantern_node_submit_topic`

The gossip topic of a pool POST.

### Signature

```
lantern_node_submit_topic(op) -> topic
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `op` | input | u64 in a register: the operation |

### Function does

- Returns the gossip topic of the pool POST, or 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_submit_topic`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64 and RISC-V: x0, x9; a0, t0, t1.
- Argument order: `op`.

## Function `lantern_submit_ws`

Skips JSON white space of a submitted body.

### Signature

```
lantern_submit_ws(cursor) -> cursor
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `cursor` | input | a byte of the text |

### Function does

- Returns the cursor past the JSON white space (space, tab, LF, CR) before the text's end.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_submit_ws`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It takes the end in x28, rsi, s10, and returns the cursor in x0, rdi, a0.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9; rax, rdi; a0, t0, t1.
- Argument order: `cursor`.

## Type `ApiIdentity`

The texts of the node's identity that the shell knows. A text is a u64 length, then its room of bytes; its bytes are `0x21` to `0x7e`, but `"` and `\`.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `peer_id` | text of 64 bytes | Base58btc of the libp2p peer ID |
| 72 | `enr` | text of 512 bytes | `enr:` and base64url of the node record |
| 592 | `p2p_address` | text of 128 bytes | A multiaddr of libp2p, or empty |
| 728 | `discovery_address` | text of 128 bytes | A multiaddr of discv5, or empty |
| 864 | `version` | text of 64 bytes | |
| 936 | | | Size: `API_IDENTITY_SIZE` |

## Type `ApiRoute`

The operation of one request and its parameters, by lantern_api_route.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the buffer, this field included |
| 8 | `status` | u64 | With `LANTERN_INVALID_ROUTE`: the HTTP status to answer |
| 16 | `op` | u64 | `API_OP_*` |
| 24 | `allow` | u64 | The methods of the matched path: bit 0 `GET`, bit 1 `POST` |
| 32 | `fault` | u64 | `API_PARAM_*` of the parameter at fault, or 0 |
| 40 | `present` | u64 | Bit `API_PARAM_*` set for each parameter given |
| 48 | `response` | u64 | `API_TYPE_JSON` (1) or `API_TYPE_SSZ` (2) |
| 56 | `body` | u64 | 0 for `GET`; else `API_TYPE_JSON` or `API_TYPE_SSZ` |
| 64 | `consensus_version` | u64 | `FORK_*` of `Eth-Consensus-Version` |
| 72 | `id_kind` | u64 | `state_id`, `block_id` or `block_root`: `API_ID_HEAD` (1), `API_ID_GENESIS` (2), `API_ID_FINALIZED` (3), `API_ID_JUSTIFIED` (4), `API_ID_SLOT` (5) or `API_ID_ROOT` (6) |
| 80 | `id_slot` | u64 | With `API_ID_SLOT` |
| 88 | `id_root` | Root | With `API_ID_ROOT` |
| 120 | `validator` | [`ValidatorRef`](#type-validatorref) | `validator_id` |
| 184 | `epoch` | u64 | |
| 192 | `slot` | u64 | |
| 200 | `index` | u64 | |
| 208 | `committee_index` | u64 | |
| 216 | `subcommittee_index` | u64 | |
| 224 | `start_period` | u64 | |
| 232 | `count` | u64 | |
| 240 | `syncing_status` | u64 | |
| 248 | `builder_boost_factor` | u64 | |
| 256 | `broadcast_validation` | u64 | 1, 2 or 3 |
| 264 | `statuses` | u64 | `status`: bits `API_STATUS_*` |
| 272 | `peer_states` | u64 | `state`: bits `API_PEER_*` |
| 280 | `peer_directions` | u64 | `direction`: bits `API_DIRECTION_*` |
| 288 | `topics` | u64 | Bits `API_TOPIC_*` |
| 296 | `root` | Root | `parent_root`, `attestation_data_root` or `beacon_block_root` |
| 328 | `randao_reveal` | BLSSignature | |
| 424 | `graffiti` | Bytes32 | |
| 456 | `list` | PartRef | `id` of the query or the body: `ValidatorRef` items; `indices`: u64 items; `versioned_hashes`: Root items |
| 472 | `peer_id` | PartRef | The bytes of `peer_id` |

### Rules

- The fixed part is `API_ROUTE_FIXED` (488) bytes.
- An operation takes at most one of `state_id`, `block_id` and `block_root`; one of the three roots; and one list.

## Type `HttpLimits`

The largest request head and body a connection takes.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `head_max` | u64 | Bytes from the start of the connection's bytes to the end of the head, the final CRLF CRLF included |
| 8 | `body_max` | u64 | Bytes of the body, unchunked |

## Type `HttpRequest`

One request, read by lantern_http_request.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the buffer, this field included |
| 8 | `status` | u64 | With `LANTERN_INVALID_HTTP`: the HTTP status to answer |
| 16 | `used` | u64 | Bytes of the connection the request took |
| 24 | `method` | u64 | `HTTP_METHOD_GET`, `HTTP_METHOD_POST` or `HTTP_METHOD_OTHER` |
| 32 | `version` | u64 | 10 for HTTP/1.0, 11 for HTTP/1.1 |
| 40 | `close` | u64 | 1 when the connection closes after the answer |
| 48 | `path` | PartRef | The target up to the first `?` |
| 64 | `query` | PartRef | The target after the first `?` |
| 80 | `accept` | PartRef | The `Accept` value |
| 96 | `content_type` | PartRef | The `Content-Type` value |
| 112 | `consensus_version` | PartRef | The `Eth-Consensus-Version` value |
| 128 | `body` | PartRef | The body |

### Rules

- The fixed part is `HTTP_REQUEST_FIXED` (144) bytes; the parts follow in field order, each holding bytes.
- A field that the request does not hold is a part of count 0.

## Type `JsonCursor`

Where lantern_json_encode goes on: the path from the root type to the current token, and the bytes of that token already written.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `depth` | u64 | Levels in use; 0 before the first byte |
| 8 | `done` | u64 | Bytes of the current token already written |
| 16 | `whole` | u64 | 1 once the JSON is whole |
| 24 | `levels` | 12 `JsonLevel` | The path, the root first |
| 600 | | | Size: `JSON_CURSOR_SIZE` |

### Rules

- A `JsonLevel` is 48 bytes: `node`, the index of the level's `TypeNode` in the type's descriptor; `step`, where the level is (below); `item`, the index of its next item or field; `count`, its items, or the bytes or bits of a byte or bit string; `base`, the offset from `value` of its fields (a container), its first item (a list or vector) or its bytes; `next`, the offset from `value` of its next item when its items are of variable size.
- `step` of a list, vector or container: 0 before `[` or `{`; 1 before its next item, or `]` or `}` after the last; 2 before the name of a field, or before an item after `,`; 3 while the item is written, one level deeper.
- A type has at most 12 levels, as asm-ssz allows.

## Type `JsonFault`

Why and where lantern_json_decode refused a JSON text.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `kind` | u64 | `JSON_FAULT_*`, below |
| 8 | `offset` | u64 | The byte of `json` where the token at fault starts |
| 16 | `size` | u64 | With `LANTERN_BUFFER_TOO_SMALL`: the bytes of the encoding |
| 24 | `depth` | u64 | The path's levels |
| 32 | `path` | 12 u64 | For each level from the root, the field index in its container or the item index in its list or vector |
| 128 | | | Size: `JSON_FAULT_SIZE` |

### Rules

- Kinds: `JSON_FAULT_SYNTAX` (1) a text that is no JSON, or more after the value; `JSON_FAULT_TYPE` (2) a value of another JSON type than the SSZ kind takes; `JSON_FAULT_NUMBER` (3) a uint that is no decimal digits or not below its bound; `JSON_FAULT_HEX` (4) a byte or bit string that is no `0x` and hex digits, or of a wrong length or padding; `JSON_FAULT_LENGTH` (5) an array of a wrong length; `JSON_FAULT_FIELD` (6) a field name the container does not have, or given twice; `JSON_FAULT_MISSING` (7) a field missing at the end of an object, at the offset of its `}`.
- With `JSON_FAULT_SYNTAX` at the top level, `depth` is 0.

## Type `ValidatorRef`

A validator by its index or by its public key.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `kind` | u64 | `API_VALIDATOR_INDEX` (1) or `API_VALIDATOR_PUBKEY` (2) |
| 8 | `index` | u64 | With `API_VALIDATOR_INDEX` |
| 16 | `pubkey` | BLSPubkey | With `API_VALIDATOR_PUBKEY` |
| 64 | | | Size |

## Test vectors

- The answers: the `api` cases of [node.md](node.md#test-vectors), through lantern_node_step and lantern_node_run, and the getBlockV2 and getStateV2 checks of its fork_choice cases in node mode.
- tests/generator/http_request.py: requests and the `HttpRequest` or fault of each, by the rules of lantern_http_request, apart from the assembly. Each case also runs with its bytes cut short at every length (`LANTERN_HTTP_MORE`, or the same fault once the faulty byte is in), and with `out` one byte short. File: `<preset>-phase0-http-request.bin`.
  - Request lines: each method, origin forms with and without a query, both versions, HTTP/2.0 (505), and broken lines.
  - Fields: each read field, names in mixed case, repeated lines joined, white space before a colon, folded lines, no `Host`, two `Host` lines.
  - Bodies: `Content-Length` (zero, exact, past `body_max`, two equal values, two different values), chunked (one and many chunks, extensions, trailers, bad sizes, past `body_max`), both fields together, another coding.
  - Limits: a head of exactly `head_max` bytes and one byte more.
  - Pipelining: two requests in one buffer; `used` ends the first.
- tests/generator/json_codec.py: values of every container type of each fork's spec module (get_random_ssz_object of the pinned spec's test helpers: in minimal the modes zero, one, random and max with lists of at most 4 items and byte lists of at most 64 bytes; in mainnet the mode zero) and the JSON of each, written by the rules of lantern_json_encode, apart from the assembly. The runner reads each value with the type of the fork's type table of that name, when lantern has it, and counts the others in a NOTE; each case also runs in chunks of 1, 7 and 64 bytes of room, and with `out` one byte short of the whole JSON (`LANTERN_JSON_MORE`), then with no room (`LANTERN_BUFFER_TOO_SMALL`). The runner also gives each case's SSZ bytes to lantern_json_encode_ssz, in the same rooms. File: `<preset>-<fork>-json-encode.bin`.
- tests/generator/json_codec.py also makes the cases of lantern_json_decode: the JSON of each `json-encode` case, with white space between its tokens and its fields in reverse order in a second copy, must give the case's SSZ bytes; then for some types, texts that break one rule each, with the `JsonFault` of each (its kind, offset and path). Each valid case also runs with `out` one byte short. File: `<preset>-<fork>-json-decode.bin`.
- tests/generator/api_route.py: requests and the `ApiRoute` or fault of each, by the rules of lantern_api_route, apart from the assembly. It reads the operations from the beacon-APIs clone at the pinned commit, so the table of the assembly is checked against the spec; a parameter of the spec that the rules below do not name stops it. Each case with `LANTERN_OK` also runs with `out` one byte short. File: `<preset>-phase0-api-route.bin`.
  - Every operation: its method and path with every required parameter; then each optional parameter.
  - Every path: each other method (405, `allow`), a trailing `/`, a missing and an extra segment (404).
  - Every parameter: each form of its type, and values that break it (400 and `fault`).
  - Query: repeated names, comma lists, empty items, names the operation does not take, percent-encoding (good and broken), 65 ids (414).
  - Headers: `Accept` with q-values, wildcards, parameters and broken items (406); `Content-Type` (415); `Eth-Consensus-Version` of each fork, missing and wrong (400).

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_api_route`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_http_request`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_json_decode`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_json_encode`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_json_encode_ssz`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |
