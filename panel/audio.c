#define _GNU_SOURCE

#include "audio.h"

#include <gio/gio.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define MAX_COMMAND 511
#define MAX_SOURCE 15
#define MAX_ERROR 200

typedef enum {
    BACKEND_NONE = 0,
    BACKEND_WPCTL,
    BACKEND_PACTL,
    BACKEND_AMIXER,
    BACKEND_CUSTOM
} Backend;

static GMainLoop *loop;
static GThread *thread;
static guint timeout_id;
static int sock_read = -1;
static int sock_write = -1;
static gboolean stopping;

static char custom_status[MAX_COMMAND + 1];
static char custom_up[MAX_COMMAND + 1];
static char custom_down[MAX_COMMAND + 1];
static char custom_mute[MAX_COMMAND + 1];
static Backend backend;
static const char *source = "none";

static gboolean have_state;
static gint32 last_percent = -1;
static gboolean last_muted;
static char last_source[MAX_SOURCE + 1];

typedef struct {
    guint32 code;
} AudioCommand;

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

static void send_state(gint32 percent, gboolean muted) {
    if (percent < -1) percent = -1;
    if (percent > 150) percent = 150;
    if (have_state && percent == last_percent && muted == last_muted &&
            g_strcmp0(source, last_source) == 0) {
        return;
    }
    have_state = TRUE;
    last_percent = percent;
    last_muted = muted;
    g_strlcpy(last_source, source, sizeof(last_source));

    size_t source_len = strlen(source);
    unsigned char hdr[12];
    memset(hdr, 0, sizeof(hdr));
    hdr[0] = 1;
    hdr[1] = muted ? 1 : 0;
    put_u32(hdr + 4, (uint32_t)percent);
    put_u32(hdr + 8, (uint32_t)source_len);
    write_all(hdr, sizeof(hdr));
    if (source_len > 0) write_all(source, source_len);
}

static gboolean run_sync(const char *cmd, gboolean shell, char **out) {
    *out = NULL;
    if (!cmd || cmd[0] == '\0') return FALSE;
    GError *error = NULL;
    gint wait_status = 0;
    gchar *stdout_buf = NULL;
    gchar *stderr_buf = NULL;
    gboolean ok;
    if (shell) {
        gchar *argv[] = { "/bin/sh", "-c", (gchar *)cmd, NULL };
        ok = g_spawn_sync(NULL, argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL,
            &stdout_buf, &stderr_buf, &wait_status, &error);
    } else {
        ok = g_spawn_command_line_sync(cmd, &stdout_buf, &stderr_buf,
            &wait_status, &error);
    }
    if (!ok) {
        if (error) g_error_free(error);
        g_free(stdout_buf);
        g_free(stderr_buf);
        return FALSE;
    }
    if (!g_spawn_check_wait_status(wait_status, &error)) {
        if (error) g_error_free(error);
        g_free(stdout_buf);
        g_free(stderr_buf);
        return FALSE;
    }
    g_free(stderr_buf);
    *out = stdout_buf;
    return TRUE;
}

static gint32 parse_percent(const char *text) {
    if (!text) return -1;
    const char *pct = strchr(text, '%');
    if (!pct) return -1;
    const char *start = pct;
    while (start > text && g_ascii_isdigit(start[-1])) start--;
    if (start == pct) return -1;
    gint64 value = g_ascii_strtoll(start, NULL, 10);
    if (value < 0) value = 0;
    if (value > 150) value = 150;
    return (gint32)value;
}

static gboolean text_muted(const char *text) {
    if (!text) return FALSE;
    return strstr(text, "[MUTED]") != NULL ||
        strstr(text, "[muted]") != NULL ||
        strstr(text, "MUTED") != NULL ||
        strstr(text, "Mute: yes") != NULL ||
        strstr(text, "[off]") != NULL;
}

static gboolean parse_wpctl(char *out, gint32 *percent, gboolean *muted) {
    const char *volume = strstr(out, "Volume:");
    if (!volume) return FALSE;
    volume += 7;
    while (*volume == ' ') volume++;
    gchar *end = NULL;
    double value = g_ascii_strtod(volume, &end);
    if (end == volume) return FALSE;
    *percent = (gint32)(value * 100.0 + 0.5);
    *muted = strstr(out, "[MUTED]") != NULL;
    return TRUE;
}

static gboolean poll_status(gint32 *percent, gboolean *muted) {
    char *out = NULL;
    gboolean ok = FALSE;
    *percent = -1;
    *muted = FALSE;

    switch (backend) {
    case BACKEND_WPCTL:
        ok = run_sync("wpctl get-volume @DEFAULT_AUDIO_SINK@", FALSE, &out);
        if (ok) ok = parse_wpctl(out, percent, muted);
        break;
    case BACKEND_PACTL: {
        ok = run_sync("pactl get-sink-volume @DEFAULT_SINK@", FALSE, &out);
        if (ok) {
            *percent = parse_percent(out);
            g_free(out);
            out = NULL;
            char *mute_out = NULL;
            if (run_sync("pactl get-sink-mute @DEFAULT_SINK@", FALSE, &mute_out)) {
                *muted = strstr(mute_out, "yes") != NULL;
                g_free(mute_out);
            }
        }
        break;
    }
    case BACKEND_AMIXER:
        ok = run_sync("amixer get Master", FALSE, &out);
        if (ok) {
            *percent = parse_percent(out);
            *muted = text_muted(out);
        }
        break;
    case BACKEND_CUSTOM:
        ok = run_sync(custom_status, TRUE, &out);
        if (ok) {
            *percent = parse_percent(out);
            *muted = text_muted(out);
        }
        break;
    default:
        return FALSE;
    }

    if (out) g_free(out);
    if (!ok) {
        *percent = -1;
        *muted = FALSE;
    }
    return ok;
}

static void select_backend(void) {
    if (custom_status[0] != '\0') {
        backend = BACKEND_CUSTOM;
        source = "custom";
        return;
    }
    gchar *path = g_find_program_in_path("wpctl");
    if (path) {
        g_free(path);
        backend = BACKEND_WPCTL;
        source = "wpctl";
        return;
    }
    path = g_find_program_in_path("pactl");
    if (path) {
        g_free(path);
        backend = BACKEND_PACTL;
        source = "pactl";
        return;
    }
    path = g_find_program_in_path("amixer");
    if (path) {
        g_free(path);
        backend = BACKEND_AMIXER;
        source = "amixer";
        return;
    }
    backend = BACKEND_NONE;
    source = "none";
}

static void poll_audio(void) {
    gint32 percent = -1;
    gboolean muted = FALSE;
    if (backend != BACKEND_NONE) {
        poll_status(&percent, &muted);
    }
    send_state(percent, muted);
}

static gboolean poll_cb(gpointer data) {
    (void)data;
    poll_audio();
    return G_SOURCE_CONTINUE;
}

static gboolean poll_once_cb(gpointer data) {
    (void)data;
    poll_audio();
    return G_SOURCE_REMOVE;
}

static char *action_command(guint32 code) {
    if (backend == BACKEND_NONE) return NULL;
    const char *custom = code == 1 ? custom_up : code == 2 ? custom_down :
        custom_mute;
    if (custom[0] != '\0') return g_strdup(custom);
    if (backend == BACKEND_CUSTOM) return NULL;
    if (backend == BACKEND_WPCTL) {
        if (code == 1) return g_strdup("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+");
        if (code == 2) return g_strdup("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-");
        return g_strdup("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle");
    }
    if (backend == BACKEND_PACTL) {
        if (code == 1) return g_strdup("pactl set-sink-volume @DEFAULT_SINK@ +5%");
        if (code == 2) return g_strdup("pactl set-sink-volume @DEFAULT_SINK@ -5%");
        return g_strdup("pactl set-sink-mute @DEFAULT_SINK@ toggle");
    }
    if (code == 1) return g_strdup("amixer -q sset Master 5%+");
    if (code == 2) return g_strdup("amixer -q sset Master 5%-");
    return g_strdup("amixer -q sset Master toggle");
}

static gboolean command_cb(gpointer data) {
    AudioCommand *command = data;
    char *cmd = action_command(command->code);
    if (cmd) {
        GError *error = NULL;
        gchar *argv[] = { "/bin/sh", "-c", cmd, NULL };
        g_spawn_async(NULL, argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL,
            NULL, &error);
        if (error) g_error_free(error);
        g_free(cmd);
        g_timeout_add(250, poll_once_cb, NULL);
    }
    g_free(command);
    return G_SOURCE_REMOVE;
}

static gpointer audio_thread(gpointer data) {
    (void)data;
    select_backend();
    loop = g_main_loop_new(NULL, FALSE);
    if (stopping) {
        g_main_loop_unref(loop);
        loop = NULL;
        return NULL;
    }
    send_ready();
    poll_audio();
    if (backend != BACKEND_NONE) {
        timeout_id = g_timeout_add(1000, poll_cb, NULL);
    }
    g_main_loop_run(loop);
    if (timeout_id != 0) {
        g_source_remove(timeout_id);
        timeout_id = 0;
    }
    g_main_loop_unref(loop);
    loop = NULL;
    return NULL;
}

int tessa_audio_start(const char *status_cmd, const char *up_cmd,
        const char *down_cmd, const char *mute_cmd) {
    if (sock_read >= 0) return sock_read;
    stopping = FALSE;
    have_state = FALSE;
    last_percent = -1;
    last_muted = FALSE;
    last_source[0] = '\0';
    g_strlcpy(custom_status, status_cmd ? status_cmd : "", sizeof(custom_status));
    g_strlcpy(custom_up, up_cmd ? up_cmd : "", sizeof(custom_up));
    g_strlcpy(custom_down, down_cmd ? down_cmd : "", sizeof(custom_down));
    g_strlcpy(custom_mute, mute_cmd ? mute_cmd : "", sizeof(custom_mute));
    int fds[2];
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, fds) != 0) return -1;
    sock_read = fds[0];
    sock_write = fds[1];
    thread = g_thread_new("tessa-audio", audio_thread, NULL);
    return sock_read;
}

void tessa_audio_stop(void) {
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

void tessa_audio_command(unsigned int code) {
    if (sock_write < 0) return;
    AudioCommand *command = g_new0(AudioCommand, 1);
    command->code = code;
    g_main_context_invoke(NULL, command_cb, command);
}
