#define _GNU_SOURCE

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>

#include "fractional-scale-v1-client-protocol.h"
#include "xdg-shell-client-protocol.h"

static struct wl_display *display;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct xdg_wm_base *wm_base;
static struct wp_fractional_scale_manager_v1 *fractional_manager;
static struct wl_surface *surface;
static struct wl_buffer *buffer;
static struct xdg_surface *xdg_surface;
static struct xdg_toplevel *toplevel;
static struct wp_fractional_scale_v1 *fractional;
static int configured;
static int mapped;

static void buffer_release(void *data, struct wl_buffer *wl_buffer) {
    (void)data;
    (void)wl_buffer;
}

static const struct wl_buffer_listener buffer_listener = {
    .release = buffer_release,
};

static void make_buffer(void) {
    const int width = 320;
    const int height = 200;
    const int stride = width * 4;
    const int size = stride * height;
    int fd = memfd_create("tessa-fractional", MFD_CLOEXEC);
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
    for (int i = 0; i < width * height; i++) pixels[i] = 0xff284868;
    munmap(pixels, (size_t)size);

    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
    buffer = wl_shm_pool_create_buffer(pool, 0, width, height, stride, WL_SHM_FORMAT_XRGB8888);
    wl_buffer_add_listener(buffer, &buffer_listener, NULL);
    wl_shm_pool_destroy(pool);
    close(fd);
}

static void wm_ping(void *data, struct xdg_wm_base *base, uint32_t serial) {
    (void)data;
    xdg_wm_base_pong(base, serial);
}

static const struct xdg_wm_base_listener wm_listener = {
    .ping = wm_ping,
};

static void xdg_configure(void *data, struct xdg_surface *xdg_surf, uint32_t serial) {
    (void)data;
    xdg_surface_ack_configure(xdg_surf, serial);
    if (!configured) {
        configured = 1;
        make_buffer();
        wl_surface_attach(surface, buffer, 0, 0);
        wl_surface_damage_buffer(surface, 0, 0, 320, 200);
        wl_surface_commit(surface);
        mapped = 1;
        printf("mapped\n");
        fflush(stdout);
    }
}

static const struct xdg_surface_listener xdg_surface_listener = {
    .configure = xdg_configure,
};

static void toplevel_configure(void *data, struct xdg_toplevel *tl,
        int32_t width, int32_t height, struct wl_array *states) {
    (void)data;
    (void)tl;
    (void)width;
    (void)height;
    (void)states;
}

static void toplevel_close(void *data, struct xdg_toplevel *tl) {
    (void)data;
    (void)tl;
    exit(0);
}

static const struct xdg_toplevel_listener toplevel_listener = {
    .configure = toplevel_configure,
    .close = toplevel_close,
};

static void preferred_scale(void *data, struct wp_fractional_scale_v1 *scale,
        uint32_t scale_120) {
    (void)data;
    (void)scale;
    printf("scale %u\n", scale_120);
    fflush(stdout);
}

static const struct wp_fractional_scale_v1_listener fractional_listener = {
    .preferred_scale = preferred_scale,
};

static void registry_global(void *data, struct wl_registry *registry,
        uint32_t name, const char *interface, uint32_t version) {
    (void)data;
    (void)version;
    if (strcmp(interface, wl_compositor_interface.name) == 0) {
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
    } else if (strcmp(interface, wl_shm_interface.name) == 0) {
        shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    } else if (strcmp(interface, xdg_wm_base_interface.name) == 0) {
        wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
        xdg_wm_base_add_listener(wm_base, &wm_listener, NULL);
    } else if (strcmp(interface, wp_fractional_scale_manager_v1_interface.name) == 0) {
        fractional_manager = wl_registry_bind(registry, name,
            &wp_fractional_scale_manager_v1_interface, 1);
    }
}

static void registry_global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

int main(void) {
    display = wl_display_connect(NULL);
    if (display == NULL) {
        fprintf(stderr, "cannot connect to Wayland display\n");
        return 1;
    }

    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0) return 1;
    if (compositor == NULL || shm == NULL || wm_base == NULL) {
        fprintf(stderr, "missing core Wayland globals\n");
        return 2;
    }
    if (fractional_manager == NULL) {
        fprintf(stderr, "wp_fractional_scale_manager_v1 was not advertised\n");
        return 3;
    }

    surface = wl_compositor_create_surface(compositor);
    xdg_surface = xdg_wm_base_get_xdg_surface(wm_base, surface);
    xdg_surface_add_listener(xdg_surface, &xdg_surface_listener, NULL);
    toplevel = xdg_surface_get_toplevel(xdg_surface);
    xdg_toplevel_add_listener(toplevel, &toplevel_listener, NULL);
    xdg_toplevel_set_title(toplevel, "FractionalScaleTest");

    fractional = wp_fractional_scale_manager_v1_get_fractional_scale(fractional_manager, surface);
    wp_fractional_scale_v1_add_listener(fractional, &fractional_listener, NULL);
    wl_surface_commit(surface);

    while (1) {
        if (wl_display_dispatch(display) < 0) return 1;
        if (mapped) {
            printf("ready\n");
            fflush(stdout);
            mapped = 0;
        }
    }
}
