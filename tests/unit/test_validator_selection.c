#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "lantern/genesis/genesis.h"

static void build_fixture_path(char *buffer, size_t length, const char *relative) {
    if (!buffer || length == 0 || !relative) {
        return;
    }
    int written = snprintf(buffer, length, "%s/%s", LANTERN_TEST_FIXTURE_DIR, relative);
    if (written <= 0 || (size_t)written >= length) {
        buffer[0] = '\0';
    }
}

static int write_temp_nodes_file(char *buffer, size_t length) {
    if (!buffer || length == 0) {
        return -1;
    }
    const char *tmpdir = getenv("TMPDIR");
    if (!tmpdir || tmpdir[0] == '\0') {
        tmpdir = "/tmp";
    }
    int written = snprintf(buffer, length, "%s/lantern_validator_nodes_%ld.yaml", tmpdir, (long)getpid());
    if (written <= 0 || (size_t)written >= length) {
        return -1;
    }
    FILE *fp = fopen(buffer, "w");
    if (!fp) {
        perror("fopen nodes file");
        buffer[0] = '\0';
        return -1;
    }
    static const char *kEnrs[] = {
        "enr:-IW4QMn2QUYENcnsEpITZLph3YZee8Y3B92INUje_riQUOFQQ5Zm5kASi7E_IuQoGCWgcmCYrH920Q52kH7tQcWcPhEBgmlkgnY0"
        "gmlwhH8AAAGEcXVpY4IjKIlzZWNwMjU2azGhAhMMnGF1rmIPQ9tWgqfkNmvsG-aIyc9EJU5JFo3Tegys",
        "enr:-IW4QDc1Hkslu0Bw11YH4APkXvSWukp5_3VdIrtwhWomvTVVAS-EQNB-rYesXDxhHA613gG9OGR_AiIyE0VeMltTd2cBgmlkgnY0"
        "gmlwhH8AAAGEcXVpY4IjKYlzZWNwMjU2azGhA5_HplOwUZ8wpF4O3g4CBsjRMI6kQYT7ph5LkeKzLgTS",
        "enr:-IW4QGrhos4INy6JB19eJIPA7IEi7seQABUthj_PjNNoOb7WbvNBMGreEncC5Kim-2cup44-50mjuqoAMjivr7I7mG8BgmlkgnY0"
        "gmlwhH8AAAGEcXVpY4IjKolzZWNwMjU2azGhA7NTxgfOmGE2EQa4HhsXxFOeHdTLYIc2MEBczymm9IUN",
        "enr:-IW4QKbT-CoCAKBpbYNfzfFcPfYjkqHyH-5sFlVkaKlNEPN1M5M34vIYb8HyCg56m7-V13pKWZqH9ThdYtXjjavDrP4BgmlkgnY0"
        "gmlwhKwUAAqEcXVpY4IjKIlzZWNwMjU2azGhAuIbyETf2xNYGNJfCPhn95r0lyyoRpB5PCWwh53RSSgS"};
    for (size_t i = 0; i < sizeof(kEnrs) / sizeof(kEnrs[0]); ++i) {
        if (fprintf(fp, "- %s\n", kEnrs[i]) < 0) {
            fclose(fp);
            unlink(buffer);
            buffer[0] = '\0';
            return -1;
        }
    }
    fclose(fp);
    return 0;
}

int main(void) {
    struct lantern_genesis_artifacts artifacts;
    lantern_genesis_artifacts_init(&artifacts);
    int rc = 1;

    char config_path[PATH_MAX];
    char registry_path[PATH_MAX];
    char state_path[PATH_MAX];
    char validator_config_path[PATH_MAX];
    char validators_map_path[PATH_MAX];
    char nodes_path[PATH_MAX];

    build_fixture_path(config_path, sizeof(config_path), "genesis/config.yaml");
    build_fixture_path(registry_path, sizeof(registry_path), "genesis/validators.yaml");
    build_fixture_path(state_path, sizeof(state_path), "genesis/genesis.ssz");
    build_fixture_path(validator_config_path, sizeof(validator_config_path), "genesis/validator-config.yaml");
    build_fixture_path(validators_map_path, sizeof(validators_map_path), "genesis/validators.yaml");

    if (write_temp_nodes_file(nodes_path, sizeof(nodes_path)) != 0) {
        fprintf(stderr, "failed to create nodes file for validator selection test\n");
        goto cleanup;
    }

    struct lantern_genesis_paths paths = {
        .config_path = config_path,
        .validator_registry_path = registry_path,
        .nodes_path = nodes_path,
        .state_path = state_path,
        .validator_config_path = validator_config_path,
    };

    if (lantern_genesis_load(&artifacts, &paths) != 0) {
        fprintf(stderr, "lantern_genesis_load failed for validator selection test\n");
        goto cleanup;
    }

    if (lantern_validator_config_assign_ranges(
            &artifacts.validator_config,
            artifacts.chain_config.validator_count)
        != 0) {
        fprintf(stderr, "assign_ranges failed\n");
        goto cleanup;
    }

    struct lantern_validator_config_entry *ream0 = lantern_validator_config_find(
        &artifacts.validator_config,
        "ream_0");
    if (!ream0 || !ream0->has_range || ream0->start_index != 0 || ream0->end_index != 1) {
        fprintf(stderr, "unexpected range for ream_0\n");
        goto cleanup;
    }
    struct lantern_validator_config_entry *lantern6 = lantern_validator_config_find(
        &artifacts.validator_config,
        "lantern_6");
    if (!lantern6 || !lantern6->has_range || lantern6->start_index != 6 || lantern6->end_index != 7) {
        fprintf(stderr, "unexpected range for lantern_6\n");
        goto cleanup;
    }

    if (lantern_validator_config_apply_assignments(
            &artifacts.validator_config,
            validators_map_path,
            artifacts.chain_config.validator_count)
        != 0) {
        fprintf(stderr, "apply_assignments failed\n");
        goto cleanup;
    }

    if (lantern6->indices_len != 1 || lantern6->indices[0] != 6) {
        fprintf(stderr, "lantern_6 indices mismatch\n");
        goto cleanup;
    }
    if (ream0->indices_len != 1 || ream0->indices[0] != 0) {
        fprintf(stderr, "ream_0 indices mismatch\n");
        goto cleanup;
    }

    rc = 0;
    puts("lantern_validator_selection_test OK");

cleanup:
    lantern_genesis_artifacts_reset(&artifacts);
    if (nodes_path[0]) {
        unlink(nodes_path);
    }
    return rc;
}
