#include "system.h"

#include <gio/gio.h>
#include <glib.h>
#include <math.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define NM_NAME "org.freedesktop.NetworkManager"
#define NM_PATH "/org/freedesktop/NetworkManager"
#define NM_IFACE "org.freedesktop.NetworkManager"
#define NM_DEVICE "org.freedesktop.NetworkManager.Device"
#define NM_WIRELESS "org.freedesktop.NetworkManager.Device.Wireless"
#define NM_AP "org.freedesktop.NetworkManager.AccessPoint"
#define NM_SETTINGS "org.freedesktop.NetworkManager.Settings"
#define NM_CONNECTION "org.freedesktop.NetworkManager.Settings.Connection"
#define NM_ACTIVE "org.freedesktop.NetworkManager.Connection.Active"

#define BLUEZ_NAME "org.bluez"
#define BLUEZ_ROOT "/"
#define ADAPTER_IFACE "org.bluez.Adapter1"
#define DEVICE_IFACE "org.bluez.Device1"
#define BATTERY_IFACE "org.bluez.Battery1"
#define AGENT_MANAGER "org.bluez.AgentManager1"

#define LOGIN_NAME "org.freedesktop.login1"
#define LOGIN_PATH "/org/freedesktop/login1"
#define LOGIN_MANAGER "org.freedesktop.login1.Manager"
#define LOGIN_SESSION "org.freedesktop.login1.Session"

#define PPD_NAME "org.freedesktop.UPower.PowerProfiles"
#define PPD_PATH "/org/freedesktop/UPower/PowerProfiles"
#define PPD_IFACE "org.freedesktop.UPower.PowerProfiles"

#define MAX_APS 32
#define MAX_DEVICES 24
#define MAX_SAVED 32
#define MAX_STR 160
#define MAX_PATH 256
#define MAX_SSID 65
#define MAX_NAME 96

#define FEATURE_WIFI (1u << 0)
#define FEATURE_BT (1u << 1)
#define FEATURE_BRIGHTNESS (1u << 6)
#define FEATURE_PPD (1u << 7)

#define AP_SECURED (1u << 0)
#define AP_SAVED (1u << 1)
#define AP_ACTIVE (1u << 2)
#define AP_SAE (1u << 3)
#define AP_ENTERPRISE (1u << 4)

enum {
    FRAME_STATE = 1,
    FRAME_READY = 2,
    FRAME_ERROR = 3,
    FRAME_AGENT = 4,
    FRAME_AGENT_CANCEL = 5,
};

enum {
    AGENT_NONE = 0,
    AGENT_CONFIRM = 1,
    AGENT_PIN = 2,
    AGENT_PASSKEY = 3,
    AGENT_DISPLAY = 4,
    AGENT_AUTHORIZE = 5,
};

typedef struct {
    char ssid[MAX_SSID];
    guint8 ssid_len;
    guint8 signal;
    guint32 flags;
    char path[MAX_PATH];
    char conn_path[MAX_PATH];
} WifiAp;

typedef struct {
    char path[MAX_PATH];
    char name[MAX_NAME];
    guint8 icon;
    guint8 flags;
    gint16 rssi;
    gint8 battery;
} BtDevice;

typedef struct {
    char ssid[MAX_SSID];
    guint8 ssid_len;
    char path[MAX_PATH];
} SavedConn;

static GMainContext *ctx;
static GMainLoop *loop;
static GThread *thread;
static GDBusConnection *bus;
static int sock_read = -1;
static int sock_write = -1;
static gboolean stopping;
static guint32 features = 0xffffffffu;
static guint poll_source;
static guint object_registration;

static void send_state(void);

static gboolean wifi_present;
static gboolean wifi_enabled;
static gboolean wifi_hw_enabled;
static gboolean wifi_scanning;
static guint8 wifi_state;
static char wifi_dev[MAX_PATH];
static char wifi_ssid[MAX_SSID];
static guint8 wifi_ssid_len;
static guint8 wifi_signal;
static char wifi_error[MAX_STR];
static WifiAp aps[MAX_APS];
static guint ap_count;
static SavedConn saved[MAX_SAVED];
static guint saved_count;

static gboolean bt_present;
static gboolean bt_powered;
static gboolean bt_discovering;
static char bt_adapter[MAX_PATH];
static char bt_name[MAX_NAME];
static char bt_error[MAX_STR];
static BtDevice bt_devices[MAX_DEVICES];
static guint bt_count;

static gboolean bl_present;
static char bl_name[64];
static guint32 bl_max;
static gint bl_percent = -1;
static gboolean ppd_available;
static char ppd_profile[32];
static char ppd_profiles[4][32];
static guint ppd_profile_count;

static GDBusMethodInvocation *agent_call;
static int agent_kind;

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

static void send_frame(guint8 type, const guint8 *payload, guint32 len) {
    if (sock_write < 0) return;
    unsigned char hdr[5];
    hdr[0] = type;
    put_u32(hdr + 1, len);
    write_all(hdr, sizeof(hdr));
    if (len > 0) write_all(payload, len);
}

static void send_ready(void) {
    send_frame(FRAME_READY, NULL, 0);
}

static void send_error(const char *message) {
    if (!message) return;
    size_t len = strlen(message);
    if (len > 200) len = 200;
    send_frame(FRAME_ERROR, (const guint8 *)message, (guint32)len);
}

static void copy_trunc(char *dest, size_t cap, const char *src) {
    if (!src) {
        if (cap > 0) dest[0] = '\0';
        return;
    }
    size_t len = strlen(src);
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (((unsigned char)src[len]) & 0xc0) == 0x80) len--;
    }
    memcpy(dest, src, len);
    dest[len] = '\0';
}

static void copy_ssid(char *dest, size_t cap, const guint8 *src, gsize len) {
    if (len > cap - 1) len = cap - 1;
    memcpy(dest, src, len);
    dest[len] = '\0';
}

static void tlv_add(GByteArray *b, guint8 tag, const void *data, guint16 len) {
    guint8 head[3];
    head[0] = tag;
    head[1] = (guint8)(len & 0xff);
    head[2] = (guint8)((len >> 8) & 0xff);
    g_byte_array_append(b, head, sizeof(head));
    if (len > 0) g_byte_array_append(b, data, len);
}

static void tlv_u8(GByteArray *b, guint8 tag, guint8 v) {
    tlv_add(b, tag, &v, 1);
}

static void tlv_u16(GByteArray *b, guint8 tag, guint16 v) {
    guint8 data[2] = { (guint8)(v & 0xff), (guint8)((v >> 8) & 0xff) };
    tlv_add(b, tag, data, 2);
}

static void tlv_u32(GByteArray *b, guint8 tag, guint32 v) {
    guint8 data[4];
    data[0] = (guint8)(v & 0xff);
    data[1] = (guint8)((v >> 8) & 0xff);
    data[2] = (guint8)((v >> 16) & 0xff);
    data[3] = (guint8)((v >> 24) & 0xff);
    tlv_add(b, tag, data, 4);
}

static void tlv_str(GByteArray *b, guint8 tag, const char *s) {
    size_t len = s ? strlen(s) : 0;
    if (len > 65535) len = 65535;
    tlv_add(b, tag, s, (guint16)len);
}

static GVariant *get_all(const char *name, const char *path, const char *iface) {
    if (!bus) return NULL;
    GError *err = NULL;
    GVariant *reply = g_dbus_connection_call_sync(
        bus, name, path, "org.freedesktop.DBus.Properties", "GetAll",
        g_variant_new("(s)", iface), G_VARIANT_TYPE("(a{sv})"),
        G_DBUS_CALL_FLAGS_NONE, 1500, NULL, &err);
    if (!reply) {
        if (err) g_error_free(err);
        return NULL;
    }
    GVariant *dict = g_variant_get_child_value(reply, 0);
    g_variant_unref(reply);
    return dict;
}

static gboolean dict_bool(GVariant *dict, const char *key, gboolean fallback) {
    if (!dict) return fallback;
    gboolean v = fallback;
    if (g_variant_lookup(dict, key, "b", &v)) return v;
    return fallback;
}

static guint32 dict_u32(GVariant *dict, const char *key, guint32 fallback) {
    if (!dict) return fallback;
    guint32 v = fallback;
    if (g_variant_lookup(dict, key, "u", &v)) return v;
    return fallback;
}

static guint8 dict_u8(GVariant *dict, const char *key, guint8 fallback) {
    if (!dict) return fallback;
    guint8 v = fallback;
    if (g_variant_lookup(dict, key, "y", &v)) return v;
    return fallback;
}

static const char *dict_string(GVariant *dict, const char *key, char *buf, size_t cap) {
    buf[0] = '\0';
    if (!dict) return buf;
    const gchar *s = NULL;
    if (g_variant_lookup(dict, key, "&s", &s) && s) copy_trunc(buf, cap, s);
    return buf;
}

static gboolean dict_object_path(GVariant *dict, const char *key, char *buf, size_t cap) {
    buf[0] = '\0';
    if (!dict) return FALSE;
    GVariant *v = g_variant_lookup_value(dict, key, G_VARIANT_TYPE_OBJECT_PATH);
    if (!v) return FALSE;
    const gchar *s = g_variant_get_string(v, NULL);
    if (s) copy_trunc(buf, cap, s);
    g_variant_unref(v);
    return s != NULL;
}

static gboolean dict_ssid(GVariant *dict, char *buf, size_t cap, guint8 *out_len) {
    buf[0] = '\0';
    if (out_len) *out_len = 0;
    if (!dict) return FALSE;
    GVariant *v = g_variant_lookup_value(dict, "Ssid", G_VARIANT_TYPE("ay"));
    if (!v) v = g_variant_lookup_value(dict, "ssid", G_VARIANT_TYPE("ay"));
    if (!v) return FALSE;
    gsize len = 0;
    const guint8 *data = g_variant_get_fixed_array(v, &len, 1);
    if (data && len > 0) {
        copy_ssid(buf, cap, data, len);
        if (out_len) *out_len = (guint8)(len > 255 ? 255 : len);
    }
    g_variant_unref(v);
    return len > 0;
}

static void load_saved_connections(void) {
    saved_count = 0;
    if (!bus) return;
    GError *err = NULL;
    GVariant *reply = g_dbus_connection_call_sync(
        bus, NM_NAME, NM_PATH, NM_SETTINGS, "ListConnections",
        NULL, G_VARIANT_TYPE("(ao)"), G_DBUS_CALL_FLAGS_NONE, 1500, NULL, &err);
    if (!reply) {
        if (err) g_error_free(err);
        return;
    }
    GVariant *paths = g_variant_get_child_value(reply, 0);
    gsize n = g_variant_n_children(paths);
    for (gsize i = 0; i < n && saved_count < MAX_SAVED; i++) {
        GVariant *pv = g_variant_get_child_value(paths, i);
        const gchar *path = g_variant_get_string(pv, NULL);
        GVariant *settings = get_all(NM_NAME, path, NM_CONNECTION);
        if (settings) {
            GVariant *wifi = g_variant_lookup_value(settings, "802-11-wireless", G_VARIANT_TYPE("a{sv}"));
            if (wifi) {
                char ssid[MAX_SSID];
                guint8 len = 0;
                if (dict_ssid(wifi, ssid, sizeof(ssid), &len) && len > 0) {
                    memcpy(saved[saved_count].ssid, ssid, sizeof(ssid));
                    saved[saved_count].ssid_len = len;
                    copy_trunc(saved[saved_count].path, sizeof(saved[saved_count].path), path);
                    saved_count++;
                }
                g_variant_unref(wifi);
            }
            g_variant_unref(settings);
        }
        g_variant_unref(pv);
    }
    g_variant_unref(paths);
    g_variant_unref(reply);
}

static int saved_for_ssid(const char *ssid, guint8 len, char *path, size_t cap) {
    for (guint i = 0; i < saved_count; i++) {
        if (saved[i].ssid_len == len && memcmp(saved[i].ssid, ssid, len) == 0) {
            copy_trunc(path, cap, saved[i].path);
            return 1;
        }
    }
    return 0;
}

static void poll_wifi(void) {
    if (!(features & FEATURE_WIFI)) return;
    if (!bus) {
        copy_trunc(wifi_error, sizeof(wifi_error), "System bus unavailable");
        return;
    }
    GVariant *root = get_all(NM_NAME, NM_PATH, NM_IFACE);
    if (!root) {
        wifi_present = FALSE;
        wifi_enabled = FALSE;
        copy_trunc(wifi_error, sizeof(wifi_error), "NetworkManager is not running");
        return;
    }
    wifi_error[0] = '\0';
    wifi_enabled = dict_bool(root, "WirelessEnabled", FALSE);
    wifi_hw_enabled = dict_bool(root, "WirelessHardwareEnabled", FALSE);

    GVariant *devices = g_variant_lookup_value(root, "Devices", G_VARIANT_TYPE("ao"));
    wifi_dev[0] = '\0';
    if (devices) {
        gsize n = g_variant_n_children(devices);
        for (gsize i = 0; i < n; i++) {
            GVariant *pv = g_variant_get_child_value(devices, i);
            const gchar *path = g_variant_get_string(pv, NULL);
            GVariant *dev = get_all(NM_NAME, path, NM_DEVICE);
            if (dev) {
                guint32 type = dict_u32(dev, "DeviceType", 0);
                if (type == 2) {
                    copy_trunc(wifi_dev, sizeof(wifi_dev), path);
                    wifi_state = (guint8)dict_u32(dev, "State", 0);
                    g_variant_unref(dev);
                    g_variant_unref(pv);
                    break;
                }
                g_variant_unref(dev);
            }
            g_variant_unref(pv);
        }
        g_variant_unref(devices);
    }
    g_variant_unref(root);
    wifi_present = wifi_dev[0] != '\0';
    if (!wifi_present) {
        copy_trunc(wifi_error, sizeof(wifi_error), "No Wi-Fi adapter");
        return;
    }

    load_saved_connections();
    GVariant *wireless = get_all(NM_NAME, wifi_dev, NM_WIRELESS);
    if (!wireless) {
        copy_trunc(wifi_error, sizeof(wifi_error), "Cannot read Wi-Fi device");
        return;
    }
    char active_ap[MAX_PATH] = "";
    dict_object_path(wireless, "ActiveAccessPoint", active_ap, sizeof(active_ap));
    GVariant *aps_v = g_variant_lookup_value(wireless, "AccessPoints", G_VARIANT_TYPE("ao"));
    ap_count = 0;
    wifi_ssid_len = 0;
    wifi_signal = 0;
    if (aps_v) {
        gsize n = g_variant_n_children(aps_v);
        for (gsize i = 0; i < n && ap_count < MAX_APS; i++) {
            GVariant *pv = g_variant_get_child_value(aps_v, i);
            const gchar *path = g_variant_get_string(pv, NULL);
            GVariant *ap = get_all(NM_NAME, path, NM_AP);
            if (ap) {
                WifiAp *out = &aps[ap_count];
                memset(out, 0, sizeof(*out));
                if (dict_ssid(ap, out->ssid, sizeof(out->ssid), &out->ssid_len) && out->ssid_len > 0) {
                    out->signal = dict_u8(ap, "Strength", 0);
                    guint32 flags = dict_u32(ap, "Flags", 0);
                    guint32 wpa = dict_u32(ap, "WpaFlags", 0);
                    guint32 rsn = dict_u32(ap, "RsnFlags", 0);
                    if ((flags & 0x1) != 0 || wpa != 0 || rsn != 0) out->flags |= AP_SECURED;
                    if (((wpa | rsn) & 0x200) != 0) out->flags |= AP_ENTERPRISE;
                    if ((rsn & 0x400) != 0 && (wpa & 0x100) == 0) out->flags |= AP_SAE;
                    if (active_ap[0] && strcmp(active_ap, path) == 0) out->flags |= AP_ACTIVE;
                    copy_trunc(out->path, sizeof(out->path), path);
                    if (saved_for_ssid(out->ssid, out->ssid_len, out->conn_path, sizeof(out->conn_path))) {
                        out->flags |= AP_SAVED;
                    }
                    ap_count++;
                }
                g_variant_unref(ap);
            }
            g_variant_unref(pv);
        }
        g_variant_unref(aps_v);
    }
    // Active SSID/signal.
    for (guint i = 0; i < ap_count; i++) {
        if (aps[i].flags & AP_ACTIVE) {
            memcpy(wifi_ssid, aps[i].ssid, sizeof(wifi_ssid));
            wifi_ssid_len = aps[i].ssid_len;
            wifi_signal = aps[i].signal;
            break;
        }
    }
    // Merge multiple BSSIDs that advertise the same SSID. Keep the active or
    // strongest entry and carry over saved/active/security flags.
    for (guint i = 0; i < ap_count; i++) {
        for (guint j = i + 1; j < ap_count;) {
            if (aps[i].ssid_len == aps[j].ssid_len &&
                    memcmp(aps[i].ssid, aps[j].ssid, aps[i].ssid_len) == 0) {
                aps[i].flags |= aps[j].flags;
                if ((aps[j].flags & AP_ACTIVE) || (!(aps[i].flags & AP_ACTIVE) && aps[j].signal > aps[i].signal)) {
                    char keep_path[MAX_PATH];
                    char keep_conn[MAX_PATH];
                    copy_trunc(keep_path, sizeof(keep_path), aps[i].path);
                    copy_trunc(keep_conn, sizeof(keep_conn), aps[i].conn_path);
                    aps[i].signal = aps[j].signal;
                    aps[i].flags = aps[j].flags | (aps[i].flags & (AP_SAVED | AP_ACTIVE));
                    copy_trunc(aps[i].path, sizeof(aps[i].path), aps[j].path);
                    if (aps[j].conn_path[0]) copy_trunc(aps[i].conn_path, sizeof(aps[i].conn_path), aps[j].conn_path);
                    else copy_trunc(aps[i].conn_path, sizeof(aps[i].conn_path), keep_conn);
                    (void)keep_path;
                }
                memmove(&aps[j], &aps[j + 1], (ap_count - j - 1) * sizeof(WifiAp));
                ap_count--;
            } else {
                j++;
            }
        }
    }
    // Active first, then saved, then stronger signal.
    for (guint i = 0; i < ap_count; i++) {
        for (guint j = i + 1; j < ap_count; j++) {
            guint32 fi = aps[i].flags, fj = aps[j].flags;
            gboolean swap = FALSE;
            if ((fj & AP_ACTIVE) && !(fi & AP_ACTIVE)) swap = TRUE;
            else if (((fi & AP_ACTIVE) == (fj & AP_ACTIVE)) && (fj & AP_SAVED) && !(fi & AP_SAVED)) swap = TRUE;
            else if (((fi & (AP_ACTIVE | AP_SAVED)) == (fj & (AP_ACTIVE | AP_SAVED))) && aps[j].signal > aps[i].signal) swap = TRUE;
            if (swap) {
                WifiAp tmp = aps[i];
                aps[i] = aps[j];
                aps[j] = tmp;
            }
        }
    }
    wifi_scanning = FALSE;
    g_variant_unref(wireless);
}

static GVariant *make_settings(const char *ssid, guint8 ssid_len, const char *psk,
        gboolean hidden, gboolean sae) {
    GVariantBuilder all, conn, wireless, sec;
    g_variant_builder_init(&all, G_VARIANT_TYPE("a{sa{sv}}"));
    g_variant_builder_init(&conn, G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(&conn, "{sv}", "id", g_variant_new_string(ssid));
    g_variant_builder_add(&conn, "{sv}", "type", g_variant_new_string("802-11-wireless"));
    g_variant_builder_add(&conn, "{sv}", "autoconnect", g_variant_new_boolean(TRUE));
    g_variant_builder_init(&wireless, G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(&wireless, "{sv}", "ssid",
        g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE, ssid, ssid_len, 1));
    g_variant_builder_add(&wireless, "{sv}", "mode", g_variant_new_string("infrastructure"));
    if (hidden) g_variant_builder_add(&wireless, "{sv}", "hidden", g_variant_new_boolean(TRUE));
    if (psk && psk[0] != '\0') {
        g_variant_builder_add(&wireless, "{sv}", "security", g_variant_new_string("802-11-wireless-security"));
    }

    g_variant_builder_add(&all, "{s@a{sv}}", "connection", g_variant_builder_end(&conn));
    if (psk && psk[0] != '\0') {
        g_variant_builder_init(&sec, G_VARIANT_TYPE("a{sv}"));
        g_variant_builder_add(&sec, "{sv}", "key-mgmt", g_variant_new_string(sae ? "sae" : "wpa-psk"));
        g_variant_builder_add(&sec, "{sv}", "psk", g_variant_new_string(psk));
        g_variant_builder_add(&all, "{s@a{sv}}", "802-11-wireless-security", g_variant_builder_end(&sec));
    }
    g_variant_builder_add(&all, "{s@a{sv}}", "802-11-wireless", g_variant_builder_end(&wireless));
    return g_variant_builder_end(&all);
}

static gboolean wifi_toggle_cb(gpointer data) {
    (void)data;
    if (!bus) return G_SOURCE_REMOVE;
    gboolean next = !wifi_enabled;
    GError *err = NULL;
    GVariant *reply = g_dbus_connection_call_sync(
        bus, NM_NAME, NM_PATH, "org.freedesktop.DBus.Properties", "Set",
        g_variant_new("(ssv)", NM_IFACE, "WirelessEnabled", g_variant_new_boolean(next)),
        NULL, G_DBUS_CALL_FLAGS_NONE, 2000, NULL, &err);
    if (reply) g_variant_unref(reply);
    if (err) {
        copy_trunc(wifi_error, sizeof(wifi_error), err->message);
        g_error_free(err);
    }
    poll_wifi();
    if ((features & FEATURE_BT) == 0) send_state();
    return G_SOURCE_REMOVE;
}

static gboolean wifi_scan_cb(gpointer data) {
    (void)data;
    if (!bus || wifi_dev[0] == '\0') return G_SOURCE_REMOVE;
    GVariantBuilder b;
    g_variant_builder_init(&b, G_VARIANT_TYPE("a{sv}"));
    GVariant *opts = g_variant_builder_end(&b);
    GError *err = NULL;
    GVariant *reply = g_dbus_connection_call_sync(
        bus, NM_NAME, wifi_dev, NM_WIRELESS, "RequestScan",
        g_variant_new("(@a{sv})", opts), NULL, G_DBUS_CALL_FLAGS_NONE, 3000, NULL, &err);
    if (reply) g_variant_unref(reply);
    if (err) {
        copy_trunc(wifi_error, sizeof(wifi_error), err->message);
        g_error_free(err);
    }
    wifi_scanning = TRUE;
    poll_wifi();
    send_state();
    return G_SOURCE_REMOVE;
}

typedef struct {
    char ap_path[MAX_PATH];
    char ssid[MAX_SSID];
    char psk[128];
    int hidden;
} ConnectRequest;

static void connect_request_free(ConnectRequest *req) {
    if (!req) return;
    memset(req->psk, 0, sizeof(req->psk));
    g_free(req);
}

static gboolean wifi_connect_cb(gpointer data) {
    ConnectRequest *req = data;
    if (!bus || !req) {
        connect_request_free(req);
        return G_SOURCE_REMOVE;
    }
    WifiAp *ap = NULL;
    for (guint i = 0; i < ap_count; i++) {
        if (req->ap_path[0] && strcmp(aps[i].path, req->ap_path) == 0) {
            ap = &aps[i];
            break;
        }
    }
    GError *err = NULL;
    GVariant *reply = NULL;
    if (ap && ap->conn_path[0] && req->psk[0] == '\0' && !req->hidden) {
        reply = g_dbus_connection_call_sync(
            bus, NM_NAME, NM_PATH, NM_IFACE, "ActivateConnection",
            g_variant_new("(ooo)", ap->conn_path, wifi_dev, req->ap_path),
            G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, 5000, NULL, &err);
    } else {
        gboolean sae = ap && (ap->flags & AP_SAE) != 0;
        GVariant *settings = make_settings(req->ssid, (guint8)strlen(req->ssid),
            req->psk, req->hidden != 0, sae);
        const char *specific = req->ap_path[0] ? req->ap_path : "/";

        GVariant *children[3] = {
            g_variant_ref_sink(settings),
            g_variant_new_object_path(wifi_dev),
            g_variant_new_object_path(specific),
        };
        GVariant *args = g_variant_new_tuple(children, 3);
        reply = g_dbus_connection_call_sync(
            bus, NM_NAME, NM_PATH, NM_IFACE, "AddAndActivateConnection",
            args, G_VARIANT_TYPE("(oo)"), G_DBUS_CALL_FLAGS_NONE, 8000, NULL, &err);
    }
    if (reply) g_variant_unref(reply);
    if (err) {
        copy_trunc(wifi_error, sizeof(wifi_error), err->message);
        g_error_free(err);
    } else {
        wifi_error[0] = '\0';
        wifi_scanning = FALSE;
    }
    memset(req->psk, 0, sizeof(req->psk));
    connect_request_free(req);
    poll_wifi();
    send_state();
    return G_SOURCE_REMOVE;
}

static gboolean wifi_disconnect_cb(gpointer data) {
    (void)data;
    if (!bus || wifi_dev[0] == '\0') return G_SOURCE_REMOVE;
    GVariant *dev = get_all(NM_NAME, wifi_dev, NM_DEVICE);
    char active[MAX_PATH] = "";
    if (dev) {
        dict_object_path(dev, "ActiveConnection", active, sizeof(active));
        g_variant_unref(dev);
    }
    if (active[0]) {
        GError *err = NULL;
        GVariant *reply = g_dbus_connection_call_sync(
            bus, NM_NAME, NM_PATH, NM_IFACE, "DeactivateConnection",
            g_variant_new("(o)", active), NULL, G_DBUS_CALL_FLAGS_NONE, 3000, NULL, &err);
        if (reply) g_variant_unref(reply);
        if (err) {
            copy_trunc(wifi_error, sizeof(wifi_error), err->message);
            g_error_free(err);
        }
    }
    poll_wifi();
    send_state();
    return G_SOURCE_REMOVE;
}

static gboolean wifi_forget_cb(gpointer data) {
    char *path = data;
    if (!path) return G_SOURCE_REMOVE;
    if (bus) {
        GError *err = NULL;
        GVariant *reply = g_dbus_connection_call_sync(
            bus, NM_NAME, path, NM_CONNECTION, "Delete",
            NULL, NULL, G_DBUS_CALL_FLAGS_NONE, 3000, NULL, &err);
        if (reply) g_variant_unref(reply);
        if (err) {
            copy_trunc(wifi_error, sizeof(wifi_error), err->message);
            g_error_free(err);
        }
    }
    g_free(path);
    poll_wifi();
    send_state();
    return G_SOURCE_REMOVE;
}

static void send_agent_prompt(int kind, const char *name, const char *passkey) {
    GByteArray *b = g_byte_array_new();
    tlv_u8(b, 1, (guint8)kind);
    tlv_str(b, 2, passkey ? passkey : "");
    tlv_str(b, 3, name ? name : "");
    send_frame(FRAME_AGENT, b->data, b->len);
    g_byte_array_unref(b);
}

static void agent_done(void) {
    agent_call = NULL;
    agent_kind = AGENT_NONE;
}

static void agent_method_call(GDBusConnection *connection, const gchar *sender,
        const gchar *object_path, const gchar *interface_name,
        const gchar *method_name, GVariant *parameters,
        GDBusMethodInvocation *invocation, gpointer user_data) {
    (void)connection;
    (void)sender;
    (void)object_path;
    (void)interface_name;
    (void)user_data;

    if (strcmp(method_name, "Release") == 0) {
        if (agent_call) {
            g_dbus_method_invocation_return_dbus_error(agent_call, "org.bluez.Error.Canceled", "Agent released");
            agent_done();
        }
        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }
    if (strcmp(method_name, "Cancel") == 0) {
        if (agent_call) {
            g_dbus_method_invocation_return_dbus_error(agent_call, "org.bluez.Error.Canceled", "Canceled");
            agent_done();
        }
        send_frame(FRAME_AGENT_CANCEL, NULL, 0);
        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }
    if (agent_call) {
        g_dbus_method_invocation_return_dbus_error(invocation, "org.bluez.Error.InProgress", "Another pairing request is active");
        return;
    }

    const gchar *device = "";
    guint32 passkey = 0;
    if (strcmp(method_name, "RequestConfirmation") == 0) {
        g_variant_get(parameters, "(&ou)", &device, &passkey);
        char code[16];
        snprintf(code, sizeof(code), "%06u", passkey);
        agent_kind = AGENT_CONFIRM;
        agent_call = invocation;
        send_agent_prompt(AGENT_CONFIRM, device, code);
        return;
    }
    if (strcmp(method_name, "RequestPasskey") == 0) {
        g_variant_get(parameters, "(&o)", &device);
        agent_kind = AGENT_PASSKEY;
        agent_call = invocation;
        send_agent_prompt(AGENT_PASSKEY, device, "");
        return;
    }
    if (strcmp(method_name, "RequestPinCode") == 0) {
        g_variant_get(parameters, "(&o)", &device);
        agent_kind = AGENT_PIN;
        agent_call = invocation;
        send_agent_prompt(AGENT_PIN, device, "");
        return;
    }
    if (strcmp(method_name, "DisplayPasskey") == 0) {
        guint16 entered = 0;
        g_variant_get(parameters, "(&ouq)", &device, &passkey, &entered);
        char code[16];
        snprintf(code, sizeof(code), "%06u", passkey);
        send_agent_prompt(AGENT_DISPLAY, device, code);
        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }
    if (strcmp(method_name, "DisplayPinCode") == 0) {
        const gchar *pin = "";
        g_variant_get(parameters, "(&o&s)", &device, &pin);
        send_agent_prompt(AGENT_DISPLAY, device, pin);
        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }
    if (strcmp(method_name, "RequestAuthorization") == 0 ||
        strcmp(method_name, "AuthorizeService") == 0) {
        g_variant_get(parameters, "(&o)", &device);
        agent_kind = AGENT_AUTHORIZE;
        agent_call = invocation;
        send_agent_prompt(AGENT_AUTHORIZE, device, "");
        return;
    }
    g_dbus_method_invocation_return_dbus_error(invocation, "org.bluez.Error.NotSupported", "Unsupported agent method");
}

static const GDBusInterfaceVTable agent_vtable = {
    agent_method_call, NULL, NULL, { 0 }
};

static const gchar agent_xml[] =
    "<node>"
    "  <interface name='org.bluez.Agent1'>"
    "    <method name='Release'/>"
    "    <method name='RequestPinCode'><arg type='o' direction='in'/><arg type='s' direction='out'/></method>"
    "    <method name='DisplayPinCode'><arg type='o' direction='in'/><arg type='s' direction='in'/></method>"
    "    <method name='RequestPasskey'><arg type='o' direction='in'/><arg type='u' direction='out'/></method>"
    "    <method name='DisplayPasskey'><arg type='o' direction='in'/><arg type='u' direction='in'/><arg type='q' direction='in'/></method>"
    "    <method name='RequestConfirmation'><arg type='o' direction='in'/><arg type='u' direction='in'/></method>"
    "    <method name='RequestAuthorization'><arg type='o' direction='in'/></method>"
    "    <method name='AuthorizeService'><arg type='o' direction='in'/><arg type='s' direction='in'/></method>"
    "    <method name='Cancel'/>"
    "  </interface>"
    "</node>";

static void register_agent(void) {
    if (!bus) return;
    if (object_registration != 0) return;
    GError *err = NULL;
    GDBusNodeInfo *info = g_dbus_node_info_new_for_xml(agent_xml, &err);
    if (!info) {
        if (err) g_error_free(err);
        return;
    }
    object_registration = g_dbus_connection_register_object(
        bus, "/org/tessa/Agent", info->interfaces[0], &agent_vtable,
        NULL, NULL, &err);
    g_dbus_node_info_unref(info);
    if (object_registration == 0) {
        if (err) g_error_free(err);
        return;
    }
    GVariant *reply = g_dbus_connection_call_sync(
        bus, BLUEZ_NAME, "/org/bluez", AGENT_MANAGER, "RegisterAgent",
        g_variant_new("(os)", "/org/tessa/Agent", "KeyboardDisplay"),
        NULL, G_DBUS_CALL_FLAGS_NONE, 3000, NULL, &err);
    if (reply) g_variant_unref(reply);
    if (err) {
        copy_trunc(bt_error, sizeof(bt_error), err->message);
        g_error_free(err);
        return;
    }
    reply = g_dbus_connection_call_sync(
        bus, BLUEZ_NAME, "/org/bluez", AGENT_MANAGER, "RequestDefaultAgent",
        g_variant_new("(o)", "/org/tessa/Agent"),
        NULL, G_DBUS_CALL_FLAGS_NONE, 3000, NULL, &err);
    if (reply) g_variant_unref(reply);
    if (err) g_error_free(err);
}

static void poll_bt(void) {
    if (!(features & FEATURE_BT)) return;
    if (!bus) {
        copy_trunc(bt_error, sizeof(bt_error), "System bus unavailable");
        return;
    }
    GError *err = NULL;
    GVariant *reply = g_dbus_connection_call_sync(
        bus, BLUEZ_NAME, BLUEZ_ROOT, "org.freedesktop.DBus.ObjectManager",
        "GetManagedObjects", NULL, G_VARIANT_TYPE("(a{oa{sa{sv}}})"),
        G_DBUS_CALL_FLAGS_NONE, 2500, NULL, &err);
    if (!reply) {
        bt_present = FALSE;
        bt_powered = FALSE;
        bt_count = 0;
        copy_trunc(bt_error, sizeof(bt_error), "BlueZ is not running");
        if (err) g_error_free(err);
        return;
    }
    bt_error[0] = '\0';
    bt_present = FALSE;
    bt_powered = FALSE;
    bt_discovering = FALSE;
    bt_adapter[0] = '\0';
    bt_name[0] = '\0';
    bt_count = 0;

    GVariant *objects = g_variant_get_child_value(reply, 0);
    GVariantIter iter;
    const gchar *path;
    GVariant *interfaces;
    g_variant_iter_init(&iter, objects);
    while (g_variant_iter_next(&iter, "{&o@a{sa{sv}}}", &path, &interfaces)) {
        GVariant *adapter = g_variant_lookup_value(interfaces, ADAPTER_IFACE, G_VARIANT_TYPE("a{sv}"));
        if (adapter) {
            bt_present = TRUE;
            copy_trunc(bt_adapter, sizeof(bt_adapter), path);
            bt_powered = dict_bool(adapter, "Powered", FALSE);
            bt_discovering = dict_bool(adapter, "Discovering", FALSE);
            char alias[MAX_NAME];
            dict_string(adapter, "Alias", alias, sizeof(alias));
            if (alias[0] == '\0') dict_string(adapter, "Name", alias, sizeof(alias));
            copy_trunc(bt_name, sizeof(bt_name), alias);
            if (!bt_name[0]) copy_trunc(bt_name, sizeof(bt_name), "Bluetooth");
            g_variant_unref(adapter);
        }
        GVariant *device = g_variant_lookup_value(interfaces, DEVICE_IFACE, G_VARIANT_TYPE("a{sv}"));
        if (device && bt_count < MAX_DEVICES) {
            BtDevice *out = &bt_devices[bt_count];
            memset(out, 0, sizeof(*out));
            copy_trunc(out->path, sizeof(out->path), path);
            char name[MAX_NAME];
            dict_string(device, "Alias", name, sizeof(name));
            if (name[0] == '\0') dict_string(device, "Name", name, sizeof(name));
            copy_trunc(out->name, sizeof(out->name), name);
            char icon[64];
            dict_string(device, "Icon", icon, sizeof(icon));
            if (strstr(icon, "headset") || strstr(icon, "headphone")) out->icon = 1;
            else if (strstr(icon, "phone")) out->icon = 2;
            else if (strstr(icon, "keyboard")) out->icon = 3;
            else if (strstr(icon, "mouse")) out->icon = 4;
            if (dict_bool(device, "Paired", FALSE)) out->flags |= 1;
            if (dict_bool(device, "Connected", FALSE)) out->flags |= 2;
            if (dict_bool(device, "Trusted", FALSE)) out->flags |= 4;
            gint16 rssi = 0;
            if (g_variant_lookup(device, "RSSI", "n", &rssi)) out->rssi = rssi;
            out->battery = -1;
            GVariant *battery = g_variant_lookup_value(interfaces, BATTERY_IFACE, G_VARIANT_TYPE("a{sv}"));
            if (battery) {
                guint8 pct = 0;
                if (g_variant_lookup(battery, "Percentage", "y", &pct)) out->battery = (gint8)pct;
                g_variant_unref(battery);
            }
            bt_count++;
            g_variant_unref(device);
        }
        g_variant_unref(interfaces);
    }
    g_variant_unref(objects);
    g_variant_unref(reply);

    // Connected first, then paired, then strongest signal.
    for (guint i = 0; i < bt_count; i++) {
        for (guint j = i + 1; j < bt_count; j++) {
            gboolean swap = FALSE;
            guint8 ci = bt_devices[i].flags, cj = bt_devices[j].flags;
            if ((cj & 2) && !(ci & 2)) swap = TRUE;
            else if (((ci & 2) == (cj & 2)) && (cj & 1) && !(ci & 1)) swap = TRUE;
            else if (((ci & 3) == (cj & 3)) && bt_devices[j].rssi > bt_devices[i].rssi) swap = TRUE;
            if (swap) {
                BtDevice tmp = bt_devices[i];
                bt_devices[i] = bt_devices[j];
                bt_devices[j] = tmp;
            }
        }
    }
}

static gboolean bt_toggle_cb(gpointer data) {
    (void)data;
    if (!bus || bt_adapter[0] == '\0') return G_SOURCE_REMOVE;
    GError *err = NULL;
    GVariant *reply = g_dbus_connection_call_sync(
        bus, BLUEZ_NAME, bt_adapter, "org.freedesktop.DBus.Properties", "Set",
        g_variant_new("(ssv)", ADAPTER_IFACE, "Powered", g_variant_new_boolean(!bt_powered)),
        NULL, G_DBUS_CALL_FLAGS_NONE, 3000, NULL, &err);
    if (reply) g_variant_unref(reply);
    if (err) {
        copy_trunc(bt_error, sizeof(bt_error), err->message);
        g_error_free(err);
    }
    poll_bt();
    send_state();
    return G_SOURCE_REMOVE;
}

static gboolean bt_discovery_cb(gpointer data) {
    gboolean on = GPOINTER_TO_INT(data) != 0;
    if (!bus || bt_adapter[0] == '\0') return G_SOURCE_REMOVE;
    GError *err = NULL;
    GVariant *reply = g_dbus_connection_call_sync(
        bus, BLUEZ_NAME, bt_adapter, ADAPTER_IFACE, on ? "StartDiscovery" : "StopDiscovery",
        NULL, NULL, G_DBUS_CALL_FLAGS_NONE, 3000, NULL, &err);
    if (reply) g_variant_unref(reply);
    if (err) {
        copy_trunc(bt_error, sizeof(bt_error), err->message);
        g_error_free(err);
    }
    poll_bt();
    send_state();
    return G_SOURCE_REMOVE;
}

static void bt_connect_done(GObject *source, GAsyncResult *res, gpointer data) {
    (void)data;
    GError *err = NULL;
    GVariant *reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), res, &err);
    if (reply) g_variant_unref(reply);
    if (err) {
        copy_trunc(bt_error, sizeof(bt_error), err->message);
        g_error_free(err);
    }
    poll_bt();
    send_state();
}

static gboolean bt_connect_cb(gpointer data) {
    BtDevice *d = data;
    if (!bus || !d) {
        g_free(d);
        return G_SOURCE_REMOVE;
    }
    g_dbus_connection_call(
        bus, BLUEZ_NAME, d->path, DEVICE_IFACE,
        (d->flags & 2) ? "Disconnect" : "Connect",
        NULL, NULL, G_DBUS_CALL_FLAGS_NONE, 15000, NULL,
        bt_connect_done, NULL);
    g_free(d);
    return G_SOURCE_REMOVE;
}

static void bt_pair_done(GObject *source, GAsyncResult *res, gpointer data) {
    char *path = data;
    GError *err = NULL;
    GVariant *reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), res, &err);
    if (reply) g_variant_unref(reply);
    if (err) {
        copy_trunc(bt_error, sizeof(bt_error), err->message);
        g_error_free(err);
    } else if (path) {
        g_dbus_connection_call(
            bus, BLUEZ_NAME, path, DEVICE_IFACE, "Connect",
            NULL, NULL, G_DBUS_CALL_FLAGS_NONE, 15000, NULL,
            bt_connect_done, NULL);
    }
    g_free(path);
    poll_bt();
    send_state();
}

static gboolean bt_pair_cb(gpointer data) {
    char *path = data;
    if (!bus || !path) {
        g_free(path);
        return G_SOURCE_REMOVE;
    }
    g_dbus_connection_call(
        bus, BLUEZ_NAME, path, DEVICE_IFACE, "Pair",
        NULL, NULL, G_DBUS_CALL_FLAGS_NONE, 60000, NULL,
        bt_pair_done, g_strdup(path));
    g_free(path);
    return G_SOURCE_REMOVE;
}

static gboolean bt_forget_cb(gpointer data) {
    char *path = data;
    if (!bus || !path) {
        g_free(path);
        return G_SOURCE_REMOVE;
    }
    if (bt_adapter[0]) {
        GError *err = NULL;
        GVariant *reply = g_dbus_connection_call_sync(
            bus, BLUEZ_NAME, bt_adapter, ADAPTER_IFACE, "RemoveDevice",
            g_variant_new("(o)", path), NULL, G_DBUS_CALL_FLAGS_NONE, 5000, NULL, &err);
        if (reply) g_variant_unref(reply);
        if (err) {
            copy_trunc(bt_error, sizeof(bt_error), err->message);
            g_error_free(err);
        }
    }
    g_free(path);
    poll_bt();
    send_state();
    return G_SOURCE_REMOVE;
}

static void agent_reply_cb(gpointer data) {
    (void)data;
    // The actual reply is carried by globals set in tessa_system_bt_agent_reply.
}

static int pending_agent_code;
static char pending_agent_text[128];

static gboolean agent_reply_impl(gpointer data) {
    (void)data;
    if (!agent_call) {
        agent_kind = AGENT_NONE;
        return G_SOURCE_REMOVE;
    }
    GDBusMethodInvocation *call = agent_call;
    int kind = agent_kind;
    agent_done();
    if (pending_agent_code != 0) {
        g_dbus_method_invocation_return_dbus_error(call, "org.bluez.Error.Rejected", "Rejected");
        return G_SOURCE_REMOVE;
    }
    if (kind == AGENT_PIN) {
        g_dbus_method_invocation_return_value(call, g_variant_new("(s)", pending_agent_text));
    } else if (kind == AGENT_PASSKEY) {
        guint32 value = (guint32)strtoul(pending_agent_text, NULL, 10);
        g_dbus_method_invocation_return_value(call, g_variant_new("(u)", value));
    } else {
        g_dbus_method_invocation_return_value(call, NULL);
    }
    memset(pending_agent_text, 0, sizeof(pending_agent_text));
    return G_SOURCE_REMOVE;
}

static void read_backlight(void) {
    bl_present = FALSE;
    bl_percent = -1;
    bl_max = 0;
    bl_name[0] = '\0';
    GDir *dir = g_dir_open("/sys/class/backlight", 0, NULL);
    if (!dir) return;
    const gchar *name;
    while ((name = g_dir_read_name(dir)) != NULL) {
        char path[256];
        snprintf(path, sizeof(path), "/sys/class/backlight/%s/max_brightness", name);
        FILE *f = fopen(path, "r");
        if (!f) continue;
        unsigned long max = 0;
        if (fscanf(f, "%lu", &max) != 1 || max == 0) {
            fclose(f);
            continue;
        }
        fclose(f);
        snprintf(path, sizeof(path), "/sys/class/backlight/%s/brightness", name);
        f = fopen(path, "r");
        if (!f) continue;
        unsigned long cur = 0;
        if (fscanf(f, "%lu", &cur) == 1) {
            bl_present = TRUE;
            bl_max = (guint32)max;
            bl_percent = (int)lround((double)cur * 100.0 / (double)max);
            if (bl_percent < 0) bl_percent = 0;
            if (bl_percent > 100) bl_percent = 100;
            copy_trunc(bl_name, sizeof(bl_name), name);
            fclose(f);
            break;
        }
        fclose(f);
    }
    g_dir_close(dir);
}

static char login_session[MAX_PATH];

static void ensure_login_session(void) {
    if (login_session[0] || !bus) return;
    GError *err = NULL;
    GVariant *reply = g_dbus_connection_call_sync(
        bus, LOGIN_NAME, LOGIN_PATH, LOGIN_MANAGER, "GetSessionByPID",
        g_variant_new("(u)", (guint32)getpid()), G_VARIANT_TYPE("(o)"),
        G_DBUS_CALL_FLAGS_NONE, 2000, NULL, &err);
    if (reply) {
        GVariant *path = g_variant_get_child_value(reply, 0);
        copy_trunc(login_session, sizeof(login_session), g_variant_get_string(path, NULL));
        g_variant_unref(path);
        g_variant_unref(reply);
    }
    if (err) {
        g_error_free(err);
        copy_trunc(login_session, sizeof(login_session), "/org/freedesktop/login1/session/auto");
    }
}

static gboolean set_brightness_cb(gpointer data) {
    int percent = GPOINTER_TO_INT(data);
    read_backlight();
    if (!bl_present || bl_max == 0) return G_SOURCE_REMOVE;
    if (percent < 0) percent = 0;
    if (percent > 100) percent = 100;
    guint32 value = (guint32)lround((double)bl_max * (double)percent / 100.0);
    if (value < 1) value = 1;
    ensure_login_session();
    if (!bus) return G_SOURCE_REMOVE;
    GError *err = NULL;
    GVariant *reply = g_dbus_connection_call_sync(
        bus, LOGIN_NAME, login_session, LOGIN_SESSION, "SetBrightness",
        g_variant_new("(ssu)", "backlight", bl_name, value),
        NULL, G_DBUS_CALL_FLAGS_NONE, 2500, NULL, &err);
    if (reply) g_variant_unref(reply);
    if (err) g_error_free(err);
    read_backlight();
    send_state();
    return G_SOURCE_REMOVE;
}

static void poll_ppd(void) {
    if (!(features & FEATURE_PPD)) return;
    if (!bus) return;
    GVariant *dict = get_all(PPD_NAME, PPD_PATH, PPD_IFACE);
    if (!dict) {
        ppd_available = FALSE;
        ppd_profile[0] = '\0';
        ppd_profile_count = 0;
        return;
    }
    ppd_available = TRUE;
    dict_string(dict, "ActiveProfile", ppd_profile, sizeof(ppd_profile));
    ppd_profile_count = 0;
    GVariant *profiles = g_variant_lookup_value(dict, "Profiles", G_VARIANT_TYPE("aa{sv}"));
    if (profiles) {
        gsize n = g_variant_n_children(profiles);
        for (gsize i = 0; i < n && ppd_profile_count < 4; i++) {
            GVariant *item = g_variant_get_child_value(profiles, i);
            char name[32];
            dict_string(item, "Profile", name, sizeof(name));
            if (name[0]) {
                copy_trunc(ppd_profiles[ppd_profile_count], 32, name);
                ppd_profile_count++;
            }
            g_variant_unref(item);
        }
        g_variant_unref(profiles);
    }
    g_variant_unref(dict);
}

static gboolean set_profile_cb(gpointer data) {
    char *name = data;
    if (!bus || !name) {
        g_free(name);
        return G_SOURCE_REMOVE;
    }
    GError *err = NULL;
    GVariant *reply = g_dbus_connection_call_sync(
        bus, PPD_NAME, PPD_PATH, "org.freedesktop.DBus.Properties", "Set",
        g_variant_new("(ssv)", PPD_IFACE, "ActiveProfile", g_variant_new_string(name)),
        NULL, G_DBUS_CALL_FLAGS_NONE, 4000, NULL, &err);
    if (reply) g_variant_unref(reply);
    if (err) g_error_free(err);
    g_free(name);
    poll_ppd();
    send_state();
    return G_SOURCE_REMOVE;
}

static void send_state(void) {
    GByteArray *b = g_byte_array_new();
    if (features & FEATURE_WIFI) {
        guint32 flags = 0;
        if (wifi_present) flags |= 1;
        if (wifi_enabled) flags |= 2;
        if (wifi_hw_enabled) flags |= 4;
        if (wifi_scanning) flags |= 8;
        tlv_u32(b, 0x10, flags);
        tlv_str(b, 0x11, wifi_ssid);
        tlv_u8(b, 0x12, wifi_signal);
        tlv_u8(b, 0x13, wifi_state);
        tlv_str(b, 0x14, wifi_error);
        tlv_u16(b, 0x15, (guint16)ap_count);
        for (guint i = 0; i < ap_count; i++) {
            GByteArray *ap = g_byte_array_new();
            guint8 slen = aps[i].ssid_len;
            g_byte_array_append(ap, &slen, 1);
            g_byte_array_append(ap, (const guint8 *)aps[i].ssid, slen);
            g_byte_array_append(ap, &aps[i].signal, 1);
            guint8 fl[4] = {
                (guint8)(aps[i].flags & 0xff),
                (guint8)((aps[i].flags >> 8) & 0xff),
                (guint8)((aps[i].flags >> 16) & 0xff),
                (guint8)((aps[i].flags >> 24) & 0xff),
            };
            g_byte_array_append(ap, fl, 4);
            guint16 plen = (guint16)strlen(aps[i].path);
            guint8 pl[2] = { (guint8)(plen & 0xff), (guint8)(plen >> 8) };
            g_byte_array_append(ap, pl, 2);
            g_byte_array_append(ap, (const guint8 *)aps[i].path, plen);
            guint16 clen = (guint16)strlen(aps[i].conn_path);
            guint8 cl[2] = { (guint8)(clen & 0xff), (guint8)(clen >> 8) };
            g_byte_array_append(ap, cl, 2);
            g_byte_array_append(ap, (const guint8 *)aps[i].conn_path, clen);
            tlv_add(b, 0x16, ap->data, (guint16)ap->len);
            g_byte_array_unref(ap);
        }
    }
    if (features & FEATURE_BT) {
        guint32 flags = 0;
        if (bt_present) flags |= 1;
        if (bt_powered) flags |= 2;
        if (bt_discovering) flags |= 4;
        tlv_u32(b, 0x20, flags);
        tlv_str(b, 0x21, bt_name);
        tlv_str(b, 0x22, bt_error);
        tlv_u16(b, 0x23, (guint16)bt_count);
        for (guint i = 0; i < bt_count; i++) {
            GByteArray *d = g_byte_array_new();
            guint16 plen = (guint16)strlen(bt_devices[i].path);
            guint8 pl[2] = { (guint8)(plen & 0xff), (guint8)(plen >> 8) };
            g_byte_array_append(d, pl, 2);
            g_byte_array_append(d, (const guint8 *)bt_devices[i].path, plen);
            guint16 nlen = (guint16)strlen(bt_devices[i].name);
            guint8 nl[2] = { (guint8)(nlen & 0xff), (guint8)(nlen >> 8) };
            g_byte_array_append(d, nl, 2);
            g_byte_array_append(d, (const guint8 *)bt_devices[i].name, nlen);
            g_byte_array_append(d, &bt_devices[i].icon, 1);
            g_byte_array_append(d, &bt_devices[i].flags, 1);
            guint8 rssi[2] = {
                (guint8)(bt_devices[i].rssi & 0xff),
                (guint8)((bt_devices[i].rssi >> 8) & 0xff),
            };
            g_byte_array_append(d, rssi, 2);
            g_byte_array_append(d, (const guint8 *)&bt_devices[i].battery, 1);
            tlv_add(b, 0x24, d->data, (guint16)d->len);
            g_byte_array_unref(d);
        }
    }
    if ((features & FEATURE_BRIGHTNESS) || (features & FEATURE_PPD)) {
        guint32 flags = 0;
        if (bl_present) flags |= 1;
        if (ppd_available) flags |= 2;
        tlv_u32(b, 0x30, flags);
        tlv_u8(b, 0x31, (guint8)(bl_percent < 0 ? 0 : bl_percent));
        tlv_u32(b, 0x32, bl_max);
        tlv_str(b, 0x33, bl_name);
        tlv_str(b, 0x34, ppd_profile);
        tlv_u8(b, 0x35, (guint8)ppd_profile_count);
        for (guint i = 0; i < ppd_profile_count; i++) {
            tlv_str(b, 0x36, ppd_profiles[i]);
        }
    }
    send_frame(FRAME_STATE, b->data, b->len);
    g_byte_array_unref(b);
}

static gboolean poll_all(gpointer data) {
    (void)data;
    if (stopping) return G_SOURCE_REMOVE;
    if (features & FEATURE_WIFI) poll_wifi();
    if (features & FEATURE_BT) poll_bt();
    if (features & FEATURE_BRIGHTNESS) read_backlight();
    if (features & FEATURE_PPD) poll_ppd();
    send_state();
    return G_SOURCE_CONTINUE;
}

static gboolean set_features_cb(gpointer data) {
    (void)data;
    if (stopping) return G_SOURCE_REMOVE;
    if (features & FEATURE_WIFI) poll_wifi();
    if (features & FEATURE_BT) poll_bt();
    if (features & FEATURE_BRIGHTNESS) read_backlight();
    if (features & FEATURE_PPD) poll_ppd();
    send_state();
    return G_SOURCE_REMOVE;
}

static gpointer system_thread(gpointer data) {
    (void)data;
    ctx = g_main_context_new();
    g_main_context_push_thread_default(ctx);
    loop = g_main_loop_new(ctx, FALSE);

    GError *err = NULL;
    bus = g_bus_get_sync(G_BUS_TYPE_SYSTEM, NULL, &err);
    if (!bus) {
        send_error(err ? err->message : "Cannot connect to the system bus");
        if (err) g_error_free(err);
    } else {
        if (g_getenv("TESSA_PANEL_SYSTEM_OWNER") &&
            strcmp(g_getenv("TESSA_PANEL_SYSTEM_OWNER"), "1") == 0) {
            register_agent();
        }
        poll_all(NULL);
    }
    send_ready();

    GSource *source = g_timeout_source_new(2000);
    g_source_set_callback(source, poll_all, NULL, NULL);
    poll_source = g_source_attach(source, ctx);

    g_main_loop_run(loop);

    g_source_destroy(source);
    g_source_unref(source);
    if (object_registration != 0 && bus) {
        g_dbus_connection_unregister_object(bus, object_registration);
        object_registration = 0;
    }
    if (loop) {
        g_main_loop_unref(loop);
        loop = NULL;
    }
    if (bus) {
        g_object_unref(bus);
        bus = NULL;
    }
    g_main_context_pop_thread_default(ctx);
    g_main_context_unref(ctx);
    ctx = NULL;
    return NULL;
}

int tessa_system_start(void) {
    if (sock_read >= 0) return sock_read;
    int fds[2];
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, fds) != 0) return -1;
    sock_read = fds[0];
    sock_write = fds[1];
    stopping = FALSE;
    thread = g_thread_new("tessa-system", system_thread, NULL);
    return sock_read;
}

void tessa_system_stop(void) {
    if (thread == NULL) return;
    stopping = TRUE;
    if (ctx) g_main_context_invoke(ctx, (GSourceFunc)set_features_cb, NULL);
    if (loop) g_main_loop_quit(loop);
    g_thread_join(thread);
    thread = NULL;
    if (sock_read >= 0) close(sock_read);
    if (sock_write >= 0) close(sock_write);
    sock_read = -1;
    sock_write = -1;
}

void tessa_system_set_features(unsigned int mask) {
    features = mask;
    if (ctx) g_main_context_invoke(ctx, (GSourceFunc)set_features_cb, NULL);
}

void tessa_system_wifi_toggle(void) {
    if (ctx) g_main_context_invoke(ctx, (GSourceFunc)wifi_toggle_cb, NULL);
}

void tessa_system_wifi_scan(void) {
    if (ctx) g_main_context_invoke(ctx, (GSourceFunc)wifi_scan_cb, NULL);
}

void tessa_system_wifi_connect(const char *ap_path, const char *ssid,
        const char *psk, int hidden) {
    if (!ctx) return;
    ConnectRequest *req = g_new0(ConnectRequest, 1);
    copy_trunc(req->ap_path, sizeof(req->ap_path), ap_path ? ap_path : "");
    copy_trunc(req->ssid, sizeof(req->ssid), ssid ? ssid : "");
    copy_trunc(req->psk, sizeof(req->psk), psk ? psk : "");
    req->hidden = hidden;
    g_main_context_invoke(ctx, (GSourceFunc)wifi_connect_cb, req);
}

void tessa_system_wifi_disconnect(void) {
    if (ctx) g_main_context_invoke(ctx, (GSourceFunc)wifi_disconnect_cb, NULL);
}

void tessa_system_wifi_forget(const char *conn_path) {
    if (ctx && conn_path) g_main_context_invoke(ctx, (GSourceFunc)wifi_forget_cb, g_strdup(conn_path));
}

void tessa_system_bt_toggle(void) {
    if (ctx) g_main_context_invoke(ctx, (GSourceFunc)bt_toggle_cb, NULL);
}

void tessa_system_bt_discovery(int on) {
    if (ctx) g_main_context_invoke(ctx, (GSourceFunc)bt_discovery_cb, GINT_TO_POINTER(on != 0));
}

void tessa_system_bt_pair(const char *path) {
    if (ctx && path) g_main_context_invoke(ctx, (GSourceFunc)bt_pair_cb, g_strdup(path));
}

void tessa_system_bt_connect(const char *path, int connect) {
    (void)connect;
    if (!ctx || !path) return;
    BtDevice *d = g_new0(BtDevice, 1);
    copy_trunc(d->path, sizeof(d->path), path);
    for (guint i = 0; i < bt_count; i++) {
        if (strcmp(bt_devices[i].path, path) == 0) d->flags = bt_devices[i].flags;
    }
    g_main_context_invoke(ctx, (GSourceFunc)bt_connect_cb, d);
}

void tessa_system_bt_forget(const char *path) {
    if (ctx && path) g_main_context_invoke(ctx, (GSourceFunc)bt_forget_cb, g_strdup(path));
}

void tessa_system_bt_agent_reply(int code, const char *text) {
    if (!ctx) return;
    pending_agent_code = code;
    copy_trunc(pending_agent_text, sizeof(pending_agent_text), text ? text : "");
    g_main_context_invoke(ctx, (GSourceFunc)agent_reply_impl, NULL);
}

void tessa_system_set_brightness(int percent) {
    if (ctx) g_main_context_invoke(ctx, (GSourceFunc)set_brightness_cb, GINT_TO_POINTER(percent));
}

void tessa_system_set_profile(const char *name) {
    if (ctx && name) g_main_context_invoke(ctx, (GSourceFunc)set_profile_cb, g_strdup(name));
}
