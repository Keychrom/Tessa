#ifndef TESSA_WINDOW_SHADER_H
#define TESSA_WINDOW_SHADER_H

/*
 * Offscreen GLES2 effects for individual toplevels.
 *
 * Each active window owns an effect texture. The texture is produced in a
 * private EGL context (surfaceless) from the client's DMA-BUF or shared-memory
 * content, then handed to the scene as a wlroots buffer. The compositor's
 * scenefx/GLES2 context is never modified: the previous EGL context is
 * restored around every operation.
 *
 * This is deliberately independent of scenefx so the plain wlroots build can
 * use the same effects.
 */

#include <stddef.h>
#include <stdint.h>

struct wlr_buffer;
struct wlr_dmabuf_attributes;

typedef struct TessaWindowShader TessaWindowShader;

/* effect ids match tessa/types.zig WindowShader (1=mono, 2=crt, 3=vignette,
 * 4=pixelate, 5=wave). */
TessaWindowShader *tessa_window_shader_create(int drm_fd);
void tessa_window_shader_destroy(TessaWindowShader *shader);
int tessa_window_shader_ready(const TessaWindowShader *shader);
const char *tessa_window_shader_error(const TessaWindowShader *shader);
const char *tessa_window_shader_info(const TessaWindowShader *shader);

/*
 * Render one window buffer. Returns 1 on success and hands back a malloc'd
 * top-down RGBA buffer in *out_pixels, which the caller must free (or pass to
 * tessa_window_shader_buffer()).
 */
int tessa_window_shader_render_dmabuf(
    TessaWindowShader *shader,
    int effect,
    float strength,
    float param,
    const struct wlr_dmabuf_attributes *attribs,
    unsigned char **out_pixels,
    int *out_width,
    int *out_height);

int tessa_window_shader_render_pixels(
    TessaWindowShader *shader,
    int effect,
    float strength,
    float param,
    const unsigned char *pixels,
    uint32_t drm_format,
    int width,
    int height,
    size_t stride,
    unsigned char **out_pixels,
    int *out_width,
    int *out_height);

/* Wrap top-down RGBA pixels as a read-only wlroots buffer. Takes ownership. */
struct wlr_buffer *tessa_window_shader_buffer(unsigned char *pixels, int width, int height);

#endif
