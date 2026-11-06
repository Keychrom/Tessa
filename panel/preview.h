#ifndef TESSA_PANEL_PREVIEW_H
#define TESSA_PANEL_PREVIEW_H

#include <stdint.h>

struct wl_display;
struct wl_shm;
struct ext_foreign_toplevel_list_v1;
struct ext_foreign_toplevel_image_capture_source_manager_v1;
struct ext_image_copy_capture_manager_v1;

typedef void (*tessa_preview_frame_cb)(uint64_t client_id, const void *data,
    uint32_t width, uint32_t height, uint32_t stride, uint32_t format,
    void *userdata);
typedef void (*tessa_preview_gone_cb)(uint64_t client_id, void *userdata);

void tessa_preview_init(struct wl_display *display, struct wl_shm *shm,
    struct ext_foreign_toplevel_list_v1 *list,
    struct ext_foreign_toplevel_image_capture_source_manager_v1 *source_mgr,
    struct ext_image_copy_capture_manager_v1 *capture_mgr,
    tessa_preview_frame_cb frame_cb, tessa_preview_gone_cb gone_cb,
    void *userdata);

int tessa_preview_available(void);
int tessa_preview_start(uint64_t client_id, const char *identifier);
void tessa_preview_stop(uint64_t client_id);
void tessa_preview_stop_all(void);

#endif
