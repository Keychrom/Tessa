#define _GNU_SOURCE

#include <errno.h>
#include <poll.h>
#include <signal.h>
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
static struct wl_surface *surface;
static struct xdg_surface *xdg_surface;
static struct xdg_toplevel *toplevel;
static struct wl_buffer *buffer;
static int configured;
static int pending_width = 640;
static int pending_height = 400;
static volatile sig_atomic_t retitle_requested;

static struct wl_buffer *make_buffer(int width, int height) {
    const int stride = width * 4;
    const int size = stride * height;
    const int fd = memfd_create("tessa-rule-window", MFD_CLOEXEC);
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
    for (int i = 0; i < width * height; i++) pixels[i] = 0xffffffff;
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
    if (!configured) {
        configured = 1;
        buffer = make_buffer(pending_width, pending_height);
        wl_buffer_add_listener(buffer, &buffer_listener, NULL);
        wl_surface_attach(surface, buffer, 0, 0);
        wl_surface_commit(surface);
        printf("window-mapped\n");
        fflush(stdout);
    }
}

static const struct xdg_surface_listener xdg_listener = {
    .configure = xdg_configure,
};

static void toplevel_configure(void *data, struct xdg_toplevel *tl,
        int32_t width, int32_t height, struct wl_array *states) {
    (void)data;
    (void)tl;
    (void)states;
    if (width > 0) pending_width = width;
    if (height > 0) pending_height = height;
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

static void on_retitle(int signal_number) {
    (void)signal_number;
    retitle_requested = 1;
}

int main(int argc, char **argv) {
    const char *initial_app_id = argc > 1 ? argv[1] : "tessa-rule-test";
    const char *initial_title = argc > 2 ? argv[2] : "RuleBefore";
    const char *next_app_id = argc > 3 ? argv[3] : "tessa-rule-after";
    const char *next_title = argc > 4 ? argv[4] : "RuleAfter";
    setvbuf(stdout, NULL, _IOLBF, 0);
    struct sigaction sa = {0};
    sa.sa_handler = on_retitle;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGUSR1, &sa, NULL);

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

    surface = wl_compositor_create_surface(compositor);
    xdg_surface = xdg_wm_base_get_xdg_surface(wm_base, surface);
    xdg_surface_add_listener(xdg_surface, &xdg_listener, NULL);
    toplevel = xdg_surface_get_toplevel(xdg_surface);
    xdg_toplevel_add_listener(toplevel, &toplevel_listener, NULL);
    xdg_toplevel_set_title(toplevel, initial_title);
    xdg_toplevel_set_app_id(toplevel, initial_app_id);
    wl_surface_commit(surface);

    struct pollfd pfd = { .fd = wl_display_get_fd(display), .events = POLLIN };
    while (1) {
        if (wl_display_dispatch_pending(display) < 0) break;
        if (wl_display_flush(display) < 0) break;
        if (retitle_requested) {
            retitle_requested = 0;
            xdg_toplevel_set_title(toplevel, next_title);
            xdg_toplevel_set_app_id(toplevel, next_app_id);
            printf("window-retitled\n");
            fflush(stdout);
        }
        if (poll(&pfd, 1, 50) < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (pfd.revents & POLLIN) {
            if (wl_display_dispatch(display) < 0) break;
        }
    }
    return 0;
}
