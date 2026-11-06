#define WLR_USE_UNSTABLE 1
#define _GNU_SOURCE 1

#include <drm_fourcc.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <wlr/backend/interface.h>
#include <wlr/interfaces/wlr_ext_image_capture_source_v1.h>
#include <wlr/interfaces/wlr_output.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_ext_image_capture_source_v1.h>
#include <wlr/types/wlr_ext_image_copy_capture_v1.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/util/log.h>

#include "preview_source.h"

/*
 * This is a small variant of wlroots' scene-node capture source. The
 * difference is that the private output can be rendered at a lower scale:
 * the scene graph still uses the window's native logical coordinates, while
 * the capture buffer is capped at max_dim pixels.
 */
struct tessa_preview_source {
	struct wlr_ext_image_capture_source_v1 base;

	struct wlr_surface *surface;
	struct wlr_scene *scene;
	struct wlr_scene_tree *clone;
	int max_dim;

	struct wlr_backend backend;
	struct wlr_output output;
	struct wlr_scene_output *scene_output;
	size_t num_started;

	struct wl_listener surface_destroy;
	struct wl_listener output_frame;

	void (*on_destroy)(void *userdata);
	void *userdata;
	bool alive;
};

struct tessa_preview_frame_event {
	struct wlr_ext_image_capture_source_v1_frame_event base;
	struct wlr_buffer *buffer;
	struct timespec when;
};

static float preview_scale(struct tessa_preview_source *source, int *logical_w, int *logical_h) {
	int w = source->surface->current.width;
	int h = source->surface->current.height;
	*logical_w = w > 0 ? w : 1;
	*logical_h = h > 0 ? h : 1;
	int longest = *logical_w > *logical_h ? *logical_w : *logical_h;
	float scale = 1.0f;
	if (source->max_dim > 0 && longest > source->max_dim) {
		scale = (float)source->max_dim / (float)longest;
	}
	return scale;
}

static void source_render(struct tessa_preview_source *source) {
	int logical_w, logical_h;
	float scale = preview_scale(source, &logical_w, &logical_h);
	if (source->surface->current.width <= 0 || source->surface->current.height <= 0) {
		return;
	}
	int width = (int)lroundf((float)logical_w * scale);
	int height = (int)lroundf((float)logical_h * scale);
	if (width < 1) width = 1;
	if (height < 1) height = 1;

	wlr_scene_output_set_position(source->scene_output, 0, 0);

	struct wlr_output_state state;
	wlr_output_state_init(&state);
	wlr_output_state_set_enabled(&state, true);
	wlr_output_state_set_custom_mode(&state, width, height, 0);
	wlr_output_state_set_scale(&state, (float)width / (float)logical_w);
	bool ok = wlr_scene_output_build_state(source->scene_output, &state, NULL) &&
		wlr_output_commit_state(source->scene_output->output, &state);
	wlr_output_state_finish(&state);

	if (!ok) {
		wlr_log(WLR_DEBUG, "preview: failed to render %dx%d", width, height);
	}
}

static void source_start(struct wlr_ext_image_capture_source_v1 *base, bool with_cursors) {
	(void)with_cursors;
	struct tessa_preview_source *source = wl_container_of(base, source, base);
	source->num_started++;
	if (source->num_started > 1) {
		return;
	}
	source_render(source);
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	wlr_scene_output_send_frame_done(source->scene_output, &now);
}

static void source_stop(struct wlr_ext_image_capture_source_v1 *base) {
	struct tessa_preview_source *source = wl_container_of(base, source, base);
	if (source->num_started > 0) {
		source->num_started--;
	}
	if (source->num_started > 0) {
		return;
	}
	struct wlr_output_state state;
	wlr_output_state_init(&state);
	wlr_output_state_set_enabled(&state, false);
	wlr_output_commit_state(&source->output, &state);
	wlr_output_state_finish(&state);
}

static void source_request_frame(struct wlr_ext_image_capture_source_v1 *base, bool schedule_frame) {
	struct tessa_preview_source *source = wl_container_of(base, source, base);
	if (source->output.frame_pending) {
		wlr_output_send_frame(&source->output);
	}
	if (schedule_frame) {
		wlr_output_update_needs_frame(&source->output);
	}
}

static void source_copy_frame(struct wlr_ext_image_capture_source_v1 *base,
		struct wlr_ext_image_copy_capture_frame_v1 *frame,
		struct wlr_ext_image_capture_source_v1_frame_event *base_event) {
	struct tessa_preview_source *source = wl_container_of(base, source, base);
	struct tessa_preview_frame_event *event = wl_container_of(base_event, event, base);
	if (wlr_ext_image_copy_capture_frame_v1_copy_buffer(frame, event->buffer,
			source->output.renderer)) {
		wlr_ext_image_copy_capture_frame_v1_ready(frame, source->output.transform,
			&event->when);
	}
}

static const struct wlr_ext_image_capture_source_v1_interface source_impl = {
	.start = source_start,
	.stop = source_stop,
	.request_frame = source_request_frame,
	.copy_frame = source_copy_frame,
};

static const struct wlr_backend_impl backend_impl = {0};

static void source_update_buffer_constraints(struct tessa_preview_source *source,
		const struct wlr_output_state *state) {
	struct wlr_output *output = &source->output;
	if (!wlr_output_configure_primary_swapchain(output, state, &output->swapchain)) {
		return;
	}
	wlr_ext_image_capture_source_v1_set_constraints_from_swapchain(&source->base,
		output->swapchain, output->renderer);
	if (source->base.shm_formats_len == 0) {
		uint32_t *formats = calloc(1, sizeof(uint32_t));
		if (formats != NULL) {
			formats[0] = DRM_FORMAT_XRGB8888;
			free(source->base.shm_formats);
			source->base.shm_formats = formats;
			source->base.shm_formats_len = 1;
		}
	}
}

static bool output_test(struct wlr_output *output, const struct wlr_output_state *state) {
	(void)output;
	uint32_t supported = WLR_OUTPUT_STATE_BACKEND_OPTIONAL |
		WLR_OUTPUT_STATE_BUFFER | WLR_OUTPUT_STATE_ENABLED | WLR_OUTPUT_STATE_MODE;
	if ((state->committed & ~supported) != 0) {
		return false;
	}
	/* The preview output is private; the scene output owns its swapchain. */
	return true;
}

static bool output_commit(struct wlr_output *output, const struct wlr_output_state *state) {
	struct tessa_preview_source *source = wl_container_of(output, source, output);
	if ((state->committed & WLR_OUTPUT_STATE_ENABLED) && !state->enabled) {
		return true;
	}
	if (state->committed & WLR_OUTPUT_STATE_MODE) {
		source_update_buffer_constraints(source, state);
	}
	if (!(state->committed & WLR_OUTPUT_STATE_BUFFER)) {
		return false;
	}

	struct wlr_buffer *buffer = state->buffer;
	pixman_region32_t full_damage;
	pixman_region32_init_rect(&full_damage, 0, 0, buffer->width, buffer->height);
	const pixman_region32_t *damage = state->committed & WLR_OUTPUT_STATE_DAMAGE
		? &state->damage : &full_damage;

	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	struct tessa_preview_frame_event event = {
		.base = { .damage = damage },
		.buffer = buffer,
		.when = now,
	};
	wl_signal_emit_mutable(&source->base.events.frame, &event.base);
	pixman_region32_fini(&full_damage);
	return true;
}

static const struct wlr_output_impl output_impl = {
	.test = output_test,
	.commit = output_commit,
};

static void source_handle_output_frame(struct wl_listener *listener, void *data) {
	(void)data;
	struct tessa_preview_source *source = wl_container_of(listener, source, output_frame);
	if (source->scene_output == NULL) {
		return;
	}
	if (!wlr_scene_output_needs_frame(source->scene_output)) {
		return;
	}
	source_render(source);
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	wlr_scene_output_send_frame_done(source->scene_output, &now);
}

static void source_handle_surface_destroy(struct wl_listener *listener, void *data) {
	(void)data;
	struct tessa_preview_source *source = wl_container_of(listener, source, surface_destroy);
	tessa_preview_source_destroy(&source->base);
}

void tessa_preview_source_destroy(struct wlr_ext_image_capture_source_v1 *base) {
	if (base == NULL) {
		return;
	}
	struct tessa_preview_source *source = wl_container_of(base, source, base);
	if (!source->alive) {
		return;
	}
	source->alive = false;
	wlr_ext_image_capture_source_v1_finish(base);

	wl_list_remove(&source->surface_destroy.link);
	wl_list_remove(&source->output_frame.link);
	wlr_scene_output_destroy(source->scene_output);
	wlr_output_finish(&source->output);
	wlr_backend_finish(&source->backend);
	wlr_scene_node_destroy(&source->scene->tree.node);
	if (source->on_destroy != NULL) {
		source->on_destroy(source->userdata);
	}
	free(source);
}

struct wlr_ext_image_capture_source_v1 *tessa_preview_source_create(
		struct wlr_surface *surface, int max_dim,
		struct wl_event_loop *event_loop, struct wlr_allocator *allocator,
		struct wlr_renderer *renderer,
		void (*on_destroy)(void *userdata), void *userdata) {
	if (surface == NULL) {
		return NULL;
	}
	struct tessa_preview_source *source = calloc(1, sizeof(*source));
	if (source == NULL) {
		return NULL;
	}
	source->surface = surface;
	source->max_dim = max_dim > 64 ? max_dim : 64;
	source->on_destroy = on_destroy;
	source->userdata = userdata;
	source->alive = true;
	wlr_ext_image_capture_source_v1_init(&source->base, &source_impl);

	wlr_backend_init(&source->backend, &backend_impl);
	source->backend.buffer_caps = WLR_BUFFER_CAP_DMABUF | WLR_BUFFER_CAP_SHM;
	wlr_output_init(&source->output, &source->backend, &output_impl, event_loop, NULL);
	wlr_output_set_name(&source->output, "TESSA-PREVIEW");
	wlr_output_init_render(&source->output, allocator, renderer);

	source->scene = wlr_scene_create();
	if (source->scene == NULL) {
		wlr_ext_image_capture_source_v1_finish(&source->base);
		wlr_output_finish(&source->output);
		wlr_backend_finish(&source->backend);
		free(source);
		return NULL;
	}
	source->clone = wlr_scene_subsurface_tree_create(&source->scene->tree, surface);
	if (source->clone == NULL) {
		wlr_ext_image_capture_source_v1_finish(&source->base);
		wlr_output_finish(&source->output);
		wlr_backend_finish(&source->backend);
		wlr_scene_node_destroy(&source->scene->tree.node);
		free(source);
		return NULL;
	}
	source->scene_output = wlr_scene_output_create(source->scene, &source->output);
	if (source->scene_output == NULL) {
		wlr_ext_image_capture_source_v1_finish(&source->base);
		wlr_output_finish(&source->output);
		wlr_backend_finish(&source->backend);
		wlr_scene_node_destroy(&source->scene->tree.node);
		free(source);
		return NULL;
	}

	source->surface_destroy.notify = source_handle_surface_destroy;
	wl_signal_add(&surface->events.destroy, &source->surface_destroy);
	source->output_frame.notify = source_handle_output_frame;
	wl_signal_add(&source->output.events.frame, &source->output_frame);

	return &source->base;
}
