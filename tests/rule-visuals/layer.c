#define _GNU_SOURCE

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>

#include "layer-shell-client-protocol.h"

static struct wl_display *display;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct zwlr_layer_shell_v1 *layer_shell;
static struct wl_surface *surface;
static struct zwlr_layer_surface_v1 *layer_surface;
static int configured;

static struct wl_buffer *make_buffer(int width, int height, uint32_t color) {
    const int stride = width * 4;
    const int size = stride * height;
    const int fd = memfd_create("tessa-rule-layer", MFD_CLOEXEC);
    if (fd < 0) {
        perror("memfd_create");
        exit(1);
    }
    if (ftruncate(fd, size) < 0) {
        perror("ftruncate");
        exit(1);
    }
    uint32_t *pixels = mmap(NULL, (size_t)size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (pixels == MAP_FAILED) {
        perror("mmap");
        exit(1);
    }
    for (int i = 0; i < width * height; i++) pixels[i] = color;
    munmap(pixels, (size_t)size);

    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
    struct wl_buffer *result = wl_shm_pool_create_buffer(pool, 0, width, height, stride,
        WL_SHM_FORMAT_XRGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    return result;
}

static void buffer_release(void *data, struct wl_buffer *wl_buffer) {
    (void)data;
    (void)wl_buffer;
}

static const struct wl_buffer_listener buffer_listener = {
    .release = buffer_release,
};

static void layer_configure(void *data, struct zwlr_layer_surface_v1 *ls,
        uint32_t serial, uint32_t width, uint32_t height) {
    (void)data;
    (void)width;
    (void)height;
    zwlr_layer_surface_v1_ack_configure(ls, serial);
    if (!configured) {
        configured = 1;
        struct wl_buffer *buffer = make_buffer(12, 12, 0xffff0000);
        wl_buffer_add_listener(buffer, &buffer_listener, NULL);
        wl_surface_attach(surface, buffer, 0, 0);
        wl_surface_commit(surface);
        printf("layer-mapped\n");
        fflush(stdout);
    }
}

static void layer_closed(void *data, struct zwlr_layer_surface_v1 *ls) {
    (void)data;
    (void)ls;
    exit(0);
}

static const struct zwlr_layer_surface_v1_listener layer_listener = {
    .configure = layer_configure,
    .closed = layer_closed,
};

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
        const char *interface, uint32_t version) {
    (void)data;
    if (strcmp(interface, wl_compositor_interface.name) == 0) {
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
    } else if (strcmp(interface, wl_shm_interface.name) == 0) {
        shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    } else if (strcmp(interface, zwlr_layer_shell_v1_interface.name) == 0) {
        layer_shell = wl_registry_bind(registry, name, &zwlr_layer_shell_v1_interface,
            version < 4 ? version : 4);
    }
}

static void registry_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_remove,
};

int main(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "cannot connect to Wayland\n");
        return 1;
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0) return 1;
    if (!compositor || !shm || !layer_shell) {
        fprintf(stderr, "missing required globals\n");
        return 1;
    }

    surface = wl_compositor_create_surface(compositor);
    layer_surface = zwlr_layer_shell_v1_get_layer_surface(layer_shell, surface, NULL,
        ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM, "tessa-layer-test");
    zwlr_layer_surface_v1_add_listener(layer_surface, &layer_listener, NULL);
    zwlr_layer_surface_v1_set_size(layer_surface, 12, 12);
    zwlr_layer_surface_v1_set_anchor(layer_surface,
        ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT);
    wl_surface_commit(surface);

    while (wl_display_dispatch(display) >= 0) {
    }
    return 0;
}
