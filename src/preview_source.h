#ifndef TESSA_PREVIEW_SOURCE_H
#define TESSA_PREVIEW_SOURCE_H

#include <wlr/types/wlr_ext_image_capture_source_v1.h>
#include <wlr/types/wlr_scene.h>

struct wlr_allocator;
struct wlr_renderer;
struct wl_event_loop;

/*
 * Create a capture source for one toplevel surface. The source renders the
 * surface (including subsurfaces) into a private scene at no more than
 * max_dim pixels on the longest edge, so 4K and fractional-scale windows do
 * not have to be read back at full resolution.
 */
struct wlr_ext_image_capture_source_v1 *tessa_preview_source_create(
    struct wlr_surface *surface, int max_dim,
    struct wl_event_loop *event_loop, struct wlr_allocator *allocator,
    struct wlr_renderer *renderer,
    void (*on_destroy)(void *userdata), void *userdata);

void tessa_preview_source_destroy(struct wlr_ext_image_capture_source_v1 *source);

#endif
