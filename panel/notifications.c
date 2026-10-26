#define _GNU_SOURCE

#include "notifications.h"

#include <gio/gio.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define TESSA_NOTIFICATIONS_PATH "/org/freedesktop/Notifications"
#define TESSA_NOTIFICATIONS_NAME "org.freedesktop.Notifications"
#define TESSA_NOTIFICATIONS_IFACE "org.freedesktop.Notifications"

#define MAX_APP 63
#define MAX_SUMMARY 159
#define MAX_BODY 511
#define MAX_ERROR 200
#define MAX_ICON 64
#define MAX_ICON_BYTES (MAX_ICON * MAX_ICON * 4)
#define MAX_ICON_NAME 255
#define MAX_ACTION 4
#define MAX_ACTION_KEY 63
#define MAX_ACTION_LABEL 95

static GMainLoop *loop;
static GThread *thread;
static GDBusConnection *bus;
static GHashTable *active;
static guint owner_id;
static guint32 next_id = 1;
static int sock_read = -1;
static int sock_write = -1;
static gboolean stopping;

typedef struct {
    guint32 id;
    guint32 reason;
} CloseRequest;

typedef struct {
    guint32 id;
    char *key;
} ActionRequest;

typedef struct {
    char key[MAX_ACTION_KEY + 1];
    char label[MAX_ACTION_LABEL + 1];
} NotifyAction;

static void put_u32(unsigned char *p, uint32_t v) {
    p[0] = (unsigned char)(v & 0xff);
    p[1] = (unsigned char)((v >> 8) & 0xff);
    p[2] = (unsigned char)((v >> 16) & 0xff);
    p[3] = (unsigned char)((v >> 24) & 0xff);
}

static void write_all(const void *data, size_t len) {
    const unsigned char *p = data;
    while (len > 0) {
        ssize_t n = send(sock_write, p, len, MSG_NOSIGNAL);
        if (n <= 0) return;
        p += n;
        len -= (size_t)n;
    }
}

static void send_ready(void) {
    const unsigned char type = 3;
    write_all(&type, 1);
}

static void send_error(const char *message) {
    unsigned char hdr[5];
    hdr[0] = 4;
    size_t len = strlen(message);
    if (len > MAX_ERROR) len = MAX_ERROR;
    put_u32(hdr + 1, (uint32_t)len);
    write_all(hdr, sizeof(hdr));
    write_all(message, len);
}

static void send_close_event(guint32 id) {
    unsigned char hdr[5];
    hdr[0] = 2;
    put_u32(hdr + 1, id);
    write_all(hdr, sizeof(hdr));
}

static size_t utf8_prefix(const char *text, size_t max) {
    if (!text) return 0;
    size_t len = strlen(text);
    if (len <= max) return len;
    size_t n = max;
    while (n > 0 && (((unsigned char)text[n]) & 0xc0) == 0x80) n--;
    return n;
}

static void copy_trunc(char *dest, size_t cap, const char *src) {
    size_t len = utf8_prefix(src, cap - 1);
    if (len > 0) memcpy(dest, src, len);
    dest[len] = '\0';
}

static guint32 extract_actions(GVariant *actions, NotifyAction *out) {
    if (!actions) return 0;
    gsize n = g_variant_n_children(actions);
    guint32 count = 0;
    for (gsize i = 0; i + 1 < n && count < MAX_ACTION; i += 2) {
        GVariant *key_v = g_variant_get_child_value(actions, i);
        GVariant *label_v = g_variant_get_child_value(actions, i + 1);
        const gchar *key = g_variant_get_string(key_v, NULL);
        const gchar *label = g_variant_get_string(label_v, NULL);
        if (key && key[0] != '\0') {
            copy_trunc(out[count].key, sizeof(out[count].key), key);
            copy_trunc(out[count].label, sizeof(out[count].label), label ? label : "");
            count++;
        }
        g_variant_unref(key_v);
        g_variant_unref(label_v);
    }
    return count;
}

static gboolean extract_image_data(GVariant *hints, guint8 *out,
        guint32 *out_w, guint32 *out_h, size_t *out_len) {
    if (!hints) return FALSE;
    GVariant *image = g_variant_lookup_value(hints, "image-data",
        G_VARIANT_TYPE("(iiibiiay)"));
    if (!image) {
        image = g_variant_lookup_value(hints, "image_data",
            G_VARIANT_TYPE("(iiibiiay)"));
    }
    if (!image) return FALSE;

    gint32 width = 0;
    gint32 height = 0;
    gint32 rowstride = 0;
    gboolean has_alpha = FALSE;
    gint32 bits_per_sample = 0;
    gint32 channels = 0;
    GVariant *data = NULL;
    g_variant_get(image, "(iiibii@ay)", &width, &height, &rowstride,
        &has_alpha, &bits_per_sample, &channels, &data);
    gboolean ok = FALSE;
    if (width > 0 && height > 0 && width <= MAX_ICON && height <= MAX_ICON &&
            bits_per_sample == 8 && channels == 4 &&
            rowstride >= width * 4 && data) {
        gsize n = 0;
        const guint8 *raw = g_variant_get_fixed_array(data, &n, 1);
        if (raw && n >= (gsize)rowstride * (gsize)(height - 1) + (gsize)width * 4) {
            for (gint32 y = 0; y < height; y++) {
                for (gint32 x = 0; x < width; x++) {
                    const guint8 *src = raw + (gsize)y * (gsize)rowstride +
                        (gsize)x * 4;
                    guint8 a = has_alpha ? src[0] : 255;
                    guint8 r = src[1];
                    guint8 g = src[2];
                    guint8 b = src[3];
                    if (has_alpha && a != 255) {
                        r = (guint8)(((guint)r * (guint)a + 127) / 255);
                        g = (guint8)(((guint)g * (guint)a + 127) / 255);
                        b = (guint8)(((guint)b * (guint)a + 127) / 255);
                    }
                    guint8 *dst = out + ((gsize)y * (gsize)width +
                        (gsize)x) * 4;
#if G_BYTE_ORDER == G_LITTLE_ENDIAN
                    dst[0] = b;
                    dst[1] = g;
                    dst[2] = r;
                    dst[3] = a;
#else
                    dst[0] = a;
                    dst[1] = r;
                    dst[2] = g;
                    dst[3] = b;
#endif
                }
            }
            *out_w = (guint32)width;
            *out_h = (guint32)height;
            *out_len = (size_t)width * (size_t)height * 4;
            ok = TRUE;
        }
    }
    if (data) g_variant_unref(data);
    g_variant_unref(image);
    return ok;
}

static void extract_icon(const char *app_icon, GVariant *hints,
        char *icon_name, size_t icon_name_cap, guint8 *icon_data,
        guint32 *icon_w, guint32 *icon_h, size_t *icon_len) {
    icon_name[0] = '\0';
    *icon_len = 0;
    *icon_w = 0;
    *icon_h = 0;
    (void)extract_image_data(hints, icon_data, icon_w, icon_h, icon_len);

    GVariant *path = NULL;
    GVariant *name = NULL;
    if (hints) {
        path = g_variant_lookup_value(hints, "image-path", G_VARIANT_TYPE_STRING);
        if (!path) {
            path = g_variant_lookup_value(hints, "image_path", G_VARIANT_TYPE_STRING);
        }
        name = g_variant_lookup_value(hints, "icon-name", G_VARIANT_TYPE_STRING);
    }
    if (path) {
        copy_trunc(icon_name, icon_name_cap, g_variant_get_string(path, NULL));
        g_variant_unref(path);
    } else if (name) {
        copy_trunc(icon_name, icon_name_cap, g_variant_get_string(name, NULL));
        g_variant_unref(name);
        name = NULL;
    } else if (app_icon && app_icon[0] != '\0') {
        copy_trunc(icon_name, icon_name_cap, app_icon);
    }
    if (name) g_variant_unref(name);
}

static void send_notification(guint32 id, guint32 replaces_id, int32_t timeout,
        const char *app, const char *summary, const char *body,
        const NotifyAction *actions, guint32 action_count,
        const char *icon_name, const guint8 *icon_data, guint32 icon_w,
        guint32 icon_h, size_t icon_len) {
    size_t app_len = utf8_prefix(app, MAX_APP);
    size_t summary_len = utf8_prefix(summary, MAX_SUMMARY);
    size_t body_len = utf8_prefix(body, MAX_BODY);
    size_t icon_name_len = utf8_prefix(icon_name, MAX_ICON_NAME);
    if (action_count > MAX_ACTION) action_count = MAX_ACTION;
    if (icon_len > MAX_ICON_BYTES) icon_len = 0;

    unsigned char hdr[48];
    memset(hdr, 0, sizeof(hdr));
    hdr[0] = 1;
    put_u32(hdr + 4, id);
    put_u32(hdr + 8, replaces_id);
    put_u32(hdr + 12, (uint32_t)timeout);
    put_u32(hdr + 16, (uint32_t)app_len);
    put_u32(hdr + 20, (uint32_t)summary_len);
    put_u32(hdr + 24, (uint32_t)body_len);
    put_u32(hdr + 28, action_count);
    put_u32(hdr + 32, (uint32_t)icon_name_len);
    put_u32(hdr + 36, icon_w);
    put_u32(hdr + 40, icon_h);
    put_u32(hdr + 44, (uint32_t)icon_len);
    write_all(hdr, sizeof(hdr));
    if (app_len > 0) write_all(app, app_len);
    if (summary_len > 0) write_all(summary, summary_len);
    if (body_len > 0) write_all(body, body_len);
    if (icon_name_len > 0) write_all(icon_name, icon_name_len);
    if (icon_len > 0) write_all(icon_data, icon_len);
    for (guint32 i = 0; i < action_count; i++) {
        size_t key_len = utf8_prefix(actions[i].key, MAX_ACTION_KEY);
        size_t label_len = utf8_prefix(actions[i].label, MAX_ACTION_LABEL);
        unsigned char ahdr[8];
        put_u32(ahdr, (uint32_t)key_len);
        put_u32(ahdr + 4, (uint32_t)label_len);
        write_all(ahdr, sizeof(ahdr));
        if (key_len > 0) write_all(actions[i].key, key_len);
        if (label_len > 0) write_all(actions[i].label, label_len);
    }
}

static void emit_closed(guint32 id, guint32 reason) {
    if (!bus) return;
    g_dbus_connection_emit_signal(
        bus,
        NULL,
        TESSA_NOTIFICATIONS_PATH,
        TESSA_NOTIFICATIONS_IFACE,
        "NotificationClosed",
        g_variant_new("(uu)", id, reason),
        NULL);
}

static const gchar introspection_xml[] =
    "<node>"
    "  <interface name='" TESSA_NOTIFICATIONS_IFACE "'>"
    "    <method name='Notify'>"
    "      <arg type='s' name='app_name' direction='in'/>"
    "      <arg type='u' name='replaces_id' direction='in'/>"
    "      <arg type='s' name='app_icon' direction='in'/>"
    "      <arg type='s' name='summary' direction='in'/>"
    "      <arg type='s' name='body' direction='in'/>"
    "      <arg type='as' name='actions' direction='in'/>"
    "      <arg type='a{sv}' name='hints' direction='in'/>"
    "      <arg type='i' name='expire_timeout' direction='in'/>"
    "      <arg type='u' name='id' direction='out'/>"
    "    </method>"
    "    <method name='CloseNotification'>"
    "      <arg type='u' name='id' direction='in'/>"
    "    </method>"
    "    <method name='GetCapabilities'>"
    "      <arg type='as' name='capabilities' direction='out'/>"
    "    </method>"
    "    <method name='GetServerInformation'>"
    "      <arg type='s' name='name' direction='out'/>"
    "      <arg type='s' name='vendor' direction='out'/>"
    "      <arg type='s' name='version' direction='out'/>"
    "      <arg type='s' name='spec_version' direction='out'/>"
    "    </method>"
    "    <signal name='NotificationClosed'>"
    "      <arg type='u' name='id'/>"
    "      <arg type='u' name='reason'/>"
    "    </signal>"
    "    <signal name='ActionInvoked'>"
    "      <arg type='u' name='id'/>"
    "      <arg type='s' name='action_key'/>"
    "    </signal>"
    "  </interface>"
    "</node>";

static void on_method_call(GDBusConnection *connection, const gchar *sender,
        const gchar *object_path, const gchar *interface_name,
        const gchar *method_name, GVariant *parameters,
        GDBusMethodInvocation *invocation, gpointer user_data) {
    (void)connection;
    (void)sender;
    (void)object_path;
    (void)interface_name;
    (void)user_data;

    if (g_strcmp0(method_name, "Notify") == 0) {
        const gchar *app_name = "";
        const gchar *app_icon = "";
        const gchar *summary = "";
        const gchar *body = "";
        guint32 replaces_id = 0;
        gint32 timeout = -1;
        GVariant *actions_v = NULL;
        GVariant *hints = NULL;
        g_variant_get(parameters, "(&su&s&s&s@as@a{sv}i)",
            &app_name, &replaces_id, &app_icon, &summary, &body,
            &actions_v, &hints, &timeout);

        NotifyAction actions[MAX_ACTION];
        guint32 action_count = extract_actions(actions_v, actions);
        char icon_name[MAX_ICON_NAME + 1];
        guint8 icon_data[MAX_ICON_BYTES];
        guint32 icon_w = 0;
        guint32 icon_h = 0;
        size_t icon_len = 0;
        extract_icon(app_icon, hints, icon_name, sizeof(icon_name), icon_data,
            &icon_w, &icon_h, &icon_len);
        if (actions_v) g_variant_unref(actions_v);
        if (hints) g_variant_unref(hints);

        guint32 id = replaces_id;
        if (id == 0) {
            id = next_id++;
            if (next_id == 0) next_id = 1;
        }
        if (id == 0) id = 1;
        g_hash_table_add(active, GUINT_TO_POINTER(id));
        send_notification(id, replaces_id, timeout, app_name, summary, body,
            actions, action_count, icon_name, icon_data, icon_w, icon_h,
            icon_len);
        g_dbus_method_invocation_return_value(invocation, g_variant_new("(u)", id));
        return;
    }

    if (g_strcmp0(method_name, "CloseNotification") == 0) {
        guint32 id = 0;
        g_variant_get(parameters, "(u)", &id);
        if (g_hash_table_remove(active, GUINT_TO_POINTER(id))) {
            send_close_event(id);
            emit_closed(id, 3);
        }
        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }

    if (g_strcmp0(method_name, "GetCapabilities") == 0) {
        const gchar *capabilities[] = {
            "actions", "body", "body-markup", "icon-static", "persistence", NULL
        };
        g_dbus_method_invocation_return_value(
            invocation, g_variant_new("(^as)", capabilities));
        return;
    }

    if (g_strcmp0(method_name, "GetServerInformation") == 0) {
        g_dbus_method_invocation_return_value(
            invocation, g_variant_new("(ssss)", "Tessa", "Tessa", "0.1.0", "1.2"));
        return;
    }

    g_dbus_method_invocation_return_dbus_error(
        invocation,
        "org.freedesktop.Notifications.Error.UnknownMethod",
        "Unknown method");
}

static const GDBusInterfaceVTable interface_vtable = {
    .method_call = on_method_call,
    .get_property = NULL,
    .set_property = NULL,
};

static void on_bus_acquired(GDBusConnection *connection, const gchar *name,
        gpointer user_data) {
    (void)name;
    (void)user_data;
    GError *error = NULL;
    GDBusNodeInfo *info = g_dbus_node_info_new_for_xml(introspection_xml, &error);
    if (!info) {
        send_error(error ? error->message : "invalid notification interface");
        if (error) g_error_free(error);
        return;
    }
    guint registration = g_dbus_connection_register_object(
        connection, TESSA_NOTIFICATIONS_PATH, info->interfaces[0],
        &interface_vtable, NULL, NULL, &error);
    g_dbus_node_info_unref(info);
    if (registration == 0) {
        send_error(error ? error->message : "cannot register notification object");
        if (error) g_error_free(error);
        return;
    }
    bus = connection;
}

static void on_name_acquired(GDBusConnection *connection, const gchar *name,
        gpointer user_data) {
    (void)connection;
    (void)name;
    (void)user_data;
    send_ready();
}

static void on_name_lost(GDBusConnection *connection, const gchar *name,
        gpointer user_data) {
    (void)connection;
    (void)name;
    (void)user_data;
    if (!stopping) {
        send_error("cannot own org.freedesktop.Notifications");
        if (loop) g_main_loop_quit(loop);
    }
}

static gboolean close_request_cb(gpointer data) {
    CloseRequest *req = data;
    if (active && g_hash_table_remove(active, GUINT_TO_POINTER(req->id))) {
        emit_closed(req->id, req->reason);
    }
    g_free(req);
    return G_SOURCE_REMOVE;
}

static gboolean action_request_cb(gpointer data) {
    ActionRequest *req = data;
    if (bus && active && g_hash_table_remove(active, GUINT_TO_POINTER(req->id))) {
        g_dbus_connection_emit_signal(
            bus,
            NULL,
            TESSA_NOTIFICATIONS_PATH,
            TESSA_NOTIFICATIONS_IFACE,
            "ActionInvoked",
            g_variant_new("(us)", req->id, req->key),
            NULL);
        emit_closed(req->id, 2);
    }
    g_free(req->key);
    g_free(req);
    return G_SOURCE_REMOVE;
}

static gpointer notifications_thread(gpointer data) {
    (void)data;
    active = g_hash_table_new(g_direct_hash, g_direct_equal);
    loop = g_main_loop_new(NULL, FALSE);
    if (stopping) {
        g_main_loop_unref(loop);
        loop = NULL;
        g_hash_table_destroy(active);
        active = NULL;
        return NULL;
    }
    owner_id = g_bus_own_name(
        G_BUS_TYPE_SESSION,
        TESSA_NOTIFICATIONS_NAME,
        G_BUS_NAME_OWNER_FLAGS_NONE,
        on_bus_acquired,
        on_name_acquired,
        on_name_lost,
        NULL,
        NULL);
    g_main_loop_run(loop);
    if (owner_id != 0) {
        g_bus_unown_name(owner_id);
        owner_id = 0;
    }
    bus = NULL;
    g_main_loop_unref(loop);
    loop = NULL;
    g_hash_table_destroy(active);
    active = NULL;
    return NULL;
}

int tessa_notifications_start(void) {
    if (sock_read >= 0) return sock_read;
    stopping = FALSE;
    int fds[2];
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, fds) != 0) return -1;
    sock_read = fds[0];
    sock_write = fds[1];
    thread = g_thread_new("tessa-notifications", notifications_thread, NULL);
    return sock_read;
}

void tessa_notifications_stop(void) {
    stopping = TRUE;
    if (loop) g_main_loop_quit(loop);
    if (thread) {
        g_thread_join(thread);
        thread = NULL;
    }
    if (sock_read >= 0) {
        close(sock_read);
        sock_read = -1;
    }
    if (sock_write >= 0) {
        close(sock_write);
        sock_write = -1;
    }
}

void tessa_notifications_close(unsigned int id, unsigned int reason) {
    if (!active) return;
    CloseRequest *req = g_new0(CloseRequest, 1);
    req->id = id;
    req->reason = reason;
    g_main_context_invoke(NULL, close_request_cb, req);
}

void tessa_notifications_action(unsigned int id, const char *key) {
    if (!active || !key) return;
    ActionRequest *req = g_new0(ActionRequest, 1);
    req->id = id;
    req->key = g_strdup(key);
    g_main_context_invoke(NULL, action_request_cb, req);
}
