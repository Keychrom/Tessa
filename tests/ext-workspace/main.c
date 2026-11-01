#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>

#include "ext-workspace-v1-client-protocol.h"

static struct wl_display *display;
static struct ext_workspace_manager_v1 *manager;
static struct ext_workspace_handle_v1 *ws2;
static int groups;
static int workspaces;
static int active2;
static int done;
static char ws2_name[64];
static char ws2_id[128];

static void ws_id(void *data, struct ext_workspace_handle_v1 *ws,
        const char *id) {
    (void)data;
    if (ws2 == NULL && strstr(id, ":2") != NULL) {
        ws2 = ws;
        snprintf(ws2_id, sizeof(ws2_id), "%s", id);
    }
}

static void ws_name(void *data, struct ext_workspace_handle_v1 *ws,
        const char *name) {
    (void)data;
    if (ws == ws2) snprintf(ws2_name, sizeof(ws2_name), "%s", name);
}

static void ws_coordinates(void *data, struct ext_workspace_handle_v1 *ws,
        struct wl_array *coordinates) {
    (void)data;
    (void)ws;
    (void)coordinates;
}

static void ws_state(void *data, struct ext_workspace_handle_v1 *ws,
        uint32_t state) {
    (void)data;
    if (ws == ws2 && (state & EXT_WORKSPACE_HANDLE_V1_STATE_ACTIVE)) active2 = 1;
}

static void ws_capabilities(void *data, struct ext_workspace_handle_v1 *ws,
        uint32_t capabilities) {
    (void)data;
    (void)ws;
    (void)capabilities;
}

static void ws_removed(void *data, struct ext_workspace_handle_v1 *ws) {
    (void)data;
    if (ws == ws2) ws2 = NULL;
}

static const struct ext_workspace_handle_v1_listener ws_listener = {
    .id = ws_id,
    .name = ws_name,
    .coordinates = ws_coordinates,
    .state = ws_state,
    .capabilities = ws_capabilities,
    .removed = ws_removed,
};

static void group_capabilities(void *data,
        struct ext_workspace_group_handle_v1 *group, uint32_t capabilities) {
    (void)data;
    (void)group;
    (void)capabilities;
}

static void group_output_enter(void *data,
        struct ext_workspace_group_handle_v1 *group, struct wl_output *output) {
    (void)data;
    (void)group;
    (void)output;
}

static void group_output_leave(void *data,
        struct ext_workspace_group_handle_v1 *group, struct wl_output *output) {
    (void)data;
    (void)group;
    (void)output;
}

static void group_workspace_enter(void *data,
        struct ext_workspace_group_handle_v1 *group,
        struct ext_workspace_handle_v1 *ws) {
    (void)data;
    (void)group;
    (void)ws;
}

static void group_workspace_leave(void *data,
        struct ext_workspace_group_handle_v1 *group,
        struct ext_workspace_handle_v1 *ws) {
    (void)data;
    (void)group;
    (void)ws;
}

static void group_removed(void *data,
        struct ext_workspace_group_handle_v1 *group) {
    (void)data;
    (void)group;
}

static const struct ext_workspace_group_handle_v1_listener group_listener = {
    .capabilities = group_capabilities,
    .output_enter = group_output_enter,
    .output_leave = group_output_leave,
    .workspace_enter = group_workspace_enter,
    .workspace_leave = group_workspace_leave,
    .removed = group_removed,
};

static void manager_group(void *data,
        struct ext_workspace_manager_v1 *mgr,
        struct ext_workspace_group_handle_v1 *group) {
    (void)data;
    (void)mgr;
    groups++;
    ext_workspace_group_handle_v1_add_listener(group, &group_listener, NULL);
}

static void manager_workspace(void *data,
        struct ext_workspace_manager_v1 *mgr,
        struct ext_workspace_handle_v1 *ws) {
    (void)data;
    (void)mgr;
    workspaces++;
    ext_workspace_handle_v1_add_listener(ws, &ws_listener, NULL);
}

static void manager_done(void *data, struct ext_workspace_manager_v1 *mgr) {
    (void)data;
    (void)mgr;
    done = 1;
}

static void manager_finished(void *data,
        struct ext_workspace_manager_v1 *mgr) {
    (void)data;
    (void)mgr;
}

static const struct ext_workspace_manager_v1_listener manager_listener = {
    .workspace_group = manager_group,
    .workspace = manager_workspace,
    .done = manager_done,
    .finished = manager_finished,
};

static void registry_global(void *data, struct wl_registry *registry,
        uint32_t name, const char *interface, uint32_t version) {
    (void)data;
    (void)version;
    if (strcmp(interface, ext_workspace_manager_v1_interface.name) == 0) {
        manager = wl_registry_bind(registry, name,
            &ext_workspace_manager_v1_interface, 1);
        ext_workspace_manager_v1_add_listener(manager, &manager_listener, NULL);
    }
}

static void registry_remove(void *data, struct wl_registry *registry,
        uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_remove,
};

static int roundtrip_until(int *flag, int limit) {
    int i = 0;
    while (i < limit) {
        if (wl_display_roundtrip(display) < 0) return -1;
        if (*flag) return 0;
        usleep(10000);
        i++;
    }
    return -1;
}

int main(void) {
    display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "cannot connect to Wayland display\n");
        return 1;
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0) return 1;
    if (manager == NULL) {
        fprintf(stderr, "ext_workspace_manager_v1 not advertised\n");
        return 1;
    }
    if (roundtrip_until(&done, 100) < 0) {
        fprintf(stderr, "timed out waiting for initial workspace state\n");
        return 1;
    }
    if (groups < 1 || workspaces < 9) {
        fprintf(stderr, "groups=%d workspaces=%d (expected at least 1/9)\n",
            groups, workspaces);
        return 1;
    }
    if (ws2 == NULL) {
        fprintf(stderr, "no workspace id ending in ':2'\n");
        return 1;
    }

    active2 = 0;
    ext_workspace_handle_v1_activate(ws2);
    ext_workspace_manager_v1_commit(manager);
    if (roundtrip_until(&active2, 100) < 0) {
        fprintf(stderr, "workspace activation did not become active (id=%s name=%s)\n",
            ws2_id, ws2_name);
        return 1;
    }

    printf("groups=%d workspaces=%d active2=%d id=%s name=%s\n",
        groups, workspaces, active2, ws2_id, ws2_name);
    ext_workspace_manager_v1_destroy(manager);
    wl_display_disconnect(display);
    return 0;
}
