#ifndef LANTERN_TEST_DRIVER_DRIVER_H
#define LANTERN_TEST_DRIVER_DRIVER_H

#include <stddef.h>

int lantern_test_driver_fork_choice_init(
    const char *body,
    size_t body_len,
    char **out_error);

int lantern_test_driver_fork_choice_step(
    const char *body,
    size_t body_len,
    char **out_body,
    size_t *out_body_len);

int lantern_test_driver_state_transition_run(
    const char *body,
    size_t body_len,
    char **out_body,
    size_t *out_body_len);

int lantern_test_driver_verify_signatures_run(
    const char *body,
    size_t body_len,
    char **out_body,
    size_t *out_body_len);

#endif /* LANTERN_TEST_DRIVER_DRIVER_H */
