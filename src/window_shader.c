#define WLR_USE_UNSTABLE 1
#define EGL_EGLEXT_PROTOTYPES 1
#define GL_GLEXT_PROTOTYPES 1
#include "window_shader.h"

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <drm_fourcc.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <wlr/interfaces/wlr_buffer.h>
#include <wlr/render/dmabuf.h>
#include <wlr/types/wlr_buffer.h>

#ifndef EGL_PLATFORM_SURFACELESS_MESA
#define EGL_PLATFORM_SURFACELESS_MESA 0x31DD
#endif

struct TessaWindowShader {
    EGLDisplay display;
    EGLContext context;
    EGLSurface surface;
    EGLConfig config;
    int drm_fd;
    int ready;
    int has_dmabuf_import;
    int has_modifiers;
    int has_egl_image;
    int egl_major;
    int egl_minor;
    PFNEGLCREATEIMAGEKHRPROC create_image;
    PFNEGLDESTROYIMAGEKHRPROC destroy_image;
    PFNGLEGLIMAGETARGETTEXTURE2DOESPROC image_target_texture;
    char error[256];
    char info[320];

    GLuint fbo;
    GLuint out_tex;
    int fbo_w;
    int fbo_h;
    GLuint programs[6];
};

static void set_error(TessaWindowShader *s, const char *fmt, ...) {
    if (s == NULL) return;
    va_list args;
    va_start(args, fmt);
    vsnprintf(s->error, sizeof(s->error), fmt, args);
    va_end(args);
}

static int has_extension(const char *haystack, const char *needle) {
    if (haystack == NULL || needle == NULL) return 0;
    return strstr(haystack, needle) != NULL;
}

static void clear_gl_errors(void) {
    while (glGetError() != GL_NO_ERROR) {
    }
}

/* ---------------------------------------------------------------- shaders */

static const char *vertex_src =
    "attribute vec2 a_pos;\n"
    "varying vec2 v_uv;\n"
    "void main() {\n"
    "    v_uv = vec2(a_pos.x * 0.5 + 0.5, 0.5 - a_pos.y * 0.5);\n"
    "    gl_Position = vec4(a_pos, 0.0, 1.0);\n"
    "}\n";

static const char *fragment_header =
    "#ifdef GL_FRAGMENT_PRECISION_HIGH\n"
    "precision highp float;\n"
    "#else\n"
    "precision mediump float;\n"
    "#endif\n"
    "varying vec2 v_uv;\n"
    "uniform sampler2D u_tex;\n"
    "uniform float u_strength;\n"
    "uniform float u_param;\n"
    "uniform vec2 u_size;\n";

static const char *fragment_mono =
    "void main() {\n"
    "    vec4 c = texture2D(u_tex, v_uv);\n"
    "    float l = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));\n"
    "    gl_FragColor = vec4(mix(c.rgb, vec3(l), u_strength), c.a);\n"
    "}\n";

static const char *fragment_vignette =
    "void main() {\n"
    "    vec4 c = texture2D(u_tex, v_uv);\n"
    "    vec2 p = v_uv * 2.0 - 1.0;\n"
    "    float d = length(p * vec2(1.0, 1.12));\n"
    "    float v = smoothstep(1.30, 0.28, d);\n"
    "    v = mix(1.0, v, u_strength);\n"
    "    gl_FragColor = vec4(c.rgb * v, c.a);\n"
    "}\n";

static const char *fragment_pixelate =
    "void main() {\n"
    "    vec4 c = texture2D(u_tex, v_uv);\n"
    "    vec2 block = vec2(max(1.0, u_param));\n"
    "    vec2 uv2 = (floor(v_uv * u_size / block) + 0.5) * block / u_size;\n"
    "    vec4 c2 = texture2D(u_tex, clamp(uv2, vec2(0.0), vec2(1.0)));\n"
    "    gl_FragColor = mix(c, c2, u_strength);\n"
    "}\n";

static const char *fragment_wave =
    "void main() {\n"
    "    vec2 uv = v_uv;\n"
    "    uv.x += sin(v_uv.y * 18.0 + 0.7) * 0.008 * u_strength;\n"
    "    uv.y += sin(v_uv.x * 22.0 + 1.3) * 0.004 * u_strength;\n"
    "    gl_FragColor = texture2D(u_tex, clamp(uv, vec2(0.0), vec2(1.0)));\n"
    "}\n";

static const char *fragment_crt =
    "void main() {\n"
    "    vec2 p = v_uv * 2.0 - 1.0;\n"
    "    float r2 = dot(p, p);\n"
    "    vec2 uv = (p * (1.0 + 0.035 * u_strength * r2)) * 0.5 + 0.5;\n"
    "    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {\n"
    "        gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);\n"
    "        return;\n"
    "    }\n"
    "    float ca = (1.0 / max(1.0, u_size.x)) * u_strength * 1.4;\n"
    "    vec4 cr = texture2D(u_tex, clamp(uv + vec2(ca, 0.0), vec2(0.0), vec2(1.0)));\n"
    "    vec4 cg = texture2D(u_tex, uv);\n"
    "    vec4 cb = texture2D(u_tex, clamp(uv - vec2(ca, 0.0), vec2(0.0), vec2(1.0)));\n"
    "    vec3 col = vec3(cr.r, cg.g, cb.b);\n"
    "    float scan = 0.5 + 0.5 * sin(uv.y * u_size.y * 1.6);\n"
    "    col *= mix(1.0, 0.72 + 0.28 * scan, u_strength);\n"
    "    float vig = smoothstep(1.35, 0.45, length(p));\n"
    "    col *= mix(1.0, vig, u_strength);\n"
    "    gl_FragColor = vec4(col, cg.a);\n"
    "}\n";

static GLuint compile_shader(TessaWindowShader *s, GLenum type, const char *body) {
    GLuint shader = glCreateShader(type);
    const char *parts[2];
    int count = 0;
    if (type == GL_FRAGMENT_SHADER) parts[count++] = fragment_header;
    parts[count++] = body;
    glShaderSource(shader, count, parts, NULL);
    glCompileShader(shader);
    GLint ok = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[512];
        GLsizei len = 0;
        glGetShaderInfoLog(shader, sizeof(log), &len, log);
        set_error(s, "shader compile failed: %s", len > 0 ? log : "unknown error");
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

static GLuint build_program(TessaWindowShader *s, const char *body) {
    GLuint vs = compile_shader(s, GL_VERTEX_SHADER, vertex_src);
    if (vs == 0) return 0;
    GLuint fs = compile_shader(s, GL_FRAGMENT_SHADER, body);
    if (fs == 0) {
        glDeleteShader(vs);
        return 0;
    }
    GLuint program = glCreateProgram();
    glAttachShader(program, vs);
    glAttachShader(program, fs);
    glBindAttribLocation(program, 0, "a_pos");
    glLinkProgram(program);
    glDeleteShader(vs);
    glDeleteShader(fs);
    GLint ok = 0;
    glGetProgramiv(program, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[512];
        GLsizei len = 0;
        glGetProgramInfoLog(program, sizeof(log), &len, log);
        set_error(s, "shader link failed: %s", len > 0 ? log : "unknown error");
        glDeleteProgram(program);
        return 0;
    }
    return program;
}

static GLuint program_for(TessaWindowShader *s, int effect) {
    if (effect < 1 || effect > 5) return 0;
    if (s->programs[effect] != 0) return s->programs[effect];
    const char *body = NULL;
    switch (effect) {
    case 1: body = fragment_mono; break;
    case 2: body = fragment_crt; break;
    case 3: body = fragment_vignette; break;
    case 4: body = fragment_pixelate; break;
    case 5: body = fragment_wave; break;
    default: return 0;
    }
    s->programs[effect] = build_program(s, body);
    return s->programs[effect];
}

/* ------------------------------------------------------------------- EGL */

static int egl_current(TessaWindowShader *s) {
    EGLSurface surface = s->surface;
    if (!eglMakeCurrent(s->display, surface, surface, s->context)) {
        set_error(s, "eglMakeCurrent failed (0x%x)", eglGetError());
        return 0;
    }
    return 1;
}

static int egl_init(TessaWindowShader *s) {
    PFNEGLGETPLATFORMDISPLAYEXTPROC get_platform_display =
        (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
    EGLDisplay display = EGL_NO_DISPLAY;
    if (get_platform_display != NULL) {
        display = get_platform_display(
            EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
    }
    if (display == EGL_NO_DISPLAY) {
        display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    }
    if (display == EGL_NO_DISPLAY) {
        set_error(s, "no EGL display");
        return 0;
    }
    if (!eglInitialize(display, &s->egl_major, &s->egl_minor)) {
        set_error(s, "eglInitialize failed (0x%x)", eglGetError());
        return 0;
    }
    s->display = display;
    if (!eglBindAPI(EGL_OPENGL_ES_API)) {
        set_error(s, "eglBindAPI(ES) failed (0x%x)", eglGetError());
        return 0;
    }

    const char *egl_ext = eglQueryString(display, EGL_EXTENSIONS);
    s->has_dmabuf_import = has_extension(egl_ext, "EGL_EXT_image_dma_buf_import");
    s->has_modifiers = has_extension(egl_ext, "EGL_EXT_image_dma_buf_import_modifiers");

    EGLint config_attrs[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_NONE,
    };
    EGLint count = 0;
    if (!eglChooseConfig(display, config_attrs, &s->config, 1, &count) || count == 0) {
        EGLint fallback_attrs[] = {
            EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
            EGL_NONE,
        };
        if (!eglChooseConfig(display, fallback_attrs, &s->config, 1, &count) || count == 0) {
            set_error(s, "no GLES2 EGL config");
            return 0;
        }
    }

    EGLint context_attrs[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    s->context = eglCreateContext(display, s->config, EGL_NO_CONTEXT, context_attrs);
    if (s->context == EGL_NO_CONTEXT) {
        set_error(s, "eglCreateContext failed (0x%x)", eglGetError());
        return 0;
    }
    s->surface = EGL_NO_SURFACE;
    if (!eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, s->context)) {
        EGLint pbuffer_attrs[] = { EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE };
        s->surface = eglCreatePbufferSurface(display, s->config, pbuffer_attrs);
        if (s->surface == EGL_NO_SURFACE ||
            !eglMakeCurrent(display, s->surface, s->surface, s->context)) {
            set_error(s, "cannot make the shader context current (0x%x)", eglGetError());
            return 0;
        }
    }

    const char *gl_ext = (const char *)glGetString(GL_EXTENSIONS);
    s->has_egl_image = has_extension(gl_ext, "GL_OES_EGL_image");
    s->create_image = (PFNEGLCREATEIMAGEKHRPROC)eglGetProcAddress("eglCreateImageKHR");
    s->destroy_image = (PFNEGLDESTROYIMAGEKHRPROC)eglGetProcAddress("eglDestroyImageKHR");
    s->image_target_texture = (PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)
        eglGetProcAddress("glEGLImageTargetTexture2DOES");
    if (s->create_image == NULL || s->destroy_image == NULL ||
        s->image_target_texture == NULL) {
        s->has_egl_image = 0;
    }
    const char *version = (const char *)glGetString(GL_VERSION);
    const char *renderer = (const char *)glGetString(GL_RENDERER);
    snprintf(s->info, sizeof(s->info), "EGL %d.%d / %s / %s", s->egl_major,
             s->egl_minor, version != NULL ? version : "unknown GL",
             renderer != NULL ? renderer : "unknown renderer");
    if (!s->has_dmabuf_import) {
        /* Shared-memory content can still use the pixel upload path. */
        set_error(s, "EGL_EXT_image_dma_buf_import unavailable");
    }
    return 1;
}

/* ------------------------------------------------------------- rendering */

static int ensure_target(TessaWindowShader *s, int width, int height) {
    if (width <= 0 || height <= 0 || width > 16384 || height > 16384) return 0;
    if (s->fbo != 0 && s->fbo_w == width && s->fbo_h == height) return 1;
    if (s->out_tex != 0) {
        glDeleteTextures(1, &s->out_tex);
        s->out_tex = 0;
    }
    if (s->fbo != 0) {
        glDeleteFramebuffers(1, &s->fbo);
        s->fbo = 0;
    }
    glGenTextures(1, &s->out_tex);
    glBindTexture(GL_TEXTURE_2D, s->out_tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glGenFramebuffers(1, &s->fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, s->fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                           s->out_tex, 0);
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        set_error(s, "framebuffer incomplete (0x%x)", status);
        return 0;
    }
    s->fbo_w = width;
    s->fbo_h = height;
    return 1;
}

static void flip_rows(unsigned char *pixels, int width, int height) {
    const size_t stride = (size_t)width * 4;
    unsigned char *tmp = malloc(stride);
    if (tmp == NULL) return;
    for (int y = 0; y < height / 2; y++) {
        unsigned char *a = pixels + (size_t)y * stride;
        unsigned char *b = pixels + (size_t)(height - 1 - y) * stride;
        memcpy(tmp, a, stride);
        memcpy(a, b, stride);
        memcpy(b, tmp, stride);
    }
    free(tmp);
}

static int draw_and_read(TessaWindowShader *s, GLuint texture, int effect,
                         float strength, float param, int width, int height,
                         unsigned char **out_pixels, int *out_width,
                         int *out_height) {
    GLuint program = program_for(s, effect);
    if (program == 0) return 0;
    glBindFramebuffer(GL_FRAMEBUFFER, s->fbo);
    glViewport(0, 0, width, height);
    glDisable(GL_BLEND);
    glDisable(GL_DEPTH_TEST);
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    glUseProgram(program);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glUniform1i(glGetUniformLocation(program, "u_tex"), 0);
    glUniform1f(glGetUniformLocation(program, "u_strength"), strength);
    glUniform1f(glGetUniformLocation(program, "u_param"), param);
    glUniform2f(glGetUniformLocation(program, "u_size"), (float)width, (float)height);

    static const float verts[] = { -1.0f, -1.0f, 3.0f, -1.0f, -1.0f, 3.0f };
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, verts);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glDisableVertexAttribArray(0);

    unsigned char *pixels = malloc((size_t)width * (size_t)height * 4);
    if (pixels == NULL) {
        set_error(s, "out of memory for shader output");
        return 0;
    }
    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    GLenum err = glGetError();
    if (err != GL_NO_ERROR) {
        set_error(s, "GL error 0x%x during shader readback", err);
        free(pixels);
        return 0;
    }
    flip_rows(pixels, width, height);
    *out_pixels = pixels;
    *out_width = width;
    *out_height = height;
    return 1;
}

int tessa_window_shader_render_dmabuf(
    TessaWindowShader *s,
    int effect,
    float strength,
    float param,
    const struct wlr_dmabuf_attributes *attribs,
    unsigned char **out_pixels,
    int *out_width,
    int *out_height) {
    if (s == NULL || !s->ready || attribs == NULL || out_pixels == NULL) return 0;
    if (!s->has_dmabuf_import || !s->has_egl_image) return 0;
    if (attribs->n_planes != 1 || attribs->width <= 0 || attribs->height <= 0) return 0;

    EGLDisplay prev_display = eglGetCurrentDisplay();
    EGLContext prev_context = eglGetCurrentContext();
    EGLSurface prev_draw = eglGetCurrentSurface(EGL_DRAW);
    EGLSurface prev_read = eglGetCurrentSurface(EGL_READ);
    if (!egl_current(s)) return 0;
    clear_gl_errors();
    int ok = 0;
    GLuint texture = 0;
    EGLImageKHR image = EGL_NO_IMAGE_KHR;

    if (!ensure_target(s, attribs->width, attribs->height)) goto out;

    EGLint attrs[40];
    int n = 0;
    attrs[n++] = EGL_WIDTH;
    attrs[n++] = attribs->width;
    attrs[n++] = EGL_HEIGHT;
    attrs[n++] = attribs->height;
    attrs[n++] = EGL_LINUX_DRM_FOURCC_EXT;
    attrs[n++] = (EGLint)attribs->format;
    attrs[n++] = EGL_DMA_BUF_PLANE0_FD_EXT;
    attrs[n++] = attribs->fd[0];
    attrs[n++] = EGL_DMA_BUF_PLANE0_OFFSET_EXT;
    attrs[n++] = (EGLint)attribs->offset[0];
    attrs[n++] = EGL_DMA_BUF_PLANE0_PITCH_EXT;
    attrs[n++] = (EGLint)attribs->stride[0];
    if (s->has_modifiers && attribs->modifier != DRM_FORMAT_MOD_INVALID) {
        attrs[n++] = EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT;
        attrs[n++] = (EGLint)(attribs->modifier & 0xffffffffu);
        attrs[n++] = EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT;
        attrs[n++] = (EGLint)(attribs->modifier >> 32);
    }
    attrs[n++] = EGL_NONE;

    image = s->create_image(s->display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT,
                            NULL, attrs);
    if (image == EGL_NO_IMAGE_KHR) {
        set_error(s, "cannot import DMA-BUF (format=0x%x, err=0x%x)",
                  attribs->format, eglGetError());
        goto out;
    }
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    s->image_target_texture(GL_TEXTURE_2D, (GLeglImageOES)image);
    GLenum bind_err = glGetError();
    if (bind_err != GL_NO_ERROR) {
        set_error(s, "cannot bind DMA-BUF image (0x%x)", bind_err);
        goto out;
    }
    ok = draw_and_read(s, texture, effect, strength, param, attribs->width,
                       attribs->height, out_pixels, out_width, out_height);

out:
    if (texture != 0) glDeleteTextures(1, &texture);
    if (image != EGL_NO_IMAGE_KHR) s->destroy_image(s->display, image);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glBindTexture(GL_TEXTURE_2D, 0);
    if (prev_context != EGL_NO_CONTEXT) {
        eglMakeCurrent(prev_display, prev_draw, prev_read, prev_context);
    } else {
        eglMakeCurrent(s->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    }
    return ok;
}

int tessa_window_shader_render_pixels(
    TessaWindowShader *s,
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
    int *out_height) {
    if (s == NULL || !s->ready || pixels == NULL || out_pixels == NULL) return 0;
    if (width <= 0 || height <= 0 || stride < (size_t)width * 4) return 0;

    unsigned char *rgba = malloc((size_t)width * (size_t)height * 4);
    if (rgba == NULL) return 0;
    int direct = drm_format == DRM_FORMAT_ABGR8888;
    int bgr = drm_format == DRM_FORMAT_ARGB8888 ||
              drm_format == DRM_FORMAT_XRGB8888;
    int bgr_x = drm_format == DRM_FORMAT_XBGR8888;
    if (!direct && !bgr && !bgr_x) {
        free(rgba);
        return 0;
    }
    for (int y = 0; y < height; y++) {
        const unsigned char *src = pixels + (size_t)y * stride;
        unsigned char *dst = rgba + (size_t)y * (size_t)width * 4;
        for (int x = 0; x < width; x++) {
            if (direct) {
                dst[x * 4 + 0] = src[x * 4 + 0];
                dst[x * 4 + 1] = src[x * 4 + 1];
                dst[x * 4 + 2] = src[x * 4 + 2];
                dst[x * 4 + 3] = src[x * 4 + 3];
            } else if (bgr) {
                dst[x * 4 + 0] = src[x * 4 + 2];
                dst[x * 4 + 1] = src[x * 4 + 1];
                dst[x * 4 + 2] = src[x * 4 + 0];
                dst[x * 4 + 3] = drm_format == DRM_FORMAT_XRGB8888
                                     ? 255
                                     : src[x * 4 + 3];
            } else {
                dst[x * 4 + 0] = src[x * 4 + 0];
                dst[x * 4 + 1] = src[x * 4 + 1];
                dst[x * 4 + 2] = src[x * 4 + 2];
                dst[x * 4 + 3] = 255;
            }
        }
    }

    EGLDisplay prev_display = eglGetCurrentDisplay();
    EGLContext prev_context = eglGetCurrentContext();
    EGLSurface prev_draw = eglGetCurrentSurface(EGL_DRAW);
    EGLSurface prev_read = eglGetCurrentSurface(EGL_READ);
    if (!egl_current(s)) {
        free(rgba);
        return 0;
    }
    clear_gl_errors();
    int ok = 0;
    GLuint texture = 0;
    if (!ensure_target(s, width, height)) goto out;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, rgba);
    ok = draw_and_read(s, texture, effect, strength, param, width, height,
                       out_pixels, out_width, out_height);

out:
    if (texture != 0) glDeleteTextures(1, &texture);
    free(rgba);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glBindTexture(GL_TEXTURE_2D, 0);
    if (prev_context != EGL_NO_CONTEXT) {
        eglMakeCurrent(prev_display, prev_draw, prev_read, prev_context);
    } else {
        eglMakeCurrent(s->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    }
    return ok;
}

/* --------------------------------------------------------- pixel buffer */

struct TessaPixelBuffer {
    struct wlr_buffer base;
    unsigned char *pixels;
};

static void pixel_buffer_destroy(struct wlr_buffer *buffer) {
    struct TessaPixelBuffer *p = (struct TessaPixelBuffer *)buffer;
    wlr_buffer_finish(buffer);
    free(p->pixels);
    free(p);
}

static bool pixel_buffer_begin_access(struct wlr_buffer *buffer, uint32_t flags,
                                      void **data, uint32_t *format,
                                      size_t *stride) {
    if ((flags & WLR_BUFFER_DATA_PTR_ACCESS_READ) == 0) return false;
    struct TessaPixelBuffer *p = (struct TessaPixelBuffer *)buffer;
    *data = p->pixels;
    *format = DRM_FORMAT_ABGR8888;
    *stride = (size_t)buffer->width * 4;
    return true;
}

static void pixel_buffer_end_access(struct wlr_buffer *buffer) {
    (void)buffer;
}

static const struct wlr_buffer_impl pixel_buffer_impl = {
    .destroy = pixel_buffer_destroy,
    .get_dmabuf = NULL,
    .get_shm = NULL,
    .begin_data_ptr_access = pixel_buffer_begin_access,
    .end_data_ptr_access = pixel_buffer_end_access,
};

struct wlr_buffer *tessa_window_shader_buffer(unsigned char *pixels, int width, int height) {
    if (pixels == NULL || width <= 0 || height <= 0) return NULL;
    struct TessaPixelBuffer *p = calloc(1, sizeof(*p));
    if (p == NULL) {
        free(pixels);
        return NULL;
    }
    p->pixels = pixels;
    wlr_buffer_init(&p->base, &pixel_buffer_impl, width, height);
    return &p->base;
}

/* ------------------------------------------------------------- lifecycle */

TessaWindowShader *tessa_window_shader_create(int drm_fd) {
    TessaWindowShader *s = calloc(1, sizeof(*s));
    if (s == NULL) return NULL;
    s->drm_fd = drm_fd;
    if (!egl_init(s)) {
        s->ready = 0;
        return s;
    }
    s->ready = 1;
    return s;
}

void tessa_window_shader_destroy(TessaWindowShader *s) {
    if (s == NULL) return;
    if (s->display != EGL_NO_DISPLAY) {
        eglMakeCurrent(s->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        for (int i = 0; i < 6; i++) {
            if (s->programs[i] != 0) glDeleteProgram(s->programs[i]);
        }
        if (s->out_tex != 0) glDeleteTextures(1, &s->out_tex);
        if (s->fbo != 0) glDeleteFramebuffers(1, &s->fbo);
        if (s->surface != EGL_NO_SURFACE) eglDestroySurface(s->display, s->surface);
        if (s->context != EGL_NO_CONTEXT) eglDestroyContext(s->display, s->context);
        eglTerminate(s->display);
    }
    free(s);
}

int tessa_window_shader_ready(const TessaWindowShader *s) {
    return s != NULL && s->ready;
}

const char *tessa_window_shader_error(const TessaWindowShader *s) {
    if (s == NULL) return "no shader context";
    return s->error[0] != 0 ? s->error : "unknown error";
}

const char *tessa_window_shader_info(const TessaWindowShader *s) {
    if (s == NULL) return "unavailable";
    return s->info[0] != 0 ? s->info : "unavailable";
}
