#define _GNU_SOURCE

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>

#include "xdg-shell-client-protocol.h"

static struct wl_display *display;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct xdg_wm_base *wm_base;
static struct wl_surface *parent_surface;
static struct xdg_surface *parent_xdg;
static struct xdg_toplevel *parent_toplevel;
static struct wl_surface *popup_surface;
static struct xdg_surface *popup_xdg;
static int parent_configured;
static int popup_configured;

static struct wl_buffer *make_buffer(int width, int height, uint32_t color) {
    int stride = width * 4;
    int size = stride * height;
    int fd = memfd_create("tessa-popup", MFD_CLOEXEC);
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
    struct wl_buffer *buffer = wl_shm_pool_create_buffer(pool, 0, width, height, stride,
        WL_SHM_FORMAT_XRGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    return buffer;
}

static void buffer_release(void *data, struct wl_buffer *buffer) {
    (void)data;
    (void)buffer;
}

static const struct wl_buffer_listener buffer_listener = {
    .release = buffer_release,
};

static void wm_ping(void *data, struct xdg_wm_base *base, uint32_t serial) {
    (void)data;
    xdg_wm_base_pong(base, serial);
}

static const struct xdg_wm_base_listener wm_listener = {
    .ping = wm_ping,
};

static void parent_configure(void *data, struct xdg_surface *xdg_surface, uint32_t serial) {
    (void)data;
    xdg_surface_ack_configure(xdg_surface, serial);
    if (!parent_configured) {
        struct wl_buffer *buffer = make_buffer(400, 300, 0xff223344);
        wl_buffer_add_listener(buffer, &buffer_listener, NULL);
        wl_surface_attach(parent_surface, buffer, 0, 0);
        wl_surface_commit(parent_surface);
        parent_configured = 1;
    }
}

static const struct xdg_surface_listener parent_surface_listener = {
    .configure = parent_configure,
};

static void toplevel_configure(void *data, struct xdg_toplevel *toplevel,
        int32_t width, int32_t height, struct wl_array *states) {
    (void)data;
    (void)toplevel;
    (void)width;
    (void)height;
    (void)states;
}

static void toplevel_close(void *data, struct xdg_toplevel *toplevel) {
    (void)data;
    (void)toplevel;
    wl_display_disconnect(display);
    exit(0);
}

static const struct xdg_toplevel_listener toplevel_listener = {
    .configure = toplevel_configure,
    .close = toplevel_close,
};

static void popup_configure(void *data, struct xdg_surface *xdg_surface, uint32_t serial) {
    (void)data;
    xdg_surface_ack_configure(xdg_surface, serial);
    if (!popup_configured) {
        struct wl_buffer *buffer = make_buffer(120, 80, 0xffff0000);
        wl_buffer_add_listener(buffer, &buffer_listener, NULL);
        wl_surface_attach(popup_surface, buffer, 0, 0);
        wl_surface_commit(popup_surface);
        popup_configured = 1;
        printf("popup-mapped\n");
        fflush(stdout);
    }
}

static const struct xdg_surface_listener popup_surface_listener = {
    .configure = popup_configure,
};

static void popup_done(void *data, struct xdg_popup *popup) {
    (void)data;
    (void)popup;
}

static void popup_configure_event(void *data, struct xdg_popup *popup,
        int32_t x, int32_t y, int32_t width, int32_t height) {
    (void)data;
    (void)popup;
    (void)x;
    (void)y;
    (void)width;
    (void)height;
}

static void popup_repositioned(void *data, struct xdg_popup *popup, uint32_t token) {
    (void)data;
    (void)popup;
    (void)token;
}

static const struct xdg_popup_listener popup_listener = {
    .configure = popup_configure_event,
    .popup_done = popup_done,
    .repositioned = popup_repositioned,
};

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
        const char *interface, uint32_t version) {
    (void)data;
    if (strcmp(interface, wl_compositor_interface.name) == 0) {
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
    } else if (strcmp(interface, wl_shm_interface.name) == 0) {
        shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    } else if (strcmp(interface, xdg_wm_base_interface.name) == 0) {
        wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface, version < 3 ? version : 3);
        xdg_wm_base_add_listener(wm_base, &wm_listener, NULL);
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
    if (!compositor || !shm || !wm_base) {
        fprintf(stderr, "missing required globals\n");
        return 1;
    }

    parent_surface = wl_compositor_create_surface(compositor);
    parent_xdg = xdg_wm_base_get_xdg_surface(wm_base, parent_surface);
    xdg_surface_add_listener(parent_xdg, &parent_surface_listener, NULL);
    parent_toplevel = xdg_surface_get_toplevel(parent_xdg);
    xdg_toplevel_add_listener(parent_toplevel, &toplevel_listener, NULL);
    xdg_toplevel_set_title(parent_toplevel, "PopupTest");
    xdg_toplevel_set_app_id(parent_toplevel, "tessa-popup-test");
    wl_surface_commit(parent_surface);

    while (!parent_configured) {
        if (wl_display_dispatch(display) < 0) return 1;
    }

    popup_surface = wl_compositor_create_surface(compositor);
    popup_xdg = xdg_wm_base_get_xdg_surface(wm_base, popup_surface);
    xdg_surface_add_listener(popup_xdg, &popup_surface_listener, NULL);
    struct xdg_positioner *positioner = xdg_wm_base_create_positioner(wm_base);
    xdg_positioner_set_size(positioner, 120, 80);
    xdg_positioner_set_anchor_rect(positioner, 0, 0, 1, 1);
    xdg_positioner_set_anchor(positioner, XDG_POSITIONER_ANCHOR_TOP_LEFT);
    xdg_positioner_set_gravity(positioner, XDG_POSITIONER_GRAVITY_BOTTOM_RIGHT);
    xdg_positioner_set_offset(positioner, 30, 30);
    struct xdg_popup *popup = xdg_surface_get_popup(popup_xdg, parent_xdg, positioner);
    xdg_positioner_destroy(positioner);
    xdg_popup_add_listener(popup, &popup_listener, NULL);
    wl_surface_commit(popup_surface);

    while (wl_display_dispatch(display) >= 0) {
    }
    return 0;
}
