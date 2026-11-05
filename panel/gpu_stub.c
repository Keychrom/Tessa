#include "gpu.h"

#include <stddef.h>

/* Built with -Dgpu=false: keep the panel free of EGL/GLES dependencies. */

TessaGpu *tessa_gpu_create(struct wl_display *display) {
    (void)display;
    return NULL;
}

void tessa_gpu_destroy(TessaGpu *gpu) {
    (void)gpu;
}

int tessa_gpu_ready(const TessaGpu *gpu) {
    (void)gpu;
    return 0;
}

const char *tessa_gpu_error(const TessaGpu *gpu) {
    (void)gpu;
    return "GPU backend disabled at build time";
}

TessaGpuSurface *tessa_gpu_surface_create(
    TessaGpu *gpu,
    struct wl_surface *surface,
    int width,
    int height) {
    (void)gpu;
    (void)surface;
    (void)width;
    (void)height;
    return NULL;
}

int tessa_gpu_surface_resize(TessaGpuSurface *surface, int width, int height) {
    (void)surface;
    (void)width;
    (void)height;
    return 0;
}

void tessa_gpu_surface_destroy(TessaGpuSurface *surface) {
    (void)surface;
}

int tessa_gpu_set_base(
    TessaGpuSurface *surface,
    const unsigned char *argb_pixels,
    int width,
    int height,
    int stride) {
    (void)surface;
    (void)argb_pixels;
    (void)width;
    (void)height;
    (void)stride;
    return 0;
}

int tessa_gpu_set_mark(
    TessaGpuSurface *surface,
    const unsigned char *argb_pixels,
    int width,
    int height,
    int stride) {
    (void)surface;
    (void)argb_pixels;
    (void)width;
    (void)height;
    (void)stride;
    return 0;
}

void tessa_gpu_clear_mark(TessaGpuSurface *surface) {
    (void)surface;
}

int tessa_gpu_draw(TessaGpuSurface *surface, const TessaGpuParams *params) {
    (void)surface;
    (void)params;
    return 0;
}

int tessa_gpu_draw_overlay(TessaGpuSurface *surface, const TessaGpuOverlayParams *params) {
    (void)surface;
    (void)params;
    return 0;
}
