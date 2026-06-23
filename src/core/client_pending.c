/**
 * @file client_pending.c
 * @brief Pending and persisted block list management
 *
 * Implements list operations for pending blocks (waiting for parent)
 * and persisted blocks (stored for replay).
 *
 * @note Thread safety:
 *       - Pending list functions require caller to hold pending_lock.
 *       - Persisted list helpers are thread-safe.
 */

#include "client_internal.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/support/strings.h"

enum
{
    LANTERN_CLIENT_PENDING_OK = 0,
    LANTERN_CLIENT_PENDING_ERR_INVALID_PARAM = -1,
    LANTERN_CLIENT_PENDING_ERR_ALLOC = -2,
    LANTERN_CLIENT_PENDING_ERR_OVERFLOW = -3,
    LANTERN_CLIENT_PENDING_ERR_COPY = -4,
};

static const size_t BLOCK_LIST_INITIAL_CAPACITY = 4u;


/* ============================================================================
 * Helpers
 * ============================================================================ */

static int grow_item_capacity(
    void *items,
    size_t *capacity,
    size_t required,
    size_t element_size,
    size_t initial_capacity,
    void **out_items)
{
    if (!capacity || !out_items || element_size == 0u || initial_capacity == 0u)
    {
        return LANTERN_CLIENT_PENDING_ERR_INVALID_PARAM;
    }
    *out_items = items;
    if (*capacity >= required)
    {
        return LANTERN_CLIENT_PENDING_OK;
    }

    size_t new_capacity = initial_capacity;
    if (*capacity > 0u)
    {
        size_t half = *capacity / 2u;
        if (*capacity > SIZE_MAX - half)
        {
            return LANTERN_CLIENT_PENDING_ERR_OVERFLOW;
        }
        new_capacity = *capacity + half;
        if (new_capacity < initial_capacity)
        {
            new_capacity = initial_capacity;
        }
    }
    if (new_capacity < required)
    {
        new_capacity = required;
    }
    if (new_capacity > SIZE_MAX / element_size)
    {
        return LANTERN_CLIENT_PENDING_ERR_OVERFLOW;
    }

    void *expanded = realloc(items, new_capacity * element_size);
    if (!expanded)
    {
        return LANTERN_CLIENT_PENDING_ERR_ALLOC;
    }
    *capacity = new_capacity;
    *out_items = expanded;
    return LANTERN_CLIENT_PENDING_OK;
}

#define GROW_ITEMS(owner, field, required, initial_capacity, rc)                         \
    do                                                                                  \
    {                                                                                   \
        void *expanded_items = NULL;                                                    \
        (rc) = grow_item_capacity(                                                      \
            (owner)->field,                                                            \
            &(owner)->capacity,                                                        \
            (required),                                                                 \
            sizeof(*(owner)->field),                                                    \
            (initial_capacity),                                                         \
            &expanded_items);                                                           \
        if ((rc) == LANTERN_CLIENT_PENDING_OK)                                          \
        {                                                                               \
            (owner)->field = expanded_items;                                            \
        }                                                                               \
    } while (0)

/* ============================================================================
 * Pending Vote List
 * ============================================================================ */

/**
 * Initialize a pending vote list.
 *
 * @param list  List to initialize
 *
 * @note Thread safety: This function is thread-safe
 */
void pending_vote_list_init(struct lantern_pending_vote_list *list)
{
    if (!list)
    {
        return;
    }
    list->items = NULL;
    list->length = 0;
    list->capacity = 0;
}


/**
 * Reset and free a pending vote list.
 *
 * @param list  List to reset
 *
 * @note Thread safety: This function is thread-safe
 */
void pending_vote_list_reset(struct lantern_pending_vote_list *list)
{
    if (!list)
    {
        return;
    }
    free(list->items);
    list->items = NULL;
    list->length = 0;
    list->capacity = 0;
}


/**
 * Append a pending gossip vote to the list.
 *
 * @param list      List to append to
 * @param vote      Vote to append
 * @param peer_text Peer ID text (may be NULL)
 * @return Pointer to new entry, or NULL on failure
 *
 * @note Thread safety: Caller must synchronize access
 */
struct lantern_pending_vote *pending_vote_list_append(
    struct lantern_pending_vote_list *list,
    const LanternSignedVote *vote,
    const char *peer_text)
{
    if (!list || !vote)
    {
        return NULL;
    }

    if (list->length >= LANTERN_PENDING_GOSSIP_VOTE_LIMIT
        || list->length == SIZE_MAX)
    {
        return NULL;
    }

    int ensure_rc = LANTERN_CLIENT_PENDING_OK;
    GROW_ITEMS(list, items, list->length + 1u, BLOCK_LIST_INITIAL_CAPACITY, ensure_rc);
    if (ensure_rc != LANTERN_CLIENT_PENDING_OK)
    {
        return NULL;
    }

    struct lantern_pending_vote *entry = &list->items[list->length];
    memset(entry, 0, sizeof(*entry));
    entry->vote = *vote;
    if (peer_text && *peer_text)
    {
        (void)lantern_string_copy(entry->peer_text, sizeof(entry->peer_text), peer_text);
    }
    list->length += 1u;

    return entry;
}


/* ============================================================================
 * Block Cloning
 * ============================================================================ */

/**
 * Clone a signed block.
 *
 * @param source  Source block to clone
 * @param dest    Destination block (will be initialized)
 * @return LANTERN_CLIENT_PENDING_OK on success
 * @return LANTERN_CLIENT_PENDING_ERR_INVALID_PARAM if any parameter is NULL
 * @return LANTERN_CLIENT_PENDING_ERR_COPY if block cloning fails
 *
 * @note Thread safety: This function is thread-safe
 */
int clone_signed_block(const LanternSignedBlock *source, LanternSignedBlock *dest)
{
    if (!source || !dest)
    {
        return LANTERN_CLIENT_PENDING_ERR_INVALID_PARAM;
    }

    lantern_signed_block_with_attestation_init(dest);
    dest->block.slot = source->block.slot;
    dest->block.proposer_index = source->block.proposer_index;
    dest->block.parent_root = source->block.parent_root;
    dest->block.state_root = source->block.state_root;

    if (lantern_aggregated_attestations_copy(
            &dest->block.body.attestations,
            &source->block.body.attestations) != 0)
    {
        lantern_signed_block_with_attestation_reset(dest);
        return LANTERN_CLIENT_PENDING_ERR_COPY;
    }

    if (lantern_byte_list_copy(&dest->proof, &source->proof) != 0)
    {
        lantern_signed_block_with_attestation_reset(dest);
        return LANTERN_CLIENT_PENDING_ERR_COPY;
    }

    return LANTERN_CLIENT_PENDING_OK;
}


/* ============================================================================
 * Persisted Block List
 * ============================================================================ */

/**
 * Initialize a persisted block list.
 *
 * @param list  List to initialize
 *
 * @note Thread safety: This function is thread-safe
 */
void persisted_block_list_init(struct lantern_persisted_block_list *list)
{
    if (!list)
    {
        return;
    }
    list->items = NULL;
    list->length = 0;
    list->capacity = 0;
}


/**
 * Reset and free a persisted block list.
 *
 * @param list  List to reset
 *
 * @note Thread safety: This function is thread-safe
 */
void persisted_block_list_reset(struct lantern_persisted_block_list *list)
{
    if (!list)
    {
        return;
    }
    if (list->items)
    {
        for (size_t i = 0; i < list->length; ++i)
        {
            lantern_signed_block_with_attestation_reset(&list->items[i].block);
        }
        free(list->items);
    }
    list->items = NULL;
    list->length = 0;
    list->capacity = 0;
}


/**
 * Append a persisted block to the list.
 *
 * @param list   List to append to
 * @param block  Block to append
 * @param root   Root of the block
 * @return LANTERN_CLIENT_PENDING_OK on success
 * @return LANTERN_CLIENT_PENDING_ERR_INVALID_PARAM if any parameter is NULL
 * @return LANTERN_CLIENT_PENDING_ERR_OVERFLOW if the list size would overflow
 * @return LANTERN_CLIENT_PENDING_ERR_ALLOC if allocation fails
 * @return LANTERN_CLIENT_PENDING_ERR_COPY if block cloning fails
 *
 * @note Thread safety: This function is thread-safe
 */
int persisted_block_list_append(
    struct lantern_persisted_block_list *list,
    const LanternSignedBlock *block,
    const LanternRoot *root)
{
    if (!list || !block || !root)
    {
        return LANTERN_CLIENT_PENDING_ERR_INVALID_PARAM;
    }

    if (list->length == SIZE_MAX)
    {
        return LANTERN_CLIENT_PENDING_ERR_OVERFLOW;
    }

    int ensure_rc = LANTERN_CLIENT_PENDING_OK;
    GROW_ITEMS(list, items, list->length + 1u, BLOCK_LIST_INITIAL_CAPACITY, ensure_rc);
    if (ensure_rc != LANTERN_CLIENT_PENDING_OK)
    {
        return ensure_rc;
    }

    struct lantern_persisted_block *entry = &list->items[list->length];
    int clone_rc = clone_signed_block(block, &entry->block);
    if (clone_rc != LANTERN_CLIENT_PENDING_OK)
    {
        return clone_rc;
    }
    entry->root = *root;
    list->length += 1;

    return LANTERN_CLIENT_PENDING_OK;
}


/* ============================================================================
 * Pending Block List
 * ============================================================================ */

/**
 * Initialize a pending block list.
 *
 * @param list  List to initialize
 *
 * @note Thread safety: This function is thread-safe
 */
void pending_block_list_init(struct lantern_pending_block_list *list)
{
    if (!list)
    {
        return;
    }
    list->items = NULL;
    list->length = 0;
    list->capacity = 0;
}


/**
 * Reset and free a pending block list.
 *
 * @param list  List to reset
 *
 * @note Thread safety: This function is thread-safe
 */
void pending_block_list_reset(struct lantern_pending_block_list *list)
{
    if (!list)
    {
        return;
    }
    if (list->items)
    {
        for (size_t i = 0; i < list->length; ++i)
        {
            lantern_signed_block_with_attestation_reset(&list->items[i].block);
        }
        free(list->items);
    }
    list->items = NULL;
    list->length = 0;
    list->capacity = 0;
}


/**
 * Find a pending block by root.
 *
 * @param list  List to search
 * @param root  Root to find
 * @return Pointer to entry if found, NULL otherwise
 *
 * @note Thread safety: Caller must hold pending_lock
 */
struct lantern_pending_block *pending_block_list_find(
    struct lantern_pending_block_list *list,
    const LanternRoot *root)
{
    if (!list || !root || !list->items)
    {
        return NULL;
    }

    for (size_t i = 0; i < list->length; ++i)
    {
        if (memcmp(list->items[i].root.bytes, root->bytes, LANTERN_ROOT_SIZE) == 0)
        {
            return &list->items[i];
        }
    }

    return NULL;
}


/**
 * Remove a pending block by index.
 *
 * @param list   List to modify
 * @param index  Index to remove
 *
 * @note Thread safety: Caller must hold pending_lock
 */
void pending_block_list_remove(struct lantern_pending_block_list *list, size_t index)
{
    if (!list || !list->items || index >= list->length)
    {
        return;
    }

    struct lantern_pending_block *entry = &list->items[index];
    lantern_signed_block_with_attestation_reset(&entry->block);

    if (index + 1u < list->length)
    {
        memmove(
            &list->items[index],
            &list->items[index + 1u],
            (list->length - (index + 1u)) * sizeof(*list->items));
    }

    list->length -= 1u;

    if (list->length < list->capacity)
    {
        /* Do NOT call reset here - memmove has moved the dynamic pointers
           from the last entry to an earlier position. Calling reset would
           double-free those pointers. Just zero the leftover slot. */
        memset(&list->items[list->length], 0, sizeof(*list->items));
    }
}


/**
 * Append a pending block to the list.
 *
 * @param list         List to append to
 * @param block        Block to append
 * @param block_root   Root of the block
 * @param parent_root  Root of the parent block
 * @param peer_text    Peer ID text (may be NULL)
 * @return Pointer to new entry, or NULL on failure
 *
 * @note Thread safety: Caller must hold pending_lock
 */
struct lantern_pending_block *pending_block_list_append(
    struct lantern_pending_block_list *list,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternRoot *parent_root,
    const char *peer_text,
    uint32_t backfill_depth)
{
    if (!list || !block || !block_root || !parent_root)
    {
        return NULL;
    }

    if (list->length == SIZE_MAX)
    {
        return NULL;
    }

    int ensure_rc = LANTERN_CLIENT_PENDING_OK;
    GROW_ITEMS(list, items, list->length + 1u, BLOCK_LIST_INITIAL_CAPACITY, ensure_rc);
    if (ensure_rc != LANTERN_CLIENT_PENDING_OK)
    {
        return NULL;
    }

    struct lantern_pending_block *entry = &list->items[list->length];
    if (clone_signed_block(block, &entry->block) != LANTERN_CLIENT_PENDING_OK)
    {
        memset(entry, 0, sizeof(*entry));
        return NULL;
    }

    entry->root = *block_root;
    entry->parent_root = *parent_root;
    entry->peer_text[0] = '\0';
    entry->parent_requested = false;
    entry->parent_requested_ms = 0;
    entry->received_ms = monotonic_millis();
    entry->backfill_depth = backfill_depth;

    if (peer_text && *peer_text)
    {
        (void)lantern_string_copy(entry->peer_text, sizeof(entry->peer_text), peer_text);
    }

    list->length += 1u;

    return entry;
}
