#include "lantern/consensus/duties.h"
#include "lantern/genesis/genesis.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int test_explicit_assignment(void) {
    uint64_t explicit_indices[] = {1, 5, 9};
    struct lantern_validator_config_entry entry = {
        .count = 3,
        .indices = explicit_indices,
        .indices_len = 3,
    };
    struct lantern_validator_assignment assignment;
    if (lantern_validator_assignment_from_config(&entry, &assignment) != 0) {
        fprintf(stderr, "assignment with explicit indices failed\n");
        return 1;
    }
    if (assignment.length != 3) {
        fprintf(stderr, "explicit assignment count mismatch\n");
        lantern_validator_assignment_reset(&assignment);
        return 1;
    }
    if (assignment.indices[0] != 1 || assignment.indices[1] != 5 || assignment.indices[2] != 9) {
        fprintf(stderr, "explicit assignment indices not preserved\n");
        lantern_validator_assignment_reset(&assignment);
        return 1;
    }
    uint64_t local_index = 0;
    if (!lantern_validator_assignment_contains(&assignment, 5, &local_index) || local_index != 1) {
        fprintf(stderr, "explicit assignment containment failed\n");
        lantern_validator_assignment_reset(&assignment);
        return 1;
    }
    if (lantern_validator_assignment_contains(&assignment, 2, NULL)) {
        fprintf(stderr, "unexpected containment for explicit assignment\n");
        lantern_validator_assignment_reset(&assignment);
        return 1;
    }
    lantern_validator_assignment_reset(&assignment);
    return 0;
}

static int test_assignment_parser(void) {
    char template[] = "/tmp/lantern_assignmentsXXXXXX";
    int fd = mkstemp(template);
    if (fd < 0) {
        perror("mkstemp");
        return 1;
    }
    const char *content = "alpha:\n"
                          "  - 0\n"
                          "  - 2\n"
                          "beta:\n"
                          "  - 1\n";
    size_t content_len = strlen(content);
    if ((size_t)write(fd, content, content_len) != content_len) {
        perror("write");
        close(fd);
        unlink(template);
        return 1;
    }
    close(fd);

    struct lantern_validator_config_entry entries[2];
    memset(entries, 0, sizeof(entries));
    entries[0].name = "alpha";
    entries[0].count = 2;
    entries[1].name = "beta";
    entries[1].count = 1;
    struct lantern_validator_config config = {
        .entries = entries,
        .count = 2,
    };

    int rc = lantern_validator_config_apply_assignments(&config, template, 3);
    unlink(template);
    if (rc != 0) {
        fprintf(stderr, "failed to parse assignment mapping\n");
        free(entries[0].indices);
        free(entries[1].indices);
        return 1;
    }
    if (entries[0].indices_len != 2 || entries[1].indices_len != 1) {
        fprintf(stderr, "parsed assignment lengths mismatch\n");
        free(entries[0].indices);
        free(entries[1].indices);
        return 1;
    }
    if (entries[0].indices[0] != 0 || entries[0].indices[1] != 2 || entries[1].indices[0] != 1) {
        fprintf(stderr, "parsed assignment indices unexpected\n");
        free(entries[0].indices);
        free(entries[1].indices);
        return 1;
    }
    free(entries[0].indices);
    free(entries[1].indices);
    return 0;
}

static int test_proposer_selection(void) {
    uint64_t proposer = 0;
    if (lantern_proposer_for_slot(5, 4, &proposer) != 0) {
        fprintf(stderr, "proposer selection failed\n");
        return 1;
    }
    if (proposer != 1) {
        fprintf(stderr, "unexpected proposer index %llu\n", (unsigned long long)proposer);
        return 1;
    }
    if (lantern_proposer_for_slot(3, 0, &proposer) == 0) {
        fprintf(stderr, "expected proposer selection failure with zero validators\n");
        return 1;
    }
    return 0;
}

int main(void) {
    if (test_explicit_assignment() != 0) {
        return 1;
    }
    if (test_assignment_parser() != 0) {
        return 1;
    }
    if (test_proposer_selection() != 0) {
        return 1;
    }
    puts("lantern_duties_test OK");
    return 0;
}
