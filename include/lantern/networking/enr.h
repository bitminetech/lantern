#ifndef LANTERN_ENR_H
#define LANTERN_ENR_H

#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

struct lantern_enr_key_value {
    const uint8_t *key;
    size_t key_len;
    const uint8_t *value;
    size_t value_len;
};

struct lantern_enr_record {
    char *encoded;
    uint8_t *rlp_bytes;
    size_t rlp_len;
    const uint8_t *signature;
    size_t signature_len;
    uint64_t sequence;
    struct lantern_enr_key_value *pairs;
    size_t pair_count;
};

struct lantern_enr_record_list {
    struct lantern_enr_record *records;
    size_t count;
    size_t capacity;
};

struct lantern_enr_eth2_data {
    uint8_t fork_digest[4];
    uint8_t next_fork_version[4];
    uint64_t next_fork_epoch;
};

void lantern_enr_record_init(struct lantern_enr_record *record);
void lantern_enr_record_reset(struct lantern_enr_record *record);
int lantern_enr_record_decode(const char *enr_text, struct lantern_enr_record *record);
const struct lantern_enr_key_value *lantern_enr_record_find(const struct lantern_enr_record *record, const char *key);
bool lantern_enr_record_is_valid(const struct lantern_enr_record *record);
int lantern_enr_record_signature_valid(const struct lantern_enr_record *record, bool *out_valid);
int lantern_enr_record_node_id(const struct lantern_enr_record *record, uint8_t out_node_id[32]);
int lantern_enr_record_ip4(const struct lantern_enr_record *record, char *buffer, size_t buffer_len);
int lantern_enr_record_ip6(const struct lantern_enr_record *record, char *buffer, size_t buffer_len);
int lantern_enr_record_multiaddr(const struct lantern_enr_record *record, char *buffer, size_t buffer_len);
int lantern_enr_record_eth2(const struct lantern_enr_record *record, struct lantern_enr_eth2_data *out_eth2);
bool lantern_enr_record_is_aggregator(const struct lantern_enr_record *record);

void lantern_enr_record_list_init(struct lantern_enr_record_list *list);
void lantern_enr_record_list_reset(struct lantern_enr_record_list *list);
int lantern_enr_record_list_append(struct lantern_enr_record_list *list, const char *enr_text);
int lantern_enr_record_build_v4(
    struct lantern_enr_record *record,
    const uint8_t private_key[32],
    const char *ip_string,
    uint16_t udp_port,
    uint64_t sequence,
    bool is_aggregator);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_ENR_H */
