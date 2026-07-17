#ifndef LANTERN_TEST_STORAGE_CLEANUP_H
#define LANTERN_TEST_STORAGE_CLEANUP_H

#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int lantern_test_remove_file(const char *path)
{
    return unlink(path) == 0 || errno == ENOENT ? 0 : -1;
}

static int lantern_test_remove_storage_dir(const char *directory)
{
    if (!directory)
    {
        return -1;
    }
    static const char *const root_files[] = {"state.ssz", "state.ssz.tmp"};
    char path[PATH_MAX];
    for (size_t i = 0; i < sizeof(root_files) / sizeof(root_files[0]); ++i)
    {
        int written = snprintf(path, sizeof(path), "%s/%s", directory, root_files[i]);
        if (written <= 0 || (size_t)written >= sizeof(path)
            || lantern_test_remove_file(path) != 0)
        {
            return -1;
        }
    }
    static const char *const namespaces[] = {"blocks", "states"};
    for (size_t i = 0; i < sizeof(namespaces) / sizeof(namespaces[0]); ++i)
    {
        int written = snprintf(path, sizeof(path), "%s/%s", directory, namespaces[i]);
        if (written <= 0 || (size_t)written >= sizeof(path))
        {
            return -1;
        }
        DIR *stream = opendir(path);
        if (!stream)
        {
            if (errno == ENOENT)
            {
                continue;
            }
            return -1;
        }
        struct dirent *entry;
        while ((entry = readdir(stream)) != NULL)
        {
            if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
            {
                continue;
            }
            char child[PATH_MAX];
            written = snprintf(child, sizeof(child), "%s/%s", path, entry->d_name);
            if (written <= 0 || (size_t)written >= sizeof(child)
                || lantern_test_remove_file(child) != 0)
            {
                closedir(stream);
                return -1;
            }
        }
        if (closedir(stream) != 0 || rmdir(path) != 0)
        {
            return -1;
        }
    }
    return rmdir(directory);
}

#endif /* LANTERN_TEST_STORAGE_CLEANUP_H */
