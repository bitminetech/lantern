#include <assert.h>
#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/types.h>

#include "lantern/consensus/state.h"
#include "lantern/consensus/ssz.h"
#include "lantern/http/server.h"
#include "lantern/storage/storage.h"
#include "lantern/support/strings.h"

struct checkpoint_fixture
{
    char *data_dir;
    LanternState state;
    LanternRoot root;
    uint8_t *ssz_bytes;
    size_t ssz_len;
};

struct checkpoint_callback_ctx
{
    const uint8_t *data;
    size_t len;
    int rc;
};

static void expect_zero(int rc, const char *label)
{
    if (rc != 0)
    {
        fprintf(stderr, "%s failed rc=%d (errno=%d)\n", label, rc, errno);
        exit(EXIT_FAILURE);
    }
}

static void expect_true(bool value, const char *label)
{
    if (!value)
    {
        fprintf(stderr, "%s expected true\n", label);
        exit(EXIT_FAILURE);
    }
}

static void cleanup_path(const char *path)
{
    if (!path)
    {
        return;
    }
    if (unlink(path) != 0 && errno != ENOENT)
    {
        fprintf(stderr, "failed to remove %s: %s\n", path, strerror(errno));
        exit(EXIT_FAILURE);
    }
}

static void cleanup_dir(const char *path)
{
    if (!path)
    {
        return;
    }
    if (rmdir(path) != 0 && errno != ENOENT)
    {
        fprintf(stderr, "failed to remove dir %s: %s\n", path, strerror(errno));
        exit(EXIT_FAILURE);
    }
}

static int build_checkpoint_fixture(struct checkpoint_fixture *fixture)
{
    if (!fixture)
    {
        return 1;
    }
    memset(fixture, 0, sizeof(*fixture));

    char dir_template[] = "/tmp/lantern_checkpoint_syncXXXXXX";
    char *temp_dir = mkdtemp(dir_template);
    if (!temp_dir)
    {
        perror("mkdtemp");
        return 1;
    }
    fixture->data_dir = strdup(temp_dir);
    if (!fixture->data_dir)
    {
        perror("strdup");
        return 1;
    }

    lantern_state_init(&fixture->state);
    if (lantern_state_generate_genesis(&fixture->state, 1234u, 4u) != 0)
    {
        fprintf(stderr, "failed to generate genesis state\n");
        return 1;
    }

    uint8_t pubkeys[4u * LANTERN_VALIDATOR_PUBKEY_SIZE];
    for (size_t i = 0; i < sizeof(pubkeys); ++i)
    {
        pubkeys[i] = (uint8_t)(0x20 + (i & 0x3Fu));
    }
    if (lantern_state_set_validator_pubkeys(&fixture->state, pubkeys, 4u) != 0)
    {
        fprintf(stderr, "failed to set validator pubkeys\n");
        return 1;
    }

    memset(&fixture->root, 0x42, sizeof(fixture->root));
    fixture->state.latest_finalized.root = fixture->root;
    fixture->state.latest_finalized.slot = 0;

    if (lantern_storage_store_state_for_root(fixture->data_dir, &fixture->root, &fixture->state) != 0)
    {
        fprintf(stderr, "failed to store state for root\n");
        return 1;
    }

    if (lantern_storage_load_state_bytes_for_root(
            fixture->data_dir,
            &fixture->root,
            &fixture->ssz_bytes,
            &fixture->ssz_len)
        != 0)
    {
        fprintf(stderr, "failed to load state bytes for root\n");
        return 1;
    }

    return 0;
}

static void cleanup_checkpoint_fixture(struct checkpoint_fixture *fixture)
{
    if (!fixture)
    {
        return;
    }

    if (fixture->ssz_bytes)
    {
        free(fixture->ssz_bytes);
        fixture->ssz_bytes = NULL;
        fixture->ssz_len = 0;
    }
    lantern_state_reset(&fixture->state);

    if (fixture->data_dir)
    {
        char root_hex[2u * LANTERN_ROOT_SIZE + 1u];
        if (lantern_bytes_to_hex(
                fixture->root.bytes,
                LANTERN_ROOT_SIZE,
                root_hex,
                sizeof(root_hex),
                0)
            == 0)
        {
            char states_dir[PATH_MAX];
            int dir_written = snprintf(states_dir, sizeof(states_dir), "%s/states", fixture->data_dir);
            if (dir_written > 0 && (size_t)dir_written < sizeof(states_dir))
            {
                char state_path[PATH_MAX];
                char meta_path[PATH_MAX];
                int state_written = snprintf(state_path, sizeof(state_path), "%s/%s.ssz", states_dir, root_hex);
                int meta_written = snprintf(meta_path, sizeof(meta_path), "%s/%s.meta", states_dir, root_hex);
                if (state_written > 0 && (size_t)state_written < sizeof(state_path))
                {
                    cleanup_path(state_path);
                }
                if (meta_written > 0 && (size_t)meta_written < sizeof(meta_path))
                {
                    cleanup_path(meta_path);
                }
                cleanup_dir(states_dir);
            }
        }
        cleanup_dir(fixture->data_dir);
        free(fixture->data_dir);
        fixture->data_dir = NULL;
    }
}

static int finalized_state_cb(void *context, uint8_t **out_bytes, size_t *out_len)
{
    if (!context || !out_bytes || !out_len)
    {
        return LANTERN_HTTP_CB_ERR_INVALID_PARAM;
    }
    struct checkpoint_callback_ctx *ctx = context;
    if (ctx->rc != 0)
    {
        return ctx->rc;
    }
    uint8_t *buffer = malloc(ctx->len);
    if (!buffer)
    {
        return LANTERN_HTTP_CB_ERR_IO;
    }
    memcpy(buffer, ctx->data, ctx->len);
    *out_bytes = buffer;
    *out_len = ctx->len;
    return LANTERN_HTTP_CB_OK;
}

static int send_all(int fd, const uint8_t *data, size_t length)
{
    size_t remaining = length;
    const uint8_t *cursor = data;
    while (remaining > 0)
    {
        ssize_t written = send(fd, cursor, remaining, 0);
        if (written < 0)
        {
            if (errno == EINTR)
            {
                continue;
            }
            return -1;
        }
        if (written == 0)
        {
            return -1;
        }
        cursor += (size_t)written;
        remaining -= (size_t)written;
    }
    return 0;
}

static int read_response(uint16_t port, const char *request, uint8_t **out_data, size_t *out_len)
{
    if (!request || !out_data || !out_len)
    {
        return -1;
    }
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
    {
        return -1;
    }
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    if (inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr) <= 0)
    {
        close(fd);
        return -1;
    }
    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0)
    {
        close(fd);
        return -1;
    }
    size_t request_len = strlen(request);
    if (send_all(fd, (const uint8_t *)request, request_len) != 0)
    {
        close(fd);
        return -1;
    }

    uint8_t *buffer = NULL;
    size_t buffer_len = 0;
    size_t buffer_cap = 0;
    for (;;)
    {
        uint8_t chunk[1024];
        ssize_t read_bytes = recv(fd, chunk, sizeof(chunk), 0);
        if (read_bytes < 0)
        {
            if (errno == EINTR)
            {
                continue;
            }
            free(buffer);
            close(fd);
            return -1;
        }
        if (read_bytes == 0)
        {
            break;
        }
        size_t needed = buffer_len + (size_t)read_bytes;
        if (needed > buffer_cap)
        {
            size_t new_cap = buffer_cap == 0 ? 2048u : buffer_cap * 2u;
            while (new_cap < needed)
            {
                new_cap *= 2u;
            }
            uint8_t *resized = realloc(buffer, new_cap);
            if (!resized)
            {
                free(buffer);
                close(fd);
                return -1;
            }
            buffer = resized;
            buffer_cap = new_cap;
        }
        memcpy(buffer + buffer_len, chunk, (size_t)read_bytes);
        buffer_len += (size_t)read_bytes;
    }
    close(fd);

    if (!buffer || buffer_len == 0)
    {
        free(buffer);
        return -1;
    }

    *out_data = buffer;
    *out_len = buffer_len;
    return 0;
}

static int find_header_end(const uint8_t *data, size_t len, size_t *out_index)
{
    if (!data || !out_index || len < 4)
    {
        return -1;
    }
    for (size_t i = 0; i + 3 < len; ++i)
    {
        if (data[i] == '\r'
            && data[i + 1] == '\n'
            && data[i + 2] == '\r'
            && data[i + 3] == '\n')
        {
            *out_index = i + 4;
            return 0;
        }
    }
    return -1;
}

static int test_checkpoint_state_endpoint(void)
{
    struct checkpoint_fixture fixture;
    if (build_checkpoint_fixture(&fixture) != 0)
    {
        cleanup_checkpoint_fixture(&fixture);
        return 1;
    }

    struct checkpoint_callback_ctx ctx = {
        .data = fixture.ssz_bytes,
        .len = fixture.ssz_len,
        .rc = LANTERN_HTTP_CB_OK,
    };

    struct lantern_http_server server;
    lantern_http_server_init(&server);
    struct lantern_http_server_config config;
    memset(&config, 0, sizeof(config));
    config.port = 0;
    config.callbacks.context = &ctx;
    config.callbacks.finalized_state_ssz = finalized_state_cb;

    if (lantern_http_server_start(&server, &config) != 0)
    {
        cleanup_checkpoint_fixture(&fixture);
        return 1;
    }

    struct sockaddr_in addr;
    socklen_t addr_len = sizeof(addr);
    if (getsockname(server.listen_fd, (struct sockaddr *)&addr, &addr_len) != 0)
    {
        lantern_http_server_stop(&server);
        cleanup_checkpoint_fixture(&fixture);
        return 1;
    }
    uint16_t port = ntohs(addr.sin_port);
    expect_true(port != 0, "ephemeral port assigned");

    const char *request =
        "GET /lean/states/finalized HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Accept: application/octet-stream\r\n"
        "Connection: close\r\n"
        "\r\n";

    uint8_t *response = NULL;
    size_t response_len = 0;
    if (read_response(port, request, &response, &response_len) != 0)
    {
        lantern_http_server_stop(&server);
        cleanup_checkpoint_fixture(&fixture);
        return 1;
    }

    size_t header_end = 0;
    expect_zero(find_header_end(response, response_len, &header_end), "find header end");
    expect_true(header_end < response_len, "header size");

    char *header = malloc(header_end + 1);
    expect_true(header != NULL, "header alloc");
    memcpy(header, response, header_end);
    header[header_end] = '\0';

    expect_true(strstr(header, "HTTP/1.1 200") != NULL, "status 200");
    expect_true(strstr(header, "Content-Type: application/octet-stream") != NULL, "content-type");

    size_t body_len = response_len - header_end;
    expect_true(body_len == fixture.ssz_len, "body length");
    expect_true(memcmp(response + header_end, fixture.ssz_bytes, fixture.ssz_len) == 0, "body bytes");

    free(header);
    free(response);

    ctx.rc = LANTERN_HTTP_CB_ERR_NOT_FOUND;
    response = NULL;
    response_len = 0;
    if (read_response(port, request, &response, &response_len) != 0)
    {
        lantern_http_server_stop(&server);
        cleanup_checkpoint_fixture(&fixture);
        return 1;
    }

    header_end = 0;
    expect_zero(find_header_end(response, response_len, &header_end), "find header end 404");
    header = malloc(header_end + 1);
    expect_true(header != NULL, "header alloc 404");
    memcpy(header, response, header_end);
    header[header_end] = '\0';
    expect_true(strstr(header, "HTTP/1.1 404") != NULL, "status 404");

    free(header);
    free(response);

    lantern_http_server_stop(&server);
    cleanup_checkpoint_fixture(&fixture);
    return 0;
}

static int test_storage_state_bytes(void)
{
    struct checkpoint_fixture fixture;
    if (build_checkpoint_fixture(&fixture) != 0)
    {
        cleanup_checkpoint_fixture(&fixture);
        return 1;
    }

    LanternState decoded;
    lantern_state_init(&decoded);
    int decode_rc = lantern_ssz_decode_state(&decoded, fixture.ssz_bytes, fixture.ssz_len);
    expect_zero(decode_rc, "decode state bytes");
    expect_true(decoded.validator_count == 4u, "validator count");
    expect_true(
        memcmp(decoded.latest_finalized.root.bytes, fixture.root.bytes, LANTERN_ROOT_SIZE) == 0,
        "finalized root");

    lantern_state_reset(&decoded);
    cleanup_checkpoint_fixture(&fixture);
    return 0;
}

int main(void)
{
    if (test_storage_state_bytes() != 0)
    {
        return 1;
    }
    if (test_checkpoint_state_endpoint() != 0)
    {
        return 1;
    }
    return 0;
}
