#define _GNU_SOURCE

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <wayland-client.h>

#include "ext-foreign-toplevel-list-v1-client-protocol.h"
#include "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

static struct wl_display *display;
static struct wl_registry *registry;
static struct zwlr_foreign_toplevel_manager_v1 *manager;
static struct ext_foreign_toplevel_list_v1 *ext_list;

static void handle_title(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
        const char *title) {
    (void)data;
    (void)handle;
    printf("wlr-title=%s\n", title ? title : "");
    fflush(stdout);
}

static void handle_app_id(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
        const char *app_id) {
    (void)data;
    (void)handle;
    printf("wlr-app-id=%s\n", app_id ? app_id : "");
    fflush(stdout);
}

static void handle_output_enter(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
        struct wl_output *output) {
    (void)data;
    (void)handle;
    (void)output;
}

static void handle_output_leave(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
        struct wl_output *output) {
    (void)data;
    (void)handle;
    (void)output;
}

static void handle_state(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
        struct wl_array *state) {
    (void)data;
    (void)handle;
    uint32_t *value;
    wl_array_for_each(value, state) {
        printf("wlr-state=%u\n", *value);
        fflush(stdout);
    }
}

static void handle_done(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle) {
    (void)data;
    (void)handle;
    printf("wlr-done\n");
    fflush(stdout);
}

static void handle_closed(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle) {
    (void)data;
    (void)handle;
    printf("wlr-closed\n");
    fflush(stdout);
}

static void handle_parent(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
        struct zwlr_foreign_toplevel_handle_v1 *parent) {
    (void)data;
    (void)handle;
    (void)parent;
}

static const struct zwlr_foreign_toplevel_handle_v1_listener handle_listener = {
    .title = handle_title,
    .app_id = handle_app_id,
    .output_enter = handle_output_enter,
    .output_leave = handle_output_leave,
    .state = handle_state,
    .done = handle_done,
    .closed = handle_closed,
    .parent = handle_parent,
};

static void manager_toplevel(void *data,
        struct zwlr_foreign_toplevel_manager_v1 *mgr,
        struct zwlr_foreign_toplevel_handle_v1 *handle) {
    (void)data;
    (void)mgr;
    zwlr_foreign_toplevel_handle_v1_add_listener(handle, &handle_listener, NULL);
}

static void manager_finished(void *data, struct zwlr_foreign_toplevel_manager_v1 *mgr) {
    (void)data;
    (void)mgr;
    printf("wlr-finished\n");
    fflush(stdout);
}

static const struct zwlr_foreign_toplevel_manager_v1_listener manager_listener = {
    .toplevel = manager_toplevel,
    .finished = manager_finished,
};

static void ext_title(void *data, struct ext_foreign_toplevel_handle_v1 *handle,
        const char *title) {
    (void)data;
    (void)handle;
    printf("ext-title=%s\n", title ? title : "");
    fflush(stdout);
}

static void ext_app_id(void *data, struct ext_foreign_toplevel_handle_v1 *handle,
        const char *app_id) {
    (void)data;
    (void)handle;
    printf("ext-app-id=%s\n", app_id ? app_id : "");
    fflush(stdout);
}

static void ext_identifier(void *data, struct ext_foreign_toplevel_handle_v1 *handle,
        const char *identifier) {
    (void)data;
    (void)handle;
    (void)identifier;
}

static void ext_closed(void *data, struct ext_foreign_toplevel_handle_v1 *handle) {
    (void)data;
    (void)handle;
    printf("ext-closed\n");
    fflush(stdout);
}

static void ext_done(void *data, struct ext_foreign_toplevel_handle_v1 *handle) {
    (void)data;
    (void)handle;
    printf("ext-done\n");
    fflush(stdout);
}

static const struct ext_foreign_toplevel_handle_v1_listener ext_handle_listener = {
    .closed = ext_closed,
    .done = ext_done,
    .title = ext_title,
    .app_id = ext_app_id,
    .identifier = ext_identifier,
};

static void ext_toplevel(void *data, struct ext_foreign_toplevel_list_v1 *list,
        struct ext_foreign_toplevel_handle_v1 *handle) {
    (void)data;
    (void)list;
    ext_foreign_toplevel_handle_v1_add_listener(handle, &ext_handle_listener, NULL);
}

static void ext_finished(void *data, struct ext_foreign_toplevel_list_v1 *list) {
    (void)data;
    (void)list;
    printf("ext-finished\n");
    fflush(stdout);
}

static const struct ext_foreign_toplevel_list_v1_listener ext_list_listener = {
    .toplevel = ext_toplevel,
    .finished = ext_finished,
};

static void registry_global(void *data, struct wl_registry *reg, uint32_t name,
        const char *interface, uint32_t version) {
    (void)data;
    if (strcmp(interface, zwlr_foreign_toplevel_manager_v1_interface.name) == 0) {
        manager = wl_registry_bind(reg, name,
            &zwlr_foreign_toplevel_manager_v1_interface, version < 3 ? version : 3);
        zwlr_foreign_toplevel_manager_v1_add_listener(manager, &manager_listener, NULL);
        printf("wlr-manager\n");
        fflush(stdout);
    } else if (strcmp(interface, ext_foreign_toplevel_list_v1_interface.name) == 0) {
        ext_list = wl_registry_bind(reg, name,
            &ext_foreign_toplevel_list_v1_interface, 1);
        ext_foreign_toplevel_list_v1_add_listener(ext_list, &ext_list_listener, NULL);
        printf("ext-list\n");
        fflush(stdout);
    }
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

int main(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "cannot connect to Wayland\n");
        return 1;
    }
    registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0) return 1;
    if (wl_display_roundtrip(display) < 0) return 1;

    while (wl_display_dispatch(display) >= 0) {
    }
    return 0;
}
