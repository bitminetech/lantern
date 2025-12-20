#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "internal/yaml_parser.h"

static int write_deep_yaml(const char *path, size_t depth) {
    if (!path || depth == 0) {
        return -1;
    }

    FILE *fp = fopen(path, "w");
    if (!fp) {
        return -1;
    }

    for (size_t i = 0; i < depth; ++i) {
        for (size_t j = 0; j < i; ++j) {
            if (fputc(' ', fp) == EOF) {
                fclose(fp);
                return -1;
            }
        }
        if (fprintf(fp, "k%zu:\n", i) < 0) {
            fclose(fp);
            return -1;
        }
    }

    if (fclose(fp) != 0) {
        return -1;
    }

    return 0;
}

int main(void) {
    char path_template[] = "/tmp/lantern_yaml_cveXXXXXX";
    int fd = mkstemp(path_template);
    if (fd < 0) {
        perror("mkstemp");
        return 1;
    }
    close(fd);

    if (write_deep_yaml(path_template, 128) != 0) {
        fprintf(stderr, "failed to write yaml payload\n");
        unlink(path_template);
        return 1;
    }

    size_t count = 0;
    LanternYamlObject *objects = lantern_yaml_read_array(path_template, "root.array", &count);
    lantern_yaml_free_objects(objects, count);

    unlink(path_template);
    puts("lantern_yaml_parser_cve_test completed without crash");
    return 0;
}
