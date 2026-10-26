#define _GNU_SOURCE

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>

#include "xdg-shell-client-protocol.h"
#include "pointer-constraints-unstable-v1-client-protocol.h"

static struct wl_display *display;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct xdg_wm_base *wm_base;
static struct wl_seat *seat;
static struct wl_pointer *pointer;
static struct zwp_pointer_constraints_v1 *constraints;
static struct zwp_locked_pointer_v1 *locked;
static struct wl_surface *surface;
static struct wl_buffer *buffer;
static struct xdg_surface *xdg_surface;
static struct xdg_toplevel *toplevel;
static int configured;

static void buffer_release(void *data, struct wl_buffer *wl_buffer) {
    (void)data;
    (void)wl_buffer;
}

static const struct wl_buffer_listener buffer_listener = {
    .release = buffer_release,
};

static void make_buffer(void) {
    int width = 320;
    int height = 200;
    int stride = width * 4;
    int size = stride * height;
    int fd = memfd_create("tessa-constraint", MFD_CLOEXEC);
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
    for (int i = 0; i < width * height; i++) pixels[i] = 0xff334455;
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
    wl_display_disconnect(display);
    exit(0);
}

static const struct xdg_toplevel_listener toplevel_listener = {
    .configure = toplevel_configure,
    .close = toplevel_close,
};

static void pointer_enter(void *data, struct wl_pointer *wl_pointer, uint32_t serial,
        struct wl_surface *wl_surface, wl_fixed_t sx, wl_fixed_t sy) {
    (void)data;
    (void)wl_pointer;
    (void)serial;
    (void)wl_surface;
    (void)sx;
    (void)sy;
}

static void pointer_leave(void *data, struct wl_pointer *wl_pointer, uint32_t serial,
        struct wl_surface *wl_surface) {
    (void)data;
    (void)wl_pointer;
    (void)serial;
    (void)wl_surface;
}

static void pointer_motion(void *data, struct wl_pointer *wl_pointer, uint32_t time,
        wl_fixed_t sx, wl_fixed_t sy) {
    (void)data;
    (void)wl_pointer;
    (void)time;
    (void)sx;
    (void)sy;
}

static void pointer_button(void *data, struct wl_pointer *wl_pointer, uint32_t serial,
        uint32_t time, uint32_t button, uint32_t state) {
    (void)data;
    (void)wl_pointer;
    (void)serial;
    (void)time;
    (void)button;
    (void)state;
}

static void pointer_axis(void *data, struct wl_pointer *wl_pointer, uint32_t time,
        uint32_t axis, wl_fixed_t value) {
    (void)data;
    (void)wl_pointer;
    (void)time;
    (void)axis;
    (void)value;
}

static void pointer_frame(void *data, struct wl_pointer *wl_pointer) {
    (void)data;
    (void)wl_pointer;
}

static void pointer_axis_source(void *data, struct wl_pointer *wl_pointer, uint32_t source) {
    (void)data;
    (void)wl_pointer;
    (void)source;
}

static void pointer_axis_stop(void *data, struct wl_pointer *wl_pointer, uint32_t time, uint32_t axis) {
    (void)data;
    (void)wl_pointer;
    (void)time;
    (void)axis;
}

static void pointer_axis_discrete(void *data, struct wl_pointer *wl_pointer, uint32_t axis, int32_t discrete) {
    (void)data;
    (void)wl_pointer;
    (void)axis;
    (void)discrete;
}

static const struct wl_pointer_listener pointer_listener = {
    .enter = pointer_enter,
    .leave = pointer_leave,
    .motion = pointer_motion,
    .button = pointer_button,
    .axis = pointer_axis,
    .frame = pointer_frame,
    .axis_source = pointer_axis_source,
    .axis_stop = pointer_axis_stop,
    .axis_discrete = pointer_axis_discrete,
};

static void locked_activated(void *data, struct zwp_locked_pointer_v1 *wl_locked) {
    (void)data;
    (void)wl_locked;
    printf("activated\n");
    fflush(stdout);
}

static void locked_deactivated(void *data, struct zwp_locked_pointer_v1 *wl_locked) {
    (void)data;
    (void)wl_locked;
    printf("deactivated\n");
    fflush(stdout);
}

static const struct zwp_locked_pointer_v1_listener locked_listener = {
    .locked = locked_activated,
    .unlocked = locked_deactivated,
};

static void seat_capabilities(void *data, struct wl_seat *wl_seat, uint32_t caps) {
    (void)data;
    if ((caps & WL_SEAT_CAPABILITY_POINTER) && !pointer) {
        pointer = wl_seat_get_pointer(wl_seat);
        wl_pointer_add_listener(pointer, &pointer_listener, NULL);
        printf("pointer\n");
        fflush(stdout);
    }
}

static void seat_name(void *data, struct wl_seat *wl_seat, const char *name) {
    (void)data;
    (void)wl_seat;
    (void)name;
}

static const struct wl_seat_listener seat_listener = {
    .capabilities = seat_capabilities,
    .name = seat_name,
};

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
    } else if (strcmp(interface, wl_seat_interface.name) == 0) {
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 5);
        wl_seat_add_listener(seat, &seat_listener, NULL);
    } else if (strcmp(interface, zwp_pointer_constraints_v1_interface.name) == 0) {
        constraints = wl_registry_bind(registry, name, &zwp_pointer_constraints_v1_interface, 1);
        printf("constraints-global\n");
        fflush(stdout);
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
    if (!compositor || !shm || !wm_base || !constraints) {
        fprintf(stderr, "missing required globals\n");
        return 1;
    }

    surface = wl_compositor_create_surface(compositor);
    xdg_surface = xdg_wm_base_get_xdg_surface(wm_base, surface);
    xdg_surface_add_listener(xdg_surface, &xdg_surface_listener, NULL);
    toplevel = xdg_surface_get_toplevel(xdg_surface);
    xdg_toplevel_add_listener(toplevel, &toplevel_listener, NULL);
    xdg_toplevel_set_title(toplevel, "constraint-test");
    xdg_toplevel_set_app_id(toplevel, "tessa-constraint-test");
    wl_surface_commit(surface);
    if (wl_display_roundtrip(display) < 0) return 1;
    while (!configured) {
        if (wl_display_dispatch(display) < 0) return 1;
    }
    if (!pointer) {
        if (wl_display_roundtrip(display) < 0) return 1;
    }
    if (!pointer) {
        fprintf(stderr, "no pointer in seat\n");
        return 1;
    }

    make_buffer();
    wl_surface_attach(surface, buffer, 0, 0);
    wl_surface_commit(surface);
    if (wl_display_roundtrip(display) < 0) return 1;

    locked = zwp_pointer_constraints_v1_lock_pointer(
        constraints, surface, pointer, NULL, ZWP_POINTER_CONSTRAINTS_V1_LIFETIME_PERSISTENT);
    zwp_locked_pointer_v1_add_listener(locked, &locked_listener, NULL);
    printf("constraint-created\n");
    fflush(stdout);

    while (wl_display_dispatch(display) >= 0) {
    }
    return 0;
}
