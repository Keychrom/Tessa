#ifndef TESSA_GPU_H
#define TESSA_GPU_H

/*
 * Optional EGL/GLES2 background renderer for tessa-panel.
 *
 * Cairo still owns the pixels: the panel renders the wallpaper into an ARGB
 * image and uploads it here. This layer only presents that texture and adds
 * the animated water/ink post-process.
 */

struct wl_display;
struct wl_surface;

typedef struct TessaGpu TessaGpu;
typedef struct TessaGpuSurface TessaGpuSurface;

TessaGpu *tessa_gpu_create(struct wl_display *display);
void tessa_gpu_destroy(TessaGpu *gpu);
int tessa_gpu_ready(const TessaGpu *gpu);
const char *tessa_gpu_error(const TessaGpu *gpu);

TessaGpuSurface *tessa_gpu_surface_create(
    TessaGpu *gpu,
    struct wl_surface *surface,
    int width,
    int height);
int tessa_gpu_surface_resize(TessaGpuSurface *surface, int width, int height);
void tessa_gpu_surface_destroy(TessaGpuSurface *surface);

/* ARGB32 pixels as produced by Cairo (premultiplied, native endian). */
int tessa_gpu_set_base(
    TessaGpuSurface *surface,
    const unsigned char *argb_pixels,
    int width,
    int height,
    int stride);
int tessa_gpu_draw(TessaGpuSurface *surface, float time, int animate);

#endif
