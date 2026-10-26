#define _GNU_SOURCE

#include "media.h"

#include <gio/gio.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define MPRIS_PREFIX "org.mpris.MediaPlayer2."
#define MPRIS_PATH "/org/mpris/MediaPlayer2"
#define PLAYER_IFACE "org.mpris.MediaPlayer2.Player"
#define MAX_TITLE 159
#define MAX_ARTIST 159
#define MAX_PLAYER 63
#define MAX_ERROR 200

static GMainLoop *loop;
static GThread *thread;
static GDBusConnection *bus;
static guint timeout_id;
static char player_name[256];
static gboolean has_player;
static int sock_read = -1;
static int sock_write = -1;
static gboolean stopping;
static guint32 last_status;
static char last_title[MAX_TITLE + 1];
static char last_artist[MAX_ARTIST + 1];
static char last_player[MAX_PLAYER + 1];

typedef struct {
    guint32 code;
} MediaCommand;

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

static void clear_player(void) {
    has_player = FALSE;
    player_name[0] = '\0';
}

static void send_state(guint32 status, const char *title, const char *artist,
        const char *player) {
    status = status > 3 ? 3 : status;
    char tbuf[MAX_TITLE + 1] = "";
    char abuf[MAX_ARTIST + 1] = "";
    char pbuf[MAX_PLAYER + 1] = "";
    if (status != 0) {
        copy_trunc(tbuf, sizeof(tbuf), title ? title : "");
        copy_trunc(abuf, sizeof(abuf), artist ? artist : "");
        copy_trunc(pbuf, sizeof(pbuf), player ? player : "");
    }
    if (status == last_status && strcmp(tbuf, last_title) == 0 &&
            strcmp(abuf, last_artist) == 0 && strcmp(pbuf, last_player) == 0) {
        return;
    }
    last_status = status;
    copy_trunc(last_title, sizeof(last_title), tbuf);
    copy_trunc(last_artist, sizeof(last_artist), abuf);
    copy_trunc(last_player, sizeof(last_player), pbuf);

    size_t title_len = strlen(tbuf);
    size_t artist_len = strlen(abuf);
    size_t player_len = strlen(pbuf);
    unsigned char hdr[16];
    memset(hdr, 0, sizeof(hdr));
    hdr[0] = 1;
    hdr[1] = (unsigned char)status;
    put_u32(hdr + 4, (uint32_t)title_len);
    put_u32(hdr + 8, (uint32_t)artist_len);
    put_u32(hdr + 12, (uint32_t)player_len);
    write_all(hdr, sizeof(hdr));
    if (title_len > 0) write_all(tbuf, title_len);
    if (artist_len > 0) write_all(abuf, artist_len);
    if (player_len > 0) write_all(pbuf, player_len);
}

static void poll_media(void) {
    if (!bus) return;
    GError *error = NULL;
    GVariant *reply = g_dbus_connection_call_sync(
        bus,
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
        "ListNames",
        NULL,
        G_VARIANT_TYPE("(as)"),
        G_DBUS_CALL_FLAGS_NONE,
        1000,
        NULL,
        &error);
    if (!reply) {
        if (error) g_error_free(error);
        send_state(0, "", "", "");
        clear_player();
        return;
    }

    const gchar **names = NULL;
    g_variant_get(reply, "(^as)", &names);
    const gchar *chosen = NULL;
    if (names) {
        for (const gchar **it = names; *it; it++) {
            if (g_str_has_prefix(*it, MPRIS_PREFIX)) {
                chosen = *it;
                break;
            }
        }
    }
    if (!chosen) {
        g_free(names);
        g_variant_unref(reply);
        send_state(0, "", "", "");
        clear_player();
        return;
    }
    copy_trunc(player_name, sizeof(player_name), chosen);
    g_free(names);
    g_variant_unref(reply);
    has_player = TRUE;

    reply = g_dbus_connection_call_sync(
        bus,
        player_name,
        MPRIS_PATH,
        "org.freedesktop.DBus.Properties",
        "GetAll",
        g_variant_new("(s)", PLAYER_IFACE),
        G_VARIANT_TYPE("(a{sv})"),
        G_DBUS_CALL_FLAGS_NONE,
        1000,
        NULL,
        &error);
    if (!reply) {
        if (error) g_error_free(error);
        send_state(0, "", "", "");
        clear_player();
        return;
    }

    GVariant *dict = NULL;
    g_variant_get(reply, "(@a{sv})", &dict);
    guint32 status = 3;
    GVariant *status_v = g_variant_lookup_value(dict, "PlaybackStatus", G_VARIANT_TYPE_STRING);
    if (status_v) {
        const gchar *s = g_variant_get_string(status_v, NULL);
        if (g_strcmp0(s, "Playing") == 0) status = 1;
        else if (g_strcmp0(s, "Paused") == 0) status = 2;
        else status = 3;
        g_variant_unref(status_v);
    }

    const gchar *title = "";
    const gchar *artist = "";
    GVariant *first_artist = NULL;
    GVariant *metadata = g_variant_lookup_value(dict, "Metadata", G_VARIANT_TYPE_VARDICT);
    if (metadata) {
        GVariant *title_v = g_variant_lookup_value(metadata, "xesam:title", G_VARIANT_TYPE_STRING);
        if (title_v) {
            title = g_variant_get_string(title_v, NULL);
            g_variant_unref(title_v);
        }
        GVariant *artist_v = g_variant_lookup_value(metadata, "xesam:artist", G_VARIANT_TYPE_STRING_ARRAY);
        if (artist_v) {
            if (g_variant_n_children(artist_v) > 0) {
                first_artist = g_variant_get_child_value(artist_v, 0);
                artist = g_variant_get_string(first_artist, NULL);
            }
            g_variant_unref(artist_v);
        }
    }

    const gchar *display_player = player_name + strlen(MPRIS_PREFIX);
    send_state(status, title, artist, display_player);
    if (first_artist) g_variant_unref(first_artist);
    if (metadata) g_variant_unref(metadata);
    g_variant_unref(dict);
    g_variant_unref(reply);
}

static gboolean poll_cb(gpointer data) {
    (void)data;
    poll_media();
    return G_SOURCE_CONTINUE;
}

static gboolean command_cb(gpointer data) {
    MediaCommand *command = data;
    if (bus && has_player) {
        const char *method = "PlayPause";
        if (command->code == 2) method = "Next";
        else if (command->code == 3) method = "Previous";
        g_dbus_connection_call(
            bus,
            player_name,
            MPRIS_PATH,
            PLAYER_IFACE,
            method,
            NULL,
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

static gpointer media_thread(gpointer data) {
    (void)data;
    if (stopping) return NULL;
    GError *error = NULL;
    bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
    if (!bus) {
        send_error(error ? error->message : "no session bus");
        if (error) g_error_free(error);
        return NULL;
    }
    loop = g_main_loop_new(NULL, FALSE);
    send_ready();
    poll_media();
    timeout_id = g_timeout_add(700, poll_cb, NULL);
    g_main_loop_run(loop);
    if (timeout_id != 0) {
        g_source_remove(timeout_id);
        timeout_id = 0;
    }
    g_main_loop_unref(loop);
    loop = NULL;
    if (bus) {
        g_object_unref(bus);
        bus = NULL;
    }
    clear_player();
    return NULL;
}

int tessa_media_start(void) {
    if (sock_read >= 0) return sock_read;
    int fds[2];
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, fds) != 0) return -1;
    sock_read = fds[0];
    sock_write = fds[1];
    thread = g_thread_new("tessa-media", media_thread, NULL);
    return sock_read;
}

void tessa_media_stop(void) {
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

void tessa_media_command(unsigned int code) {
    if (!bus) return;
    MediaCommand *command = g_new0(MediaCommand, 1);
    command->code = code;
    g_main_context_invoke(NULL, command_cb, command);
}
