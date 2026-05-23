#include "client_internal.h"

/*
 * Req/resp stream framing now lives with the networking reqresp service so it
 * can operate on the c-lean-libp2p host stream surface and the unit-test stream
 * adapter through one Lantern-owned abstraction.
 */
