#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>

#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

static struct zwlr_virtual_pointer_manager_v1 *manager;
static struct zwlr_virtual_pointer_v1 *pointer;
static struct wl_display *display;

struct wl_registry *registry;

static void registry_global(void *data, struct wl_registry *reg, uint32_t name,
        const char *interface, uint32_t version) {
    (void)data;
    if (strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name) == 0) {
        manager = wl_registry_bind(reg, name,
            &zwlr_virtual_pointer_manager_v1_interface, version < 2 ? version : 2);
    }
    (void)version;
}

static void registry_remove(void *data, struct wl_registry *reg, uint32_t name) {
    (void)data;
    (void)reg;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_remove,
};

static int parse_action(const char *action, int argc, char **argv, int *used,
        uint32_t *time) {
    *used = 0;
    if (strcmp(action, "abs") == 0) {
        if (argc < 2) return -1;
        int x = atoi(argv[0]);
        int y = atoi(argv[1]);
        zwlr_virtual_pointer_v1_motion_absolute(pointer, *time,
            (uint32_t)x, (uint32_t)y, 1920, 1080);
        *used = 2;
    } else if (strcmp(action, "move") == 0) {
        if (argc < 2) return -1;
        double dx = atof(argv[0]);
        double dy = atof(argv[1]);
        zwlr_virtual_pointer_v1_motion(pointer, *time,
            wl_fixed_from_double(dx), wl_fixed_from_double(dy));
        *used = 2;
    } else if (strcmp(action, "press") == 0) {
        if (argc < 1) return -1;
        zwlr_virtual_pointer_v1_button(pointer, *time,
            (uint32_t)strtoul(argv[0], NULL, 0), WL_POINTER_BUTTON_STATE_PRESSED);
        *used = 1;
    } else if (strcmp(action, "release") == 0) {
        if (argc < 1) return -1;
        zwlr_virtual_pointer_v1_button(pointer, *time,
            (uint32_t)strtoul(argv[0], NULL, 0), WL_POINTER_BUTTON_STATE_RELEASED);
        *used = 1;
    } else if (strcmp(action, "click") == 0) {
        if (argc < 1) return -1;
        uint32_t button = (uint32_t)strtoul(argv[0], NULL, 0);
        zwlr_virtual_pointer_v1_button(pointer, *time, button, WL_POINTER_BUTTON_STATE_PRESSED);
        zwlr_virtual_pointer_v1_button(pointer, *time, button, WL_POINTER_BUTTON_STATE_RELEASED);
        *used = 1;
    } else if (strcmp(action, "axis") == 0) {
        if (argc < 1) return -1;
        zwlr_virtual_pointer_v1_axis(pointer, *time, WL_POINTER_AXIS_VERTICAL_SCROLL,
            wl_fixed_from_double(atof(argv[0])));
        *used = 1;
    } else if (strcmp(action, "sleep") == 0) {
        if (argc < 1) return -1;
        wl_display_flush(display);
        usleep((useconds_t)atoi(argv[0]) * 1000);
        *used = 1;
        return 0;
    } else {
        return -1;
    }
    zwlr_virtual_pointer_v1_frame(pointer);
    wl_display_flush(display);
    *time += 10;
    usleep(30000);
    return 0;
}

int main(int argc, char **argv) {
    display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "cannot connect to Wayland\n");
        return 1;
    }
    registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0) return 1;
    if (!manager) {
        fprintf(stderr, "virtual pointer manager not available\n");
        return 1;
    }
    pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, NULL);
    if (!pointer) {
        fprintf(stderr, "cannot create virtual pointer\n");
        return 1;
    }

    uint32_t time = 10;
    int i = 1;
    while (i < argc) {
        int used = 0;
        if (parse_action(argv[i], argc - i - 1, &argv[i + 1], &used, &time) < 0) {
            fprintf(stderr, "bad action: %s\n", argv[i]);
            return 2;
        }
        i += 1 + used;
    }
    if (wl_display_roundtrip(display) < 0) return 1;
    zwlr_virtual_pointer_v1_destroy(pointer);
    zwlr_virtual_pointer_manager_v1_destroy(manager);
    wl_display_disconnect(display);
    return 0;
}
