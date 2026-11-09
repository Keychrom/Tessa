#include "audio.h"

#include <gio/gio.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define MAX_COMMAND 511
#define MAX_SOURCE 15
#define MAX_ERROR 200
#define MAX_DEVICES 8
#define MAX_ID 128
#define MAX_NAME 96
#define MAX_DETAIL 64
#define DEVICE_POLL_US (3 * G_USEC_PER_SEC)

typedef enum {
    BACKEND_NONE = 0,
    BACKEND_WPCTL,
    BACKEND_PACTL,
    BACKEND_AMIXER,
    BACKEND_CUSTOM
} Backend;

typedef enum {
    DIR_OUTPUT = 0,
    DIR_INPUT = 1
} Direction;

typedef struct {
    char id[MAX_ID];
    char name[MAX_NAME];
    char detail[MAX_DETAIL];
    gboolean is_default;
} AudioDevice;

typedef struct {
    gint32 percent;
    gboolean muted;
    AudioDevice devices[MAX_DEVICES];
    guint count;
} AudioState;

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
static gboolean device_selection;

static AudioState output_state;
static AudioState input_state;
static AudioState last_output_state;
static AudioState last_input_state;
static gboolean have_state;
static gboolean force_devices = TRUE;
static gint64 last_device_poll_us;
static char last_source[MAX_SOURCE + 1];

typedef struct {
    guint32 code;
    gint32 percent;
    char id[MAX_ID];
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

static void reset_audio_state(AudioState *state) {
    memset(state, 0, sizeof(*state));
    state->percent = -1;
}

static gboolean device_equal(const AudioDevice *a, const AudioDevice *b) {
    return a->is_default == b->is_default &&
        strcmp(a->id, b->id) == 0 &&
        strcmp(a->name, b->name) == 0 &&
        strcmp(a->detail, b->detail) == 0;
}

static gboolean state_equal(const AudioState *a, const AudioState *b) {
    if (a->percent != b->percent || a->muted != b->muted || a->count != b->count) {
        return FALSE;
    }
    for (guint i = 0; i < a->count; i++) {
        if (!device_equal(&a->devices[i], &b->devices[i])) return FALSE;
    }
    return TRUE;
}

static void append_device(unsigned char *buf, size_t *off, const AudioDevice *device) {
    guint32 id_len = (guint32)strlen(device->id);
    guint32 name_len = (guint32)strlen(device->name);
    guint32 detail_len = (guint32)strlen(device->detail);
    put_u32(buf + *off, id_len);
    *off += 4;
    put_u32(buf + *off, name_len);
    *off += 4;
    put_u32(buf + *off, detail_len);
    *off += 4;
    buf[(*off)++] = device->is_default ? 1 : 0;
    memcpy(buf + *off, device->id, id_len);
    *off += id_len;
    memcpy(buf + *off, device->name, name_len);
    *off += name_len;
    memcpy(buf + *off, device->detail, detail_len);
    *off += detail_len;
}

static void send_state(void) {
    if (have_state &&
            state_equal(&output_state, &last_output_state) &&
            state_equal(&input_state, &last_input_state) &&
            g_strcmp0(source, last_source) == 0) {
        return;
    }

    unsigned char buf[8192];
    size_t off = 0;
    buf[off++] = 6;
    buf[off++] = output_state.muted ? 1 : 0;
    buf[off++] = input_state.muted ? 1 : 0;
    buf[off++] = (output_state.percent >= 0 ? 1 : 0) |
        (input_state.percent >= 0 ? 2 : 0) |
        (device_selection ? 4 : 0);
    put_u32(buf + off, output_state.percent < 0 ? 0xffffffffu : (guint32)output_state.percent);
    off += 4;
    put_u32(buf + off, input_state.percent < 0 ? 0xffffffffu : (guint32)input_state.percent);
    off += 4;
    put_u32(buf + off, output_state.count);
    off += 4;
    put_u32(buf + off, input_state.count);
    off += 4;
    size_t source_len = strlen(source);
    put_u32(buf + off, (guint32)source_len);
    off += 4;
    memcpy(buf + off, source, source_len);
    off += source_len;

    for (guint i = 0; i < output_state.count; i++) {
        append_device(buf, &off, &output_state.devices[i]);
    }
    for (guint i = 0; i < input_state.count; i++) {
        append_device(buf, &off, &input_state.devices[i]);
    }

    write_all(buf, off);
    last_output_state = output_state;
    last_input_state = input_state;
    g_strlcpy(last_source, source, sizeof(last_source));
    have_state = TRUE;
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

static gboolean poll_volume(Direction dir, gint32 *percent, gboolean *muted) {
    char cmd[MAX_COMMAND + 1];
    char *out = NULL;
    gboolean ok = FALSE;
    *percent = -1;
    *muted = FALSE;

    switch (backend) {
    case BACKEND_WPCTL:
        snprintf(cmd, sizeof(cmd), "wpctl get-volume %s",
            dir == DIR_OUTPUT ? "@DEFAULT_AUDIO_SINK@" : "@DEFAULT_AUDIO_SOURCE@");
        ok = run_sync(cmd, FALSE, &out);
        if (ok) ok = parse_wpctl(out, percent, muted);
        break;
    case BACKEND_PACTL:
        snprintf(cmd, sizeof(cmd), "pactl get-%s-volume @DEFAULT_%s@",
            dir == DIR_OUTPUT ? "sink" : "source",
            dir == DIR_OUTPUT ? "SINK" : "SOURCE");
        ok = run_sync(cmd, FALSE, &out);
        if (ok) {
            *percent = parse_percent(out);
            g_free(out);
            out = NULL;
            char mute_cmd[MAX_COMMAND + 1];
            snprintf(mute_cmd, sizeof(mute_cmd), "pactl get-%s-mute @DEFAULT_%s@",
                dir == DIR_OUTPUT ? "sink" : "source",
                dir == DIR_OUTPUT ? "SINK" : "SOURCE");
            char *mute_out = NULL;
            if (run_sync(mute_cmd, FALSE, &mute_out)) {
                *muted = strstr(mute_out, "yes") != NULL;
                g_free(mute_out);
            }
        }
        break;
    case BACKEND_AMIXER:
        snprintf(cmd, sizeof(cmd), "amixer get %s",
            dir == DIR_OUTPUT ? "Master" : "Capture");
        ok = run_sync(cmd, FALSE, &out);
        if (ok) {
            *percent = parse_percent(out);
            *muted = text_muted(out);
        }
        break;
    case BACKEND_CUSTOM:
        if (dir == DIR_OUTPUT) {
            ok = run_sync(custom_status, TRUE, &out);
            if (ok) {
                *percent = parse_percent(out);
                *muted = text_muted(out);
            }
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

static void add_device(AudioState *state, const char *id, const char *name,
        const char *detail, gboolean is_default) {
    if (state->count >= MAX_DEVICES || !id || !id[0]) return;
    AudioDevice *device = &state->devices[state->count++];
    g_strlcpy(device->id, id, sizeof(device->id));
    g_strlcpy(device->name, name && name[0] ? name : id, sizeof(device->name));
    g_strlcpy(device->detail, detail ? detail : "", sizeof(device->detail));
    device->is_default = is_default;
}

static void parse_wpctl_devices(const char *text) {
    enum { SECTION_NONE, SECTION_SINKS, SECTION_SOURCES } section = SECTION_NONE;
    enum { MEDIA_NONE, MEDIA_AUDIO, MEDIA_VIDEO } media = MEDIA_NONE;
    output_state.count = 0;
    input_state.count = 0;

    gchar **lines = g_strsplit(text, "\n", -1);
    for (guint i = 0; lines[i]; i++) {
        const char *line = lines[i];
        const char *head = line;
        while (*head == ' ' || *head == '\t') head++;
        if (g_str_has_prefix(head, "Audio") &&
                (head[5] == '\0' || head[5] == ' ')) {
            media = MEDIA_AUDIO;
            section = SECTION_NONE;
            continue;
        }
        if (g_str_has_prefix(head, "Video") &&
                (head[5] == '\0' || head[5] == ' ')) {
            media = MEDIA_VIDEO;
            section = SECTION_NONE;
            continue;
        }
        if (g_str_has_prefix(head, "Settings")) {
            media = MEDIA_NONE;
            section = SECTION_NONE;
            continue;
        }
        if (media != MEDIA_AUDIO) continue;
        if (strstr(line, "Sinks:")) {
            section = SECTION_SINKS;
            continue;
        }
        if (strstr(line, "Sources:")) {
            section = SECTION_SOURCES;
            continue;
        }
        if (strstr(line, "Devices:") || strstr(line, "Filters:") ||
                strstr(line, "Streams:") || strstr(line, "Clients:") ||
                strstr(line, "Modules:")) {
            section = SECTION_NONE;
            continue;
        }
        if (section == SECTION_NONE) continue;

        const char *digit = line;
        while (*digit && !g_ascii_isdigit(*digit)) digit++;
        if (!*digit) continue;
        char *end = NULL;
        long id = strtol(digit, &end, 10);
        if (end == digit || *end != '.') continue;
        const char *desc = end + 1;
        while (*desc == ' ') desc++;
        const char *bracket = strchr(desc, '[');
        size_t len = bracket ? (size_t)(bracket - desc) : strlen(desc);
        char name[MAX_NAME];
        if (len >= sizeof(name)) len = sizeof(name) - 1;
        memcpy(name, desc, len);
        name[len] = '\0';
        g_strstrip(name);
        if (!name[0]) continue;

        const char *star = strchr(line, '*');
        gboolean is_default = star && star < digit;
        char id_text[32];
        snprintf(id_text, sizeof(id_text), "%ld", id);
        char detail[MAX_DETAIL];
        snprintf(detail, sizeof(detail), "node %ld", id);
        if (section == SECTION_SINKS) {
            add_device(&output_state, id_text, name, detail, is_default);
        } else {
            add_device(&input_state, id_text, name, detail, is_default);
        }
    }
    g_strfreev(lines);
}

static void flush_pactl_device(AudioState *state, const char *id,
        const char *name, const char *default_name, gboolean skip) {
    if (skip || !id[0]) return;
    gboolean is_default = default_name && strcmp(id, default_name) == 0;
    add_device(state, id, name[0] ? name : id, id, is_default);
}

static void parse_pactl_list(const char *text, AudioState *state,
        const char *default_name, gboolean sources) {
    state->count = 0;
    gchar **lines = g_strsplit(text, "\n", -1);
    char id[MAX_ID] = "";
    char name[MAX_NAME] = "";
    gboolean in_block = FALSE;
    gboolean skip = FALSE;

    for (guint i = 0; lines[i]; i++) {
        const char *p = lines[i];
        while (*p == ' ' || *p == '\t') p++;
        if (g_str_has_prefix(p, "Sink #") || g_str_has_prefix(p, "Source #")) {
            flush_pactl_device(state, id, name, default_name, skip);
            in_block = TRUE;
            skip = FALSE;
            id[0] = '\0';
            name[0] = '\0';
            continue;
        }
        if (!in_block) continue;
        if (g_str_has_prefix(p, "Name:")) {
            const char *value = p + 5;
            while (*value == ' ' || *value == '\t') value++;
            g_strlcpy(id, value, sizeof(id));
            g_strstrip(id);
            if (sources && g_str_has_suffix(id, ".monitor")) skip = TRUE;
        } else if (g_str_has_prefix(p, "Description:")) {
            const char *value = p + 12;
            while (*value == ' ' || *value == '\t') value++;
            g_strlcpy(name, value, sizeof(name));
            g_strstrip(name);
        } else if (sources && g_str_has_prefix(p, "Monitor of Sink:")) {
            skip = TRUE;
        } else if (*p == '\0') {
            flush_pactl_device(state, id, name, default_name, skip);
            in_block = FALSE;
            id[0] = '\0';
            name[0] = '\0';
        }
    }
    flush_pactl_device(state, id, name, default_name, skip);
    g_strfreev(lines);
}

static char *pactl_default_name(const char *kind) {
    char cmd[64];
    snprintf(cmd, sizeof(cmd), "pactl get-default-%s", kind);
    char *out = NULL;
    if (run_sync(cmd, FALSE, &out)) {
        g_strstrip(out);
        if (out[0]) return out;
        g_free(out);
    }

    out = NULL;
    if (!run_sync("pactl info", FALSE, &out)) return NULL;
    char *result = NULL;
    const char *prefix = strcmp(kind, "sink") == 0 ? "Default Sink:" : "Default Source:";
    gchar **lines = g_strsplit(out, "\n", -1);
    for (guint i = 0; lines[i]; i++) {
        if (g_str_has_prefix(lines[i], prefix)) {
            const char *value = lines[i] + strlen(prefix);
            while (*value == ' ' || *value == '\t') value++;
            result = g_strdup(value);
            g_strstrip(result);
            break;
        }
    }
    g_strfreev(lines);
    g_free(out);
    return result;
}

static void poll_devices(void) {
    if (backend == BACKEND_WPCTL) {
        char *out = NULL;
        if (run_sync("LC_ALL=C wpctl status", TRUE, &out)) {
            parse_wpctl_devices(out);
        } else {
            output_state.count = 0;
            input_state.count = 0;
        }
        g_free(out);
    } else if (backend == BACKEND_PACTL) {
        char *default_sink = pactl_default_name("sink");
        char *default_source = pactl_default_name("source");
        char *out = NULL;
        if (run_sync("LC_ALL=C pactl list sinks", TRUE, &out)) {
            parse_pactl_list(out, &output_state, default_sink, FALSE);
        } else {
            output_state.count = 0;
        }
        g_free(out);
        out = NULL;
        if (run_sync("LC_ALL=C pactl list sources", TRUE, &out)) {
            parse_pactl_list(out, &input_state, default_source, TRUE);
        } else {
            input_state.count = 0;
        }
        g_free(out);
        g_free(default_sink);
        g_free(default_source);
    } else {
        output_state.count = 0;
        input_state.count = 0;
    }
    last_device_poll_us = g_get_monotonic_time();
}

static void poll_audio(void) {
    if (backend != BACKEND_NONE) {
        poll_volume(DIR_OUTPUT, &output_state.percent, &output_state.muted);
        poll_volume(DIR_INPUT, &input_state.percent, &input_state.muted);
        gint64 now = g_get_monotonic_time();
        if (force_devices || now - last_device_poll_us >= DEVICE_POLL_US) {
            poll_devices();
        }
    } else {
        output_state.percent = -1;
        input_state.percent = -1;
        output_state.count = 0;
        input_state.count = 0;
    }
    send_state();
    force_devices = FALSE;
}

static void select_backend(void) {
    if (custom_status[0] != '\0') {
        backend = BACKEND_CUSTOM;
        source = "custom";
        device_selection = FALSE;
        return;
    }
    gchar *path = g_find_program_in_path("wpctl");
    if (path) {
        g_free(path);
        backend = BACKEND_WPCTL;
        source = "wpctl";
        device_selection = TRUE;
        return;
    }
    path = g_find_program_in_path("pactl");
    if (path) {
        g_free(path);
        backend = BACKEND_PACTL;
        source = "pactl";
        device_selection = TRUE;
        return;
    }
    path = g_find_program_in_path("amixer");
    if (path) {
        g_free(path);
        backend = BACKEND_AMIXER;
        source = "amixer";
        device_selection = FALSE;
        return;
    }
    backend = BACKEND_NONE;
    source = "none";
    device_selection = FALSE;
}

static char *volume_step_command(Direction dir, gboolean up) {
    char cmd[256];
    if (backend == BACKEND_WPCTL) {
        snprintf(cmd, sizeof(cmd), "wpctl set-volume %s 5%%%s",
            dir == DIR_OUTPUT ? "@DEFAULT_AUDIO_SINK@" : "@DEFAULT_AUDIO_SOURCE@",
            up ? "+" : "-");
        return g_strdup(cmd);
    }
    if (backend == BACKEND_PACTL) {
        snprintf(cmd, sizeof(cmd), "pactl set-%s-volume @DEFAULT_%s@ 5%%%s",
            dir == DIR_OUTPUT ? "sink" : "source",
            dir == DIR_OUTPUT ? "SINK" : "SOURCE",
            up ? "+" : "-");
        return g_strdup(cmd);
    }
    if (backend == BACKEND_AMIXER) {
        snprintf(cmd, sizeof(cmd), "amixer -q sset %s 5%%%s",
            dir == DIR_OUTPUT ? "Master" : "Capture",
            up ? "+" : "-");
        return g_strdup(cmd);
    }
    if (backend == BACKEND_CUSTOM && dir == DIR_OUTPUT) {
        return g_strdup(up ? custom_up : custom_down);
    }
    return NULL;
}

static char *volume_absolute_command(Direction dir, int percent) {
    char cmd[256];
    if (percent < 0) percent = 0;
    if (percent > 150) percent = 150;
    if (backend == BACKEND_WPCTL) {
        snprintf(cmd, sizeof(cmd), "wpctl set-volume %s %d%%",
            dir == DIR_OUTPUT ? "@DEFAULT_AUDIO_SINK@" : "@DEFAULT_AUDIO_SOURCE@",
            percent);
        return g_strdup(cmd);
    }
    if (backend == BACKEND_PACTL) {
        snprintf(cmd, sizeof(cmd), "pactl set-%s-volume @DEFAULT_%s@ %d%%",
            dir == DIR_OUTPUT ? "sink" : "source",
            dir == DIR_OUTPUT ? "SINK" : "SOURCE",
            percent);
        return g_strdup(cmd);
    }
    if (backend == BACKEND_AMIXER) {
        snprintf(cmd, sizeof(cmd), "amixer -q sset %s %d%%",
            dir == DIR_OUTPUT ? "Master" : "Capture",
            percent);
        return g_strdup(cmd);
    }
    return NULL;
}

static char *mute_command(Direction dir) {
    char cmd[256];
    if (backend == BACKEND_WPCTL) {
        snprintf(cmd, sizeof(cmd), "wpctl set-mute %s toggle",
            dir == DIR_OUTPUT ? "@DEFAULT_AUDIO_SINK@" : "@DEFAULT_AUDIO_SOURCE@");
        return g_strdup(cmd);
    }
    if (backend == BACKEND_PACTL) {
        snprintf(cmd, sizeof(cmd), "pactl set-%s-mute @DEFAULT_%s@ toggle",
            dir == DIR_OUTPUT ? "sink" : "source",
            dir == DIR_OUTPUT ? "SINK" : "SOURCE");
        return g_strdup(cmd);
    }
    if (backend == BACKEND_AMIXER) {
        snprintf(cmd, sizeof(cmd), "amixer -q sset %s toggle",
            dir == DIR_OUTPUT ? "Master" : "Capture");
        return g_strdup(cmd);
    }
    if (backend == BACKEND_CUSTOM && dir == DIR_OUTPUT) {
        return g_strdup(custom_mute);
    }
    return NULL;
}

static gboolean valid_node_id(const char *id) {
    if (!id || !id[0]) return FALSE;
    for (const char *p = id; *p; p++) {
        if (!g_ascii_isdigit(*p)) return FALSE;
    }
    return TRUE;
}

static char *default_device_command(Direction dir, const char *id) {
    if (!id || !id[0]) return NULL;
    char cmd[512];
    if (backend == BACKEND_WPCTL) {
        if (!valid_node_id(id)) return NULL;
        snprintf(cmd, sizeof(cmd), "wpctl set-default %s", id);
        return g_strdup(cmd);
    }
    if (backend == BACKEND_PACTL) {
        gchar *quoted = g_shell_quote(id);
        snprintf(cmd, sizeof(cmd), "pactl set-default-%s %s",
            dir == DIR_OUTPUT ? "sink" : "source", quoted);
        g_free(quoted);
        return g_strdup(cmd);
    }
    return NULL;
}

static gboolean action_command(guint32 code) {
    Direction dir = (code == 5 || code == 6 || code == 7 || code == 8)
        ? DIR_INPUT
        : DIR_OUTPUT;
    if (backend == BACKEND_CUSTOM && dir == DIR_INPUT) return FALSE;
    if (code == 4 || code == 8) return TRUE;

    char *cmd = NULL;
    if (code == 1 || code == 5) {
        cmd = volume_step_command(dir, TRUE);
    } else if (code == 2 || code == 6) {
        cmd = volume_step_command(dir, FALSE);
    } else if (code == 3 || code == 7) {
        cmd = mute_command(dir);
    }
    if (!cmd) return FALSE;
    if (!cmd[0]) {
        g_free(cmd);
        return FALSE;
    }

    GError *error = NULL;
    gchar *argv[] = { "/bin/sh", "-c", cmd, NULL };
    g_spawn_async(NULL, argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, &error);
    if (error) g_error_free(error);
    g_free(cmd);
    return TRUE;
}

static gboolean poll_once_cb(gpointer data);

static gboolean command_cb(gpointer data) {
    AudioCommand *command = data;
    char *cmd = NULL;
    gboolean ran = FALSE;
    Direction dir = (command->code == 5 || command->code == 6 ||
        command->code == 7 || command->code == 8 || command->code == 10)
        ? DIR_INPUT
        : DIR_OUTPUT;

    if (command->code == 9 || command->code == 10) {
        cmd = default_device_command(dir, command->id);
        if (cmd) force_devices = TRUE;
    } else if (command->code == 4 || command->code == 8) {
        cmd = volume_absolute_command(dir, command->percent);
    } else {
        ran = action_command(command->code);
    }

    if (cmd) {
        GError *error = NULL;
        gchar *argv[] = { "/bin/sh", "-c", cmd, NULL };
        g_spawn_async(NULL, argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, &error);
        if (error) g_error_free(error);
        g_free(cmd);
        ran = TRUE;
    }
    if (ran) g_timeout_add(250, poll_once_cb, NULL);
    g_free(command);
    return G_SOURCE_REMOVE;
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
    device_selection = FALSE;
    force_devices = TRUE;
    last_device_poll_us = 0;
    last_source[0] = '\0';
    reset_audio_state(&output_state);
    reset_audio_state(&input_state);
    reset_audio_state(&last_output_state);
    reset_audio_state(&last_input_state);
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

void tessa_audio_set_percent(int percent) {
    if (sock_write < 0) return;
    AudioCommand *command = g_new0(AudioCommand, 1);
    command->code = 4;
    command->percent = percent;
    g_main_context_invoke(NULL, command_cb, command);
}

void tessa_audio_set_input_percent(int percent) {
    if (sock_write < 0) return;
    AudioCommand *command = g_new0(AudioCommand, 1);
    command->code = 8;
    command->percent = percent;
    g_main_context_invoke(NULL, command_cb, command);
}

void tessa_audio_set_default(int direction, const char *id) {
    if (sock_write < 0 || !id) return;
    AudioCommand *command = g_new0(AudioCommand, 1);
    command->code = direction == DIR_INPUT ? 10 : 9;
    g_strlcpy(command->id, id, sizeof(command->id));
    g_main_context_invoke(NULL, command_cb, command);
}
