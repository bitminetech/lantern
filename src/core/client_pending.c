/**
 * @file client_pending.c
 * @brief Pending and persisted block list management
 *
 * Implements list operations for pending blocks (waiting for parent)
 * and persisted blocks (stored for replay).
 *
 * @note Thread safety: List functions require caller to hold pending_lock
 *       unless otherwise noted.
 */

#include "client_internal.h"

#include <stdlib.h>
#include <string.h>


/* ============================================================================
 * Block Cloning
 * ============================================================================ */

/**
 * Clone a signed block.
 *
 * @param source  Source block to clone
 * @param dest    Destination block (will be initialized)
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int clone_signed_block(const LanternSignedBlock *source, LanternSignedBlock *dest)
{
    if (!source || !dest)
    {
        return -1;
    }

    lantern_signed_block_with_attestation_init(dest);
    dest->message.block.slot = source->message.block.slot;
    dest->message.block.proposer_index = source->message.block.proposer_index;
    dest->message.block.parent_root = source->message.block.parent_root;
    dest->message.block.state_root = source->message.block.state_root;

    if (lantern_attestations_copy(
            &dest->message.block.body.attestations,
            &source->message.block.body.attestations) != 0)
    {
        lantern_signed_block_with_attestation_reset(dest);
        return -1;
    }

    dest->message.proposer_attestation = source->message.proposer_attestation;

    if (lantern_block_signatures_copy(&dest->signatures, &source->signatures) != 0)
    {
        lantern_signed_block_with_attestation_reset(dest);
        return -1;
    }

    return 0;
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
 * @return 0 on success, -1 on failure
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
        return -1;
    }

    if (list->length == list->capacity)
    {
        size_t new_capacity = list->capacity == 0 ? 4u : list->capacity * 2u;
        struct lantern_persisted_block *expanded = realloc(
            list->items,
            new_capacity * sizeof(*expanded));
        if (!expanded)
        {
            return -1;
        }
        list->items = expanded;
        list->capacity = new_capacity;
    }

    struct lantern_persisted_block *entry = &list->items[list->length];
    if (clone_signed_block(block, &entry->block) != 0)
    {
        return -1;
    }
    entry->root = *root;
    list->length += 1;

    return 0;
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
    const char *peer_text)
{
    if (!list || !block || !block_root || !parent_root)
    {
        return NULL;
    }

    if (list->length == list->capacity)
    {
        size_t new_capacity = list->capacity == 0 ? 4u : list->capacity * 2u;
        struct lantern_pending_block *expanded = realloc(
            list->items,
            new_capacity * sizeof(*expanded));
        if (!expanded)
        {
            return NULL;
        }
        list->items = expanded;
        list->capacity = new_capacity;
    }

    struct lantern_pending_block *entry = &list->items[list->length];
    if (clone_signed_block(block, &entry->block) != 0)
    {
        lantern_signed_block_with_attestation_reset(&entry->block);
        memset(entry, 0, sizeof(*entry));
        return NULL;
    }

    entry->root = *block_root;
    entry->parent_root = *parent_root;
    entry->peer_text[0] = '\0';
    entry->parent_requested = false;

    if (peer_text && *peer_text)
    {
        strncpy(entry->peer_text, peer_text, sizeof(entry->peer_text) - 1u);
        entry->peer_text[sizeof(entry->peer_text) - 1u] = '\0';
    }

    list->length += 1u;

    return entry;
}
