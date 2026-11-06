#define _GNU_SOURCE 1

#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <wayland-client.h>

#include <ext-foreign-toplevel-list-v1-client-protocol.h>
#include <ext-image-capture-source-v1-client-protocol.h>
#include <ext-image-copy-capture-v1-client-protocol.h>

#include "preview.h"

struct handle_info {
	struct ext_foreign_toplevel_handle_v1 *handle;
	struct ext_foreign_toplevel_handle_v1_listener listener;
	char identifier[64];
	bool have_identifier;
	bool closed;
	struct wl_list link;
};

struct preview {
	uint64_t client_id;
	struct handle_info *info;
	struct ext_image_capture_source_v1 *source;
	struct ext_image_copy_capture_session_v1 *session;
	struct ext_image_copy_capture_frame_v1 *frame;
	struct ext_image_copy_capture_session_v1_listener session_listener;
	struct ext_image_copy_capture_frame_v1_listener frame_listener;

	struct wl_buffer *buffer;
	void *data;
	size_t data_size;
	uint32_t width, height, stride, format;
	uint32_t pending_width, pending_height;
	uint32_t pending_format;
	bool have_size;
	bool have_format;
	bool session_done;
	bool inflight;
	bool stopped;

	struct wl_list link;
};

static struct {
	struct wl_display *display;
	struct wl_shm *shm;
	struct ext_foreign_toplevel_image_capture_source_manager_v1 *source_mgr;
	struct ext_image_copy_capture_manager_v1 *capture_mgr;
	tessa_preview_frame_cb frame_cb;
	tessa_preview_gone_cb gone_cb;
	void *userdata;
	struct wl_list handles;
	struct wl_list previews;
	bool initialized;
} P;

static const struct ext_image_copy_capture_frame_v1_listener frame_listener_impl;

static struct handle_info *find_handle(const char *identifier) {
	if (identifier == NULL) {
		return NULL;
	}
	struct handle_info *info;
	wl_list_for_each(info, &P.handles, link) {
		if (!info->closed && info->have_identifier &&
				strcmp(info->identifier, identifier) == 0) {
			return info;
		}
	}
	return NULL;
}

static void preview_free(struct preview *p);

static void preview_request_frame(struct preview *p) {
	if (p->stopped || p->inflight || !p->session_done || p->buffer == NULL ||
			p->session == NULL) {
		return;
	}
	p->frame = ext_image_copy_capture_session_v1_create_frame(p->session);
	if (p->frame == NULL) {
		fprintf(stderr, "tessa-panel: preview: create_frame failed\n");
		return;
	}
	p->frame_listener = frame_listener_impl;
	p->inflight = true;
	ext_image_copy_capture_frame_v1_add_listener(p->frame, &p->frame_listener, p);
	ext_image_copy_capture_frame_v1_attach_buffer(p->frame, p->buffer);
	ext_image_copy_capture_frame_v1_damage_buffer(p->frame, 0, 0,
		(int32_t)p->width, (int32_t)p->height);
	ext_image_copy_capture_frame_v1_capture(p->frame);
}

static void preview_allocate_buffer(struct preview *p) {
	if (!p->have_size || !p->have_format || P.shm == NULL) {
		return;
	}
	if (p->buffer != NULL && p->width == p->pending_width &&
			p->height == p->pending_height && p->format == p->pending_format) {
		return;
	}
	if (p->frame != NULL) {
		ext_image_copy_capture_frame_v1_destroy(p->frame);
		p->frame = NULL;
		p->inflight = false;
	}
	if (p->buffer != NULL) {
		wl_buffer_destroy(p->buffer);
		p->buffer = NULL;
	}
	if (p->data != NULL) {
		munmap(p->data, p->data_size);
		p->data = NULL;
		p->data_size = 0;
	}

	p->width = p->pending_width;
	p->height = p->pending_height;
	p->format = p->pending_format;
	p->stride = p->width * 4;
	p->data_size = (size_t)p->stride * p->height;
	if (p->width == 0 || p->height == 0 || p->data_size == 0) {
		return;
	}
	int fd = memfd_create("tessa-preview", MFD_CLOEXEC);
	if (fd < 0) {
		fprintf(stderr, "tessa-panel: preview: memfd_create failed: %s\n", strerror(errno));
		return;
	}
	if (ftruncate(fd, (off_t)p->data_size) < 0) {
		close(fd);
		return;
	}
	p->data = mmap(NULL, p->data_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (p->data == MAP_FAILED) {
		p->data = NULL;
		close(fd);
		return;
	}
	struct wl_shm_pool *pool = wl_shm_create_pool(P.shm, fd, (int32_t)p->data_size);
	if (pool == NULL) {
		munmap(p->data, p->data_size);
		p->data = NULL;
		close(fd);
		return;
	}
	p->buffer = wl_shm_pool_create_buffer(pool, 0, (int32_t)p->width,
		(int32_t)p->height, (int32_t)p->stride, p->format);
	wl_shm_pool_destroy(pool);
	close(fd);
	if (p->buffer == NULL) {
		munmap(p->data, p->data_size);
		p->data = NULL;
	}
}

static bool preview_format_supported(uint32_t format) {
	return format == WL_SHM_FORMAT_XRGB8888 || format == WL_SHM_FORMAT_ARGB8888 ||
		format == 0x34325258u || format == 0x34325241u ||
		format == 0x34324258u || format == 0x34324241u;
}

static void on_frame_transform(void *data, struct ext_image_copy_capture_frame_v1 *frame, uint32_t transform) {
	(void)data; (void)frame; (void)transform;
}
static void on_frame_damage(void *data, struct ext_image_copy_capture_frame_v1 *frame,
		int32_t x, int32_t y, int32_t width, int32_t height) {
	(void)data; (void)frame; (void)x; (void)y; (void)width; (void)height;
}
static void on_frame_presentation(void *data, struct ext_image_copy_capture_frame_v1 *frame,
		uint32_t sec_hi, uint32_t sec_lo, uint32_t nsec) {
	(void)data; (void)frame; (void)sec_hi; (void)sec_lo; (void)nsec;
}

static void on_frame_ready(void *data, struct ext_image_copy_capture_frame_v1 *frame) {
	struct preview *p = data;
	p->inflight = false;
	if (!p->stopped && p->data != NULL && p->width > 0 && p->height > 0 &&
			P.frame_cb != NULL) {
		P.frame_cb(p->client_id, p->data, p->width, p->height, p->stride,
			p->format, P.userdata);
	}
	ext_image_copy_capture_frame_v1_destroy(frame);
	if (p->frame == frame) {
		p->frame = NULL;
	}
	if (!p->stopped) {
		/* The compositor waits for new damage, so this is damage-driven. */
		preview_request_frame(p);
	}
}

static void on_frame_failed(void *data, struct ext_image_copy_capture_frame_v1 *frame, uint32_t reason) {
	struct preview *p = data;
	fprintf(stderr, "tessa-panel: preview: frame failed id=%llu reason=%u\n", (unsigned long long)p->client_id, reason);
	p->inflight = false;
	(void)reason;
	ext_image_copy_capture_frame_v1_destroy(frame);
	if (p->frame == frame) {
		p->frame = NULL;
	}
	p->stopped = true;
	if (P.gone_cb != NULL) {
		P.gone_cb(p->client_id, P.userdata);
	}
}

static void on_session_buffer_size(void *data, struct ext_image_copy_capture_session_v1 *session,
		uint32_t width, uint32_t height) {
	(void)session;
	struct preview *p = data;
	p->pending_width = width;
	p->pending_height = height;
	p->have_size = width > 0 && height > 0;
}

static void on_session_shm_format(void *data, struct ext_image_copy_capture_session_v1 *session,
		uint32_t format) {
	(void)session;
	struct preview *p = data;
	if (!preview_format_supported(format)) {
		return;
	}
	if (!p->have_format || format == 0x34325258u || format == WL_SHM_FORMAT_XRGB8888) {
		p->pending_format = format;
		p->have_format = true;
	}
}

static void on_session_dmabuf_device(void *data, struct ext_image_copy_capture_session_v1 *session,
		struct wl_array *device) {
	(void)data; (void)session; (void)device;
}
static void on_session_dmabuf_format(void *data, struct ext_image_copy_capture_session_v1 *session,
		uint32_t format, struct wl_array *modifiers) {
	(void)data; (void)session; (void)format; (void)modifiers;
}

static void on_session_done(void *data, struct ext_image_copy_capture_session_v1 *session) {
	(void)session;
	struct preview *p = data;
	p->session_done = true;
	preview_allocate_buffer(p);
	if (p->buffer != NULL) {
		preview_request_frame(p);
	}
}

static void on_session_stopped(void *data, struct ext_image_copy_capture_session_v1 *session) {
	(void)session;
	struct preview *p = data;
	p->stopped = true;
	if (P.gone_cb != NULL) {
		P.gone_cb(p->client_id, P.userdata);
	}
}

static const struct ext_image_copy_capture_frame_v1_listener frame_listener_impl = {
	.transform = on_frame_transform,
	.damage = on_frame_damage,
	.presentation_time = on_frame_presentation,
	.ready = on_frame_ready,
	.failed = on_frame_failed,
};

static const struct ext_image_copy_capture_session_v1_listener session_listener_impl = {
	.buffer_size = on_session_buffer_size,
	.shm_format = on_session_shm_format,
	.dmabuf_device = on_session_dmabuf_device,
	.dmabuf_format = on_session_dmabuf_format,
	.done = on_session_done,
	.stopped = on_session_stopped,
};

static void preview_free(struct preview *p) {
	if (p->frame != NULL) {
		ext_image_copy_capture_frame_v1_destroy(p->frame);
		p->frame = NULL;
	}
	if (p->session != NULL) {
		ext_image_copy_capture_session_v1_destroy(p->session);
		p->session = NULL;
	}
	if (p->source != NULL) {
		ext_image_capture_source_v1_destroy(p->source);
		p->source = NULL;
	}
	if (p->buffer != NULL) {
		wl_buffer_destroy(p->buffer);
		p->buffer = NULL;
	}
	if (p->data != NULL) {
		munmap(p->data, p->data_size);
		p->data = NULL;
	}
	p->stopped = true;
	wl_list_remove(&p->link);
	free(p);
}

struct preview *find_preview(uint64_t client_id) {
	struct preview *p;
	wl_list_for_each(p, &P.previews, link) {
		if (p->client_id == client_id) {
			return p;
		}
	}
	return NULL;
}

int tessa_preview_available(void) {
	return P.initialized && P.display != NULL && P.shm != NULL &&
		P.source_mgr != NULL && P.capture_mgr != NULL;
}

int tessa_preview_start(uint64_t client_id, const char *identifier) {
	if (!tessa_preview_available() || identifier == NULL || identifier[0] == '\0') {
		return 0;
	}
	struct handle_info *info = find_handle(identifier);
	if (info == NULL) {
		return 0;
	}
	struct preview *p = find_preview(client_id);
	if (p != NULL) {
		preview_free(p);
	}
	p = calloc(1, sizeof(*p));
	if (p == NULL) {
		return 0;
	}
	p->client_id = client_id;
	p->info = info;
	p->source = ext_foreign_toplevel_image_capture_source_manager_v1_create_source(
		P.source_mgr, info->handle);
	if (p->source == NULL) {
		free(p);
		return 0;
	}
	p->session = ext_image_copy_capture_manager_v1_create_session(P.capture_mgr,
		p->source, 0);
	if (p->session == NULL) {
		ext_image_capture_source_v1_destroy(p->source);
		free(p);
		return 0;
	}
	memset(&p->session_listener, 0, sizeof(p->session_listener));
	p->session_listener.buffer_size = on_session_buffer_size;
	p->session_listener.shm_format = on_session_shm_format;
	p->session_listener.dmabuf_device = on_session_dmabuf_device;
	p->session_listener.dmabuf_format = on_session_dmabuf_format;
	p->session_listener.done = on_session_done;
	p->session_listener.stopped = on_session_stopped;
	ext_image_copy_capture_session_v1_add_listener(p->session, &p->session_listener, p);
	wl_list_insert(&P.previews, &p->link);
	return 1;
}

void tessa_preview_stop(uint64_t client_id) {
	struct preview *p = find_preview(client_id);
	if (p != NULL) {
		preview_free(p);
	}
}

void tessa_preview_stop_all(void) {
	struct preview *p, *tmp;
	wl_list_for_each_safe(p, tmp, &P.previews, link) {
		preview_free(p);
	}
}

static void on_handle_closed(void *data, struct ext_foreign_toplevel_handle_v1 *handle) {
	struct handle_info *info = data;
	info->closed = true;
	struct preview *p, *tmp;
	wl_list_for_each_safe(p, tmp, &P.previews, link) {
		if (p->info == info) {
			if (P.gone_cb != NULL) {
				P.gone_cb(p->client_id, P.userdata);
			}
			preview_free(p);
		}
	}
	wl_list_remove(&info->link);
	ext_foreign_toplevel_handle_v1_destroy(handle);
	free(info);
}

static void on_handle_done(void *data, struct ext_foreign_toplevel_handle_v1 *handle) {
	(void)data; (void)handle;
}
static void on_handle_title(void *data, struct ext_foreign_toplevel_handle_v1 *handle, const char *title) {
	(void)data; (void)handle; (void)title;
}
static void on_handle_app_id(void *data, struct ext_foreign_toplevel_handle_v1 *handle, const char *app_id) {
	(void)data; (void)handle; (void)app_id;
}
static void on_handle_identifier(void *data, struct ext_foreign_toplevel_handle_v1 *handle,
		const char *identifier) {
	(void)handle;
	struct handle_info *info = data;
	if (identifier == NULL) {
		return;
	}
	strncpy(info->identifier, identifier, sizeof(info->identifier) - 1);
	info->identifier[sizeof(info->identifier) - 1] = '\0';
	info->have_identifier = true;
}


static void on_toplevel(void *data, struct ext_foreign_toplevel_list_v1 *list,
		struct ext_foreign_toplevel_handle_v1 *handle) {
	(void)data; (void)list;
	struct handle_info *info = calloc(1, sizeof(*info));
	if (info == NULL) {
		return;
	}
	info->handle = handle;
	memset(&info->listener, 0, sizeof(info->listener));
	info->listener.closed = on_handle_closed;
	info->listener.done = on_handle_done;
	info->listener.title = on_handle_title;
	info->listener.app_id = on_handle_app_id;
	info->listener.identifier = on_handle_identifier;
	ext_foreign_toplevel_handle_v1_add_listener(handle, &info->listener, info);
	wl_list_insert(&P.handles, &info->link);
}

static void on_list_finished(void *data, struct ext_foreign_toplevel_list_v1 *list) {
	(void)data; (void)list;
}

static const struct ext_foreign_toplevel_list_v1_listener list_listener_impl = {
	.toplevel = on_toplevel,
	.finished = on_list_finished,
};

void tessa_preview_init(struct wl_display *display, struct wl_shm *shm,
		struct ext_foreign_toplevel_list_v1 *list,
		struct ext_foreign_toplevel_image_capture_source_manager_v1 *source_mgr,
		struct ext_image_copy_capture_manager_v1 *capture_mgr,
		tessa_preview_frame_cb frame_cb, tessa_preview_gone_cb gone_cb,
		void *userdata) {
	if (P.initialized) {
		return;
	}
	P.display = display;
	P.shm = shm;
	P.source_mgr = source_mgr;
	P.capture_mgr = capture_mgr;
	P.frame_cb = frame_cb;
	P.gone_cb = gone_cb;
	P.userdata = userdata;
	wl_list_init(&P.handles);
	wl_list_init(&P.previews);
	if (list != NULL) {
		ext_foreign_toplevel_list_v1_add_listener(list, &list_listener_impl, NULL);
	}
	P.initialized = true;
}
