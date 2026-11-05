#ifndef TESSA_GPU_H
#define TESSA_GPU_H

/*
 * Optional EGL/GLES2 background renderer for tessa-panel.
 *
 * The panel can either upload a Cairo-rendered wallpaper as a texture or ask
 * the shader to generate the Vermilion Ink background procedurally. Both paths
 * share the same animated water/ink post-process and the small corner mark.
 */

struct wl_display;
struct wl_surface;

typedef struct TessaGpu TessaGpu;
typedef struct TessaGpuSurface TessaGpuSurface;

typedef struct {
    float top[3];
    float bottom[3];
    float accent[3];
    float bg[3];
    float art;
    float prev_top[3];
    float prev_bottom[3];
    float prev_accent[3];
    float prev_art;
    float fade;
    float time;
    int animate;
    int procedural;
} TessaGpuParams;

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
int tessa_gpu_set_mark(
    TessaGpuSurface *surface,
    const unsigned char *argb_pixels,
    int width,
    int height,
    int stride);
void tessa_gpu_clear_mark(TessaGpuSurface *surface);

int tessa_gpu_draw(TessaGpuSurface *surface, const TessaGpuParams *params);

#endif
