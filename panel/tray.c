#define _GNU_SOURCE

#include "tray.h"

#include <gio/gio.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define WATCHER_NAME "org.kde.StatusNotifierWatcher"
#define WATCHER_PATH "/StatusNotifierWatcher"
#define WATCHER_IFACE "org.kde.StatusNotifierWatcher"
#define SNI_IFACE "org.kde.StatusNotifierItem"
#define PROPS_IFACE "org.freedesktop.DBus.Properties"

#define MAX_TRAY_ITEMS 8
#define MAX_SERVICE 255
#define MAX_PATH 255
#define MAX_TITLE 159
#define MAX_ICON_NAME 127
#define MAX_ICON_DIM 32
#define MAX_ERROR 200

typedef struct {
    char service[MAX_SERVICE + 1];
    char path[MAX_PATH + 1];
    char title[MAX_TITLE + 1];
    char icon_name[MAX_ICON_NAME + 1];
    guint8 status;
    guint8 icon_w;
    guint8 icon_h;
    size_t icon_len;
    guint8 icon_data[MAX_ICON_DIM * MAX_ICON_DIM * 4];
} TrayItem;

static GMainLoop *loop;
static GThread *thread;
static GDBusConnection *bus;
static guint owner_id;
static guint timeout_id;
static int sock_read = -1;
static int sock_write = -1;
static gboolean stopping;
static TrayItem items[MAX_TRAY_ITEMS];
static guint item_count;
static GByteArray *last_state;

typedef struct {
    guint32 index;
    guint32 code;
} TrayCommand;

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

static void send_ready(void) {
    const unsigned char type = 2;
    write_all(&type, 1);
}

static void send_error(const char *message) {
    unsigned char hdr[5];
    hdr[0] = 3;
    size_t len = strlen(message);
    if (len > MAX_ERROR) len = MAX_ERROR;
    put_u32(hdr + 1, (uint32_t)len);
    write_all(hdr, sizeof(hdr));
    write_all(message, len);
}

static void append_u32(GByteArray *out, uint32_t v) {
    unsigned char raw[4];
    put_u32(raw, v);
    g_byte_array_append(out, raw, sizeof(raw));
}

static GVariant *registered_items_variant(void) {
    GVariantBuilder builder;
    g_variant_builder_init(&builder, G_VARIANT_TYPE("as"));
    for (guint i = 0; i < item_count; i++) {
        g_variant_builder_add(&builder, "s", items[i].service);
    }
    return g_variant_builder_end(&builder);
}

static void emit_registered(const char *service) {
    if (!bus) return;
    g_dbus_connection_emit_signal(
        bus,
        NULL,
        WATCHER_PATH,
        WATCHER_IFACE,
        "StatusNotifierItemRegistered",
        g_variant_new("(s)", service),
        NULL);
}

static void emit_unregistered(const char *service) {
    if (!bus) return;
    g_dbus_connection_emit_signal(
        bus,
        NULL,
        WATCHER_PATH,
        WATCHER_IFACE,
        "StatusNotifierItemUnregistered",
        g_variant_new("(s)", service),
        NULL);
}

static gboolean poll_tray(void);

static void remove_item(guint index) {
    if (index >= item_count) return;
    char service[MAX_SERVICE + 1];
    copy_trunc(service, sizeof(service), items[index].service);
    for (guint i = index + 1; i < item_count; i++) {
        items[i - 1] = items[i];
    }
    item_count--;
    memset(&items[item_count], 0, sizeof(items[item_count]));
    emit_unregistered(service);
}

static void clear_item_icon(TrayItem *item) {
    item->icon_w = 0;
    item->icon_h = 0;
    item->icon_len = 0;
}

static gboolean query_item(guint index) {
    if (index >= item_count) return FALSE;
    TrayItem *item = &items[index];
    if (!bus || item->service[0] == '\0') return FALSE;

    GError *error = NULL;
    GVariant *reply = g_dbus_connection_call_sync(
        bus,
        item->service,
        item->path,
        PROPS_IFACE,
        "GetAll",
        g_variant_new("(s)", SNI_IFACE),
        G_VARIANT_TYPE("(a{sv})"),
        G_DBUS_CALL_FLAGS_NONE,
        500,
        NULL,
        &error);
    if (!reply) {
        if (error) g_error_free(error);
        return FALSE;
    }

    GVariant *dict = NULL;
    g_variant_get(reply, "(@a{sv})", &dict);

    const gchar *title = "";
    const gchar *id = "";
    const gchar *icon_name = "";
    guint8 status = 0;
    guint8 icon_w = 0;
    guint8 icon_h = 0;
    guint8 icon_data[MAX_ICON_DIM * MAX_ICON_DIM * 4];
    size_t icon_len = 0;

    GVariant *value = g_variant_lookup_value(dict, "Title", G_VARIANT_TYPE_STRING);
    if (value) {
        title = g_variant_get_string(value, NULL);
        g_variant_unref(value);
    }
    value = g_variant_lookup_value(dict, "Id", G_VARIANT_TYPE_STRING);
    if (value) {
        id = g_variant_get_string(value, NULL);
        g_variant_unref(value);
    }
    value = g_variant_lookup_value(dict, "Status", G_VARIANT_TYPE_STRING);
    if (value) {
        const gchar *s = g_variant_get_string(value, NULL);
        if (g_strcmp0(s, "Active") == 0) status = 1;
        else if (g_strcmp0(s, "NeedsAttention") == 0) status = 2;
        else status = 0;
        g_variant_unref(value);
    }
    value = g_variant_lookup_value(dict, "IconName", G_VARIANT_TYPE_STRING);
    if (value) {
        icon_name = g_variant_get_string(value, NULL);
        g_variant_unref(value);
    }

    GVariant *pixmaps = g_variant_lookup_value(dict, "IconPixmap", G_VARIANT_TYPE("a(iiay)"));
    if (pixmaps) {
        gsize n = g_variant_n_children(pixmaps);
        for (gsize i = 0; i < n; i++) {
            GVariant *child = g_variant_get_child_value(pixmaps, i);
            gint32 w = 0;
            gint32 h = 0;
            GVariant *bytes = NULL;
            g_variant_get(child, "(ii@ay)", &w, &h, &bytes);
            if (bytes) {
                gsize len = 0;
                const guint8 *data = g_variant_get_fixed_array(bytes, &len, 1);
                if (w > 0 && h > 0 && w <= MAX_ICON_DIM && h <= MAX_ICON_DIM &&
                        len >= (gsize)w * (gsize)h * 4) {
                    size_t need = (size_t)w * (size_t)h * 4;
                    /* Prefer the largest icon that still fits our budget. */
                    if (need >= icon_len) {
                        icon_w = (guint8)w;
                        icon_h = (guint8)h;
                        icon_len = need;
                        memcpy(icon_data, data, need);
                    }
                }
                g_variant_unref(bytes);
            }
            g_variant_unref(child);
        }
        g_variant_unref(pixmaps);
    }

    if (title[0] == '\0') {
        if (id[0] != '\0') {
            copy_trunc(item->title, sizeof(item->title), id);
        } else {
            const char *dot = strrchr(item->service, '.');
            copy_trunc(item->title, sizeof(item->title), dot ? dot + 1 : item->service);
        }
    } else {
        copy_trunc(item->title, sizeof(item->title), title);
    }
    copy_trunc(item->icon_name, sizeof(item->icon_name), icon_name);
    item->status = status;
    clear_item_icon(item);
    if (icon_len > 0) {
        item->icon_w = icon_w;
        item->icon_h = icon_h;
        item->icon_len = icon_len;
        memcpy(item->icon_data, icon_data, icon_len);
    }

    g_variant_unref(dict);
    g_variant_unref(reply);
    return TRUE;
}

static void send_state(void) {
    GByteArray *msg = g_byte_array_new();
    unsigned char hdr[5];
    memset(hdr, 0, sizeof(hdr));
    hdr[0] = 1;
    put_u32(hdr + 1, item_count);
    g_byte_array_append(msg, hdr, sizeof(hdr));

    for (guint i = 0; i < item_count; i++) {
        TrayItem *item = &items[i];
        size_t title_len = strlen(item->title);
        size_t icon_name_len = strlen(item->icon_name);
        unsigned char item_hdr[24];
        memset(item_hdr, 0, sizeof(item_hdr));
        item_hdr[0] = item->status;
        put_u32(item_hdr + 4, (uint32_t)title_len);
        put_u32(item_hdr + 8, (uint32_t)icon_name_len);
        put_u32(item_hdr + 12, item->icon_w);
        put_u32(item_hdr + 16, item->icon_h);
        put_u32(item_hdr + 20, (uint32_t)item->icon_len);
        g_byte_array_append(msg, item_hdr, sizeof(item_hdr));
        if (title_len > 0) g_byte_array_append(msg, (const guint8 *)item->title, title_len);
        if (icon_name_len > 0) {
            g_byte_array_append(msg, (const guint8 *)item->icon_name, icon_name_len);
        }
        if (item->icon_len > 0) {
            g_byte_array_append(msg, item->icon_data, item->icon_len);
        }
    }

    if (last_state && last_state->len == msg->len &&
            memcmp(last_state->data, msg->data, msg->len) == 0) {
        g_byte_array_unref(msg);
        return;
    }
    if (last_state) g_byte_array_unref(last_state);
    last_state = g_byte_array_ref(msg);
    write_all(msg->data, msg->len);
    g_byte_array_unref(msg);
}

static gboolean poll_tray(void) {
    if (!bus) return G_SOURCE_REMOVE;
    guint i = 0;
    while (i < item_count) {
        if (query_item(i)) {
            i++;
        } else {
            remove_item(i);
        }
    }
    send_state();
    return G_SOURCE_REMOVE;
}

static gboolean poll_cb(gpointer data) {
    (void)data;
    poll_tray();
    return G_SOURCE_CONTINUE;
}

static gboolean poll_once_cb(gpointer data) {
    (void)data;
    return poll_tray();
}

static gboolean command_cb(gpointer data) {
    TrayCommand *command = data;
    if (bus && command->index < item_count) {
        TrayItem *item = &items[command->index];
        const char *method = command->code == 2 ? "SecondaryActivate" : "Activate";
        g_dbus_connection_call(
            bus,
            item->service,
            item->path,
            SNI_IFACE,
            method,
            g_variant_new("(ii)", 0, 0),
            NULL,
            G_DBUS_CALL_FLAGS_NONE,
            1000,
            NULL,
            NULL,
            NULL);
    }
    g_free(command);
    return G_SOURCE_REMOVE;
}

static const gchar introspection_xml[] =
    "<node>"
    "  <interface name='" WATCHER_IFACE "'>"
    "    <method name='RegisterStatusNotifierItem'>"
    "      <arg type='s' name='service' direction='in'/>"
    "    </method>"
    "    <method name='RegisterStatusNotifierHost'>"
    "      <arg type='s' name='service' direction='in'/>"
    "    </method>"
    "    <property name='RegisteredStatusNotifierItems' type='as' access='read'/>"
    "    <property name='IsStatusNotifierHostRegistered' type='b' access='read'/>"
    "    <property name='ProtocolVersion' type='i' access='read'/>"
    "    <signal name='StatusNotifierItemRegistered'>"
    "      <arg type='s' name='service'/>"
    "    </signal>"
    "    <signal name='StatusNotifierItemUnregistered'>"
    "      <arg type='s' name='service'/>"
    "    </signal>"
    "    <signal name='StatusNotifierHostRegistered'/>"
    "  </interface>"
    "  <interface name='" PROPS_IFACE "'>"
    "    <method name='Get'>"
    "      <arg type='s' name='interface_name' direction='in'/>"
    "      <arg type='s' name='property_name' direction='in'/>"
    "      <arg type='v' name='value' direction='out'/>"
    "    </method>"
    "    <method name='GetAll'>"
    "      <arg type='s' name='interface_name' direction='in'/>"
    "      <arg type='a{sv}' name='values' direction='out'/>"
    "    </method>"
    "  </interface>"
    "</node>";

static void register_item(const char *service, const char *path) {
    if (!service || service[0] == '\0' || !path || path[0] == '\0') return;
    for (guint i = 0; i < item_count; i++) {
        if (g_strcmp0(items[i].service, service) == 0 &&
                g_strcmp0(items[i].path, path) == 0) {
            return;
        }
    }
    if (item_count >= MAX_TRAY_ITEMS) return;
    TrayItem *item = &items[item_count++];
    memset(item, 0, sizeof(*item));
    copy_trunc(item->service, sizeof(item->service), service);
    copy_trunc(item->path, sizeof(item->path), path);
    const char *dot = strrchr(service, '.');
    copy_trunc(item->title, sizeof(item->title), dot ? dot + 1 : service);
    emit_registered(service);
}

static void on_watcher_method(GDBusConnection *connection, const gchar *sender,
        const gchar *object_path, const gchar *interface_name,
        const gchar *method_name, GVariant *parameters,
        GDBusMethodInvocation *invocation, gpointer user_data) {
    (void)connection;
    (void)object_path;
    (void)interface_name;
    (void)user_data;

    if (g_strcmp0(method_name, "RegisterStatusNotifierItem") == 0) {
        const gchar *arg = "";
        g_variant_get(parameters, "(&s)", &arg);
        if (arg[0] == '/') {
            register_item(sender, arg);
        } else if (arg[0] != '\0') {
            register_item(arg, "/StatusNotifierItem");
        } else {
            register_item(sender, "/StatusNotifierItem");
        }
        /* The item may be blocked in the synchronous Register call. Polling
         * from inside this handler would deadlock against its main loop. */
        g_timeout_add(200, poll_once_cb, NULL);
        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }

    if (g_strcmp0(method_name, "RegisterStatusNotifierHost") == 0) {
        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }

    g_dbus_method_invocation_return_dbus_error(
        invocation,
        "org.kde.StatusNotifierWatcher.Error.UnknownMethod",
        "Unknown method");
}

static void on_properties_method(GDBusConnection *connection, const gchar *sender,
        const gchar *object_path, const gchar *interface_name,
        const gchar *method_name, GVariant *parameters,
        GDBusMethodInvocation *invocation, gpointer user_data) {
    (void)connection;
    (void)object_path;
    (void)interface_name;
    (void)user_data;

    if (g_strcmp0(method_name, "GetAll") == 0) {
        const gchar *iface = "";
        g_variant_get(parameters, "(&s)", &iface);
        if (g_strcmp0(iface, WATCHER_IFACE) != 0) {
            g_dbus_method_invocation_return_dbus_error(
                invocation,
                "org.freedesktop.DBus.Error.InvalidArgs",
                "Unknown interface");
            return;
        }
        GVariantBuilder builder;
        g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
        g_variant_builder_add(&builder, "{sv}", "RegisteredStatusNotifierItems",
            registered_items_variant());
        g_variant_builder_add(&builder, "{sv}", "IsStatusNotifierHostRegistered",
            g_variant_new_boolean(TRUE));
        g_variant_builder_add(&builder, "{sv}", "ProtocolVersion",
            g_variant_new_int32(0));
        g_dbus_method_invocation_return_value(
            invocation, g_variant_new("(@a{sv})", g_variant_builder_end(&builder)));
        return;
    }

    if (g_strcmp0(method_name, "Get") == 0) {
        const gchar *iface = "";
        const gchar *property = "";
        g_variant_get(parameters, "(&s&s)", &iface, &property);
        if (g_strcmp0(iface, WATCHER_IFACE) == 0) {
            if (g_strcmp0(property, "RegisteredStatusNotifierItems") == 0) {
                g_dbus_method_invocation_return_value(
                    invocation, g_variant_new("(v)", registered_items_variant()));
                return;
            }
            if (g_strcmp0(property, "IsStatusNotifierHostRegistered") == 0) {
                g_dbus_method_invocation_return_value(
                    invocation, g_variant_new("(v)", g_variant_new_boolean(TRUE)));
                return;
            }
            if (g_strcmp0(property, "ProtocolVersion") == 0) {
                g_dbus_method_invocation_return_value(
                    invocation, g_variant_new("(v)", g_variant_new_int32(0)));
                return;
            }
        }
        g_dbus_method_invocation_return_dbus_error(
            invocation,
            "org.freedesktop.DBus.Error.UnknownProperty",
            "Unknown property");
        return;
    }

    g_dbus_method_invocation_return_dbus_error(
        invocation,
        "org.freedesktop.DBus.Error.UnknownMethod",
        "Unknown method");
}

static const GDBusInterfaceVTable watcher_vtable = {
    .method_call = on_watcher_method,
    .get_property = NULL,
    .set_property = NULL,
};

static const GDBusInterfaceVTable properties_vtable = {
    .method_call = on_properties_method,
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
        send_error(error ? error->message : "invalid tray interface");
        if (error) g_error_free(error);
        return;
    }
    guint watcher_registration = g_dbus_connection_register_object(
        connection, WATCHER_PATH, info->interfaces[0],
        &watcher_vtable, NULL, NULL, &error);
    if (watcher_registration == 0) {
        send_error(error ? error->message : "cannot register tray watcher");
        if (error) g_error_free(error);
        g_dbus_node_info_unref(info);
        return;
    }
    guint props_registration = g_dbus_connection_register_object(
        connection, WATCHER_PATH, info->interfaces[1],
        &properties_vtable, NULL, NULL, &error);
    g_dbus_node_info_unref(info);
    if (props_registration == 0) {
        send_error(error ? error->message : "cannot register tray properties");
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
    if (timeout_id == 0) {
        timeout_id = g_timeout_add(1000, poll_cb, NULL);
    }
    send_ready();
}

static void on_name_lost(GDBusConnection *connection, const gchar *name,
        gpointer user_data) {
    (void)connection;
    (void)name;
    (void)user_data;
    if (!stopping) {
        item_count = 0;
        send_state();
        send_error("cannot own org.kde.StatusNotifierWatcher");
        if (loop) g_main_loop_quit(loop);
    }
}

static gpointer tray_thread(gpointer data) {
    (void)data;
    loop = g_main_loop_new(NULL, FALSE);
    if (stopping) {
        g_main_loop_unref(loop);
        loop = NULL;
        return NULL;
    }
    owner_id = g_bus_own_name(
        G_BUS_TYPE_SESSION,
        WATCHER_NAME,
        G_BUS_NAME_OWNER_FLAGS_NONE,
        on_bus_acquired,
        on_name_acquired,
        on_name_lost,
        NULL,
        NULL);
    g_main_loop_run(loop);
    if (timeout_id != 0) {
        g_source_remove(timeout_id);
        timeout_id = 0;
    }
    if (owner_id != 0) {
        g_bus_unown_name(owner_id);
        owner_id = 0;
    }
    bus = NULL;
    g_main_loop_unref(loop);
    loop = NULL;
    item_count = 0;
    if (last_state) {
        g_byte_array_unref(last_state);
        last_state = NULL;
    }
    return NULL;
}

int tessa_tray_start(void) {
    if (sock_read >= 0) return sock_read;
    int fds[2];
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, fds) != 0) return -1;
    sock_read = fds[0];
    sock_write = fds[1];
    thread = g_thread_new("tessa-tray", tray_thread, NULL);
    return sock_read;
}

void tessa_tray_stop(void) {
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

void tessa_tray_activate(unsigned int index, unsigned int code) {
    if (!bus) return;
    TrayCommand *command = g_new0(TrayCommand, 1);
    command->index = index;
    command->code = code;
    g_main_context_invoke(NULL, command_cb, command);
}
