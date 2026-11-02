#define _GNU_SOURCE

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>

#include "xdg-shell-client-protocol.h"
#include "tearing-control-v1-client-protocol.h"

static struct wl_display *display;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct xdg_wm_base *wm_base;
static struct wp_tearing_control_manager_v1 *tearing_manager;
static struct wl_surface *surface;
static struct xdg_surface *xdg_surface;
static struct xdg_toplevel *xdg_toplevel;
static struct wl_buffer *buffer;
static int configured;

static void wm_ping(void *data, struct xdg_wm_base *base, uint32_t serial) {
    (void)data;
    xdg_wm_base_pong(base, serial);
}

static const struct xdg_wm_base_listener wm_listener = {
    .ping = wm_ping,
};

static void xdg_configure(void *data, struct xdg_surface *xdg, uint32_t serial) {
    (void)data;
    xdg_surface_ack_configure(xdg, serial);
    if (configured) return;
    configured = 1;
    wl_surface_attach(surface, buffer, 0, 0);
    wl_surface_commit(surface);
    xdg_toplevel_set_fullscreen(xdg_toplevel, NULL);
}

static const struct xdg_surface_listener xdg_listener = {
    .configure = xdg_configure,
};

static void toplevel_configure(void *data, struct xdg_toplevel *toplevel, int32_t width,
        int32_t height, struct wl_array *states) {
    (void)data;
    (void)toplevel;
    (void)width;
    (void)height;
    (void)states;
}

static void toplevel_close(void *data, struct xdg_toplevel *toplevel) {
    (void)data;
    (void)toplevel;
    exit(0);
}

static const struct xdg_toplevel_listener toplevel_listener = {
    .configure = toplevel_configure,
    .close = toplevel_close,
};

static void buffer_release(void *data, struct wl_buffer *buffer) {
    (void)data;
    (void)buffer;
}

static const struct wl_buffer_listener buffer_listener = {
    .release = buffer_release,
};

static struct wl_buffer *make_buffer(int width, int height) {
    int stride = width * 4;
    int size = stride * height;
    int fd = memfd_create("tessa-tearing", MFD_CLOEXEC);
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
    for (int i = 0; i < width * height; i++) pixels[i] = 0xFF203040;
    munmap(pixels, (size_t)size);

    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
    struct wl_buffer *buffer = wl_shm_pool_create_buffer(pool, 0, width, height, stride,
        WL_SHM_FORMAT_XRGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    return buffer;
}

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
        const char *interface, uint32_t version) {
    (void)data;
    (void)version;
    if (strcmp(interface, wl_compositor_interface.name) == 0) {
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
    } else if (strcmp(interface, wl_shm_interface.name) == 0) {
        shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    } else if (strcmp(interface, xdg_wm_base_interface.name) == 0) {
        wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
        xdg_wm_base_add_listener(wm_base, &wm_listener, NULL);
    } else if (strcmp(interface, wp_tearing_control_manager_v1_interface.name) == 0) {
        tearing_manager = wl_registry_bind(registry, name,
            &wp_tearing_control_manager_v1_interface, 1);
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
    display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "cannot connect to Wayland display\n");
        return 1;
    }

    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    if (!compositor || !shm || !wm_base) {
        fprintf(stderr, "missing core globals\n");
        return 1;
    }
    if (!tearing_manager) {
        fprintf(stderr, "wp_tearing_control_manager_v1 is not advertised\n");
        return 2;
    }

    surface = wl_compositor_create_surface(compositor);
    struct wp_tearing_control_v1 *tearing =
        wp_tearing_control_manager_v1_get_tearing_control(tearing_manager, surface);
    wp_tearing_control_v1_set_presentation_hint(tearing,
        WP_TEARING_CONTROL_V1_PRESENTATION_HINT_ASYNC);

    xdg_surface = xdg_wm_base_get_xdg_surface(wm_base, surface);
    xdg_surface_add_listener(xdg_surface, &xdg_listener, NULL);
    xdg_toplevel = xdg_surface_get_toplevel(xdg_surface);
    xdg_toplevel_add_listener(xdg_toplevel, &toplevel_listener, NULL);
    xdg_toplevel_set_title(xdg_toplevel, "TearingTest");
    xdg_toplevel_set_app_id(xdg_toplevel, "tessa-tearing-test");

    buffer = make_buffer(320, 200);
    wl_buffer_add_listener(buffer, &buffer_listener, NULL);
    wl_surface_commit(surface);

    /* Stay mapped long enough for the compositor to enter fullscreen and
     * attempt an async page flip. */
    for (int i = 0; i < 200 && !configured; i++) {
        if (wl_display_dispatch(display) < 0) break;
    }
    /* Let the fullscreen configure and the compositor's scanout commit settle
     * without blocking on a display that has no more events to send. */
    wl_display_roundtrip(display);
    for (int i = 0; i < 40; i++) {
        wl_display_dispatch_pending(display);
        wl_display_flush(display);
        usleep(50000);
    }

    wp_tearing_control_v1_destroy(tearing);
    xdg_toplevel_destroy(xdg_toplevel);
    xdg_surface_destroy(xdg_surface);
    wl_surface_destroy(surface);
    wl_buffer_destroy(buffer);
    wl_registry_destroy(registry);
    wl_display_disconnect(display);
    return 0;
}
