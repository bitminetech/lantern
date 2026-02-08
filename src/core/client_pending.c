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

enum
{
    LANTERN_CLIENT_PENDING_OK = 0,
    LANTERN_CLIENT_PENDING_ERR_INVALID_PARAM = -1,
    LANTERN_CLIENT_PENDING_ERR_ALLOC = -2,
    LANTERN_CLIENT_PENDING_ERR_OVERFLOW = -3,
    LANTERN_CLIENT_PENDING_ERR_COPY = -4,
};

static const size_t BLOCK_LIST_INITIAL_CAPACITY = 4u;
static const size_t PARENT_INDEX_INITIAL_CAPACITY = 4u;


/* ============================================================================
 * Helpers
 * ============================================================================ */

/**
 * @brief Ensure the persisted block list can hold at least `required` entries.
 */
static int ensure_persisted_block_list_capacity(
    struct lantern_persisted_block_list *list,
    size_t required)
{
    if (!list)
    {
        return LANTERN_CLIENT_PENDING_ERR_INVALID_PARAM;
    }

    if (list->capacity >= required)
    {
        return LANTERN_CLIENT_PENDING_OK;
    }

    size_t new_capacity = BLOCK_LIST_INITIAL_CAPACITY;
    if (list->capacity > 0)
    {
        size_t half = list->capacity / 2u;
        if (list->capacity > SIZE_MAX - half)
        {
            return LANTERN_CLIENT_PENDING_ERR_OVERFLOW;
        }
        new_capacity = list->capacity + half;
        if (new_capacity < BLOCK_LIST_INITIAL_CAPACITY)
        {
            new_capacity = BLOCK_LIST_INITIAL_CAPACITY;
        }
    }

    if (new_capacity < required)
    {
        new_capacity = required;
    }

    if (new_capacity > SIZE_MAX / sizeof(*list->items))
    {
        return LANTERN_CLIENT_PENDING_ERR_OVERFLOW;
    }

    struct lantern_persisted_block *expanded = realloc(
        list->items,
        new_capacity * sizeof(*expanded));
    if (!expanded)
    {
        return LANTERN_CLIENT_PENDING_ERR_ALLOC;
    }
    list->items = expanded;
    list->capacity = new_capacity;
    return LANTERN_CLIENT_PENDING_OK;
}


/**
 * @brief Ensure the pending block list can hold at least `required` entries.
 */
static int ensure_pending_block_list_capacity(
    struct lantern_pending_block_list *list,
    size_t required)
{
    if (!list)
    {
        return LANTERN_CLIENT_PENDING_ERR_INVALID_PARAM;
    }

    if (list->capacity >= required)
    {
        return LANTERN_CLIENT_PENDING_OK;
    }

    size_t new_capacity = BLOCK_LIST_INITIAL_CAPACITY;
    if (list->capacity > 0)
    {
        size_t half = list->capacity / 2u;
        if (list->capacity > SIZE_MAX - half)
        {
            return LANTERN_CLIENT_PENDING_ERR_OVERFLOW;
        }
        new_capacity = list->capacity + half;
        if (new_capacity < BLOCK_LIST_INITIAL_CAPACITY)
        {
            new_capacity = BLOCK_LIST_INITIAL_CAPACITY;
        }
    }

    if (new_capacity < required)
    {
        new_capacity = required;
    }

    if (new_capacity > SIZE_MAX / sizeof(*list->items))
    {
        return LANTERN_CLIENT_PENDING_ERR_OVERFLOW;
    }

    struct lantern_pending_block *expanded = realloc(
        list->items,
        new_capacity * sizeof(*expanded));
    if (!expanded)
    {
        return LANTERN_CLIENT_PENDING_ERR_ALLOC;
    }
    list->items = expanded;
    list->capacity = new_capacity;
    return LANTERN_CLIENT_PENDING_OK;
}

static int ensure_pending_parent_index_capacity(
    struct lantern_pending_parent_index *index,
    size_t required)
{
    if (!index)
    {
        return LANTERN_CLIENT_PENDING_ERR_INVALID_PARAM;
    }

    if (index->capacity >= required)
    {
        return LANTERN_CLIENT_PENDING_OK;
    }

    size_t new_capacity = PARENT_INDEX_INITIAL_CAPACITY;
    if (index->capacity > 0)
    {
        size_t half = index->capacity / 2u;
        if (index->capacity > SIZE_MAX - half)
        {
            return LANTERN_CLIENT_PENDING_ERR_OVERFLOW;
        }
        new_capacity = index->capacity + half;
        if (new_capacity < PARENT_INDEX_INITIAL_CAPACITY)
        {
            new_capacity = PARENT_INDEX_INITIAL_CAPACITY;
        }
    }

    if (new_capacity < required)
    {
        new_capacity = required;
    }

    if (new_capacity > SIZE_MAX / sizeof(*index->entries))
    {
        return LANTERN_CLIENT_PENDING_ERR_OVERFLOW;
    }

    struct lantern_pending_parent_index_entry *expanded = realloc(
        index->entries,
        new_capacity * sizeof(*expanded));
    if (!expanded)
    {
        return LANTERN_CLIENT_PENDING_ERR_ALLOC;
    }

    index->entries = expanded;
    index->capacity = new_capacity;
    return LANTERN_CLIENT_PENDING_OK;
}

static int ensure_pending_parent_entry_capacity(
    struct lantern_pending_parent_index_entry *entry,
    size_t required)
{
    if (!entry)
    {
        return LANTERN_CLIENT_PENDING_ERR_INVALID_PARAM;
    }

    if (entry->capacity >= required)
    {
        return LANTERN_CLIENT_PENDING_OK;
    }

    size_t new_capacity = PARENT_INDEX_INITIAL_CAPACITY;
    if (entry->capacity > 0)
    {
        size_t half = entry->capacity / 2u;
        if (entry->capacity > SIZE_MAX - half)
        {
            return LANTERN_CLIENT_PENDING_ERR_OVERFLOW;
        }
        new_capacity = entry->capacity + half;
        if (new_capacity < PARENT_INDEX_INITIAL_CAPACITY)
        {
            new_capacity = PARENT_INDEX_INITIAL_CAPACITY;
        }
    }

    if (new_capacity < required)
    {
        new_capacity = required;
    }

    if (new_capacity > SIZE_MAX / sizeof(*entry->child_roots))
    {
        return LANTERN_CLIENT_PENDING_ERR_OVERFLOW;
    }

    LanternRoot *expanded = realloc(entry->child_roots, new_capacity * sizeof(*expanded));
    if (!expanded)
    {
        return LANTERN_CLIENT_PENDING_ERR_ALLOC;
    }

    entry->child_roots = expanded;
    entry->capacity = new_capacity;
    return LANTERN_CLIENT_PENDING_OK;
}

static void pending_parent_index_init(struct lantern_pending_parent_index *index)
{
    if (!index)
    {
        return;
    }
    index->entries = NULL;
    index->length = 0;
    index->capacity = 0;
}

static void pending_parent_index_reset(struct lantern_pending_parent_index *index)
{
    if (!index)
    {
        return;
    }

    if (index->entries)
    {
        for (size_t i = 0; i < index->length; ++i)
        {
            free(index->entries[i].child_roots);
            index->entries[i].child_roots = NULL;
            index->entries[i].length = 0;
            index->entries[i].capacity = 0;
        }
        free(index->entries);
    }

    index->entries = NULL;
    index->length = 0;
    index->capacity = 0;
}

static struct lantern_pending_parent_index_entry *pending_parent_index_find(
    struct lantern_pending_parent_index *index,
    const LanternRoot *parent_root)
{
    if (!index || !parent_root || !index->entries)
    {
        return NULL;
    }

    for (size_t i = 0; i < index->length; ++i)
    {
        if (memcmp(index->entries[i].parent_root.bytes, parent_root->bytes, LANTERN_ROOT_SIZE) == 0)
        {
            return &index->entries[i];
        }
    }

    return NULL;
}

static struct lantern_pending_parent_index_entry *pending_parent_index_ensure(
    struct lantern_pending_parent_index *index,
    const LanternRoot *parent_root)
{
    if (!index || !parent_root)
    {
        return NULL;
    }

    struct lantern_pending_parent_index_entry *entry =
        pending_parent_index_find(index, parent_root);
    if (entry)
    {
        return entry;
    }

    if (index->length == SIZE_MAX)
    {
        return NULL;
    }

    int ensure_rc = ensure_pending_parent_index_capacity(index, index->length + 1u);
    if (ensure_rc != LANTERN_CLIENT_PENDING_OK)
    {
        return NULL;
    }

    entry = &index->entries[index->length];
    memset(entry, 0, sizeof(*entry));
    entry->parent_root = *parent_root;
    index->length += 1u;
    return entry;
}

static void pending_parent_index_add_child(
    struct lantern_pending_parent_index *index,
    const LanternRoot *parent_root,
    const LanternRoot *child_root)
{
    if (!index || !parent_root || !child_root)
    {
        return;
    }
    if (lantern_root_is_zero(parent_root))
    {
        return;
    }

    struct lantern_pending_parent_index_entry *entry =
        pending_parent_index_ensure(index, parent_root);
    if (!entry)
    {
        return;
    }

    for (size_t i = 0; i < entry->length; ++i)
    {
        if (memcmp(entry->child_roots[i].bytes, child_root->bytes, LANTERN_ROOT_SIZE) == 0)
        {
            return;
        }
    }

    if (entry->length == SIZE_MAX)
    {
        return;
    }

    int ensure_rc = ensure_pending_parent_entry_capacity(entry, entry->length + 1u);
    if (ensure_rc != LANTERN_CLIENT_PENDING_OK)
    {
        return;
    }

    entry->child_roots[entry->length] = *child_root;
    entry->length += 1u;
}

static void pending_parent_index_remove_child(
    struct lantern_pending_parent_index *index,
    const LanternRoot *parent_root,
    const LanternRoot *child_root)
{
    if (!index || !parent_root || !child_root || !index->entries)
    {
        return;
    }

    for (size_t i = 0; i < index->length; ++i)
    {
        struct lantern_pending_parent_index_entry *entry = &index->entries[i];
        if (memcmp(entry->parent_root.bytes, parent_root->bytes, LANTERN_ROOT_SIZE) != 0)
        {
            continue;
        }

        for (size_t j = 0; j < entry->length; ++j)
        {
            if (memcmp(entry->child_roots[j].bytes, child_root->bytes, LANTERN_ROOT_SIZE) != 0)
            {
                continue;
            }

            if (j + 1u < entry->length)
            {
                memmove(
                    &entry->child_roots[j],
                    &entry->child_roots[j + 1u],
                    (entry->length - (j + 1u)) * sizeof(*entry->child_roots));
            }
            entry->length -= 1u;

            if (entry->length == 0)
            {
                free(entry->child_roots);
                if (i + 1u < index->length)
                {
                    memmove(
                        &index->entries[i],
                        &index->entries[i + 1u],
                        (index->length - (i + 1u)) * sizeof(*index->entries));
                }
                index->length -= 1u;
                if (index->length < index->capacity)
                {
                    memset(&index->entries[index->length], 0, sizeof(*index->entries));
                }
            }
            return;
        }
        return;
    }
}

static bool pending_parent_index_peek_child(
    struct lantern_pending_parent_index *index,
    const LanternRoot *parent_root,
    LanternRoot *out_child_root)
{
    if (!index || !parent_root || !out_child_root || !index->entries)
    {
        return false;
    }

    struct lantern_pending_parent_index_entry *entry =
        pending_parent_index_find(index, parent_root);
    if (!entry || entry->length == 0)
    {
        return false;
    }

    *out_child_root = entry->child_roots[entry->length - 1u];
    return true;
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
    dest->message.block.slot = source->message.block.slot;
    dest->message.block.proposer_index = source->message.block.proposer_index;
    dest->message.block.parent_root = source->message.block.parent_root;
    dest->message.block.state_root = source->message.block.state_root;

    if (lantern_aggregated_attestations_copy(
            &dest->message.block.body.attestations,
            &source->message.block.body.attestations) != 0)
    {
        lantern_signed_block_with_attestation_reset(dest);
        return LANTERN_CLIENT_PENDING_ERR_COPY;
    }
    dest->message.block.body.legacy_plain_attestation_layout =
        source->message.block.body.legacy_plain_attestation_layout;

    dest->message.proposer_attestation = source->message.proposer_attestation;

    if (lantern_block_signatures_copy(&dest->signatures, &source->signatures) != 0)
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

    int ensure_rc = ensure_persisted_block_list_capacity(list, list->length + 1u);
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
    pending_parent_index_init(&list->parent_index);
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
    pending_parent_index_reset(&list->parent_index);
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
    pending_parent_index_remove_child(
        &list->parent_index,
        &entry->parent_root,
        &entry->root);
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

    int ensure_rc = ensure_pending_block_list_capacity(list, list->length + 1u);
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
    entry->parent_request_failures = 0;
    entry->received_ms = monotonic_millis();
    entry->backfill_depth = backfill_depth;

    if (peer_text && *peer_text)
    {
        strncpy(entry->peer_text, peer_text, sizeof(entry->peer_text) - 1u);
        entry->peer_text[sizeof(entry->peer_text) - 1u] = '\0';
    }

    pending_parent_index_add_child(&list->parent_index, parent_root, block_root);
    list->length += 1u;

    return entry;
}


/**
 * Peek a pending child root for a given parent root.
 *
 * @param list         Pending block list
 * @param parent_root  Parent root to match
 * @param out_child_root Output child root
 * @return true if a child is available, false otherwise
 *
 * @note Thread safety: Caller must hold pending_lock
 */
bool pending_block_list_peek_child_root(
    struct lantern_pending_block_list *list,
    const LanternRoot *parent_root,
    LanternRoot *out_child_root)
{
    if (!list || !parent_root || !out_child_root)
    {
        return false;
    }

    return pending_parent_index_peek_child(&list->parent_index, parent_root, out_child_root);
}
