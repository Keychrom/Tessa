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

static void send_notification(guint32 id, guint32 replaces_id, int32_t timeout,
        const char *app, const char *summary, const char *body) {
    size_t app_len = utf8_prefix(app, MAX_APP);
    size_t summary_len = utf8_prefix(summary, MAX_SUMMARY);
    size_t body_len = utf8_prefix(body, MAX_BODY);
    unsigned char hdr[28];
    memset(hdr, 0, sizeof(hdr));
    hdr[0] = 1;
    put_u32(hdr + 4, id);
    put_u32(hdr + 8, replaces_id);
    put_u32(hdr + 12, (uint32_t)timeout);
    put_u32(hdr + 16, (uint32_t)app_len);
    put_u32(hdr + 20, (uint32_t)summary_len);
    put_u32(hdr + 24, (uint32_t)body_len);
    write_all(hdr, sizeof(hdr));
    if (app_len > 0) write_all(app, app_len);
    if (summary_len > 0) write_all(summary, summary_len);
    if (body_len > 0) write_all(body, body_len);
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
        GVariant *actions = NULL;
        GVariant *hints = NULL;
        g_variant_get(parameters, "(&su&s&s&s@as@a{sv}i)",
            &app_name, &replaces_id, &app_icon, &summary, &body,
            &actions, &hints, &timeout);
        (void)app_icon;
        if (actions) g_variant_unref(actions);
        if (hints) g_variant_unref(hints);

        guint32 id = replaces_id;
        if (id == 0) {
            id = next_id++;
            if (next_id == 0) next_id = 1;
        }
        if (id == 0) id = 1;
        g_hash_table_add(active, GUINT_TO_POINTER(id));
        send_notification(id, replaces_id, timeout, app_name, summary, body);
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
        const gchar *capabilities[] = { "body", "persistence", NULL };
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
