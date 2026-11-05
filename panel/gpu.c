#define _GNU_SOURCE 1
#define EGL_EGLEXT_PROTOTYPES 1

#include "gpu.h"

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <wayland-egl.h>

#include <math.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef EGL_PLATFORM_WAYLAND_KHR
#define EGL_PLATFORM_WAYLAND_KHR 0x31D8
#endif

typedef EGLDisplay (*TessaGetPlatformDisplayProc)(
    EGLenum platform,
    void *native_display,
    const EGLint *attrib_list);

struct TessaGpu {
    EGLDisplay display;
    EGLContext context;
    EGLConfig config;
    GLuint program;
    GLuint vbo;
    GLint attr_pos;
    GLint uniform_tex;
    GLint uniform_res;
    GLint uniform_time;
    GLint uniform_animate;
    int ready;
    char error[256];
};

struct TessaGpuSurface {
    TessaGpu *gpu;
    struct wl_egl_window *window;
    EGLSurface egl_surface;
    GLuint texture;
    int width;
    int height;
};

static const char *VERTEX_SHADER =
    "#version 100\n"
    "attribute vec2 a_pos;\n"
    "varying vec2 v_uv;\n"
    "void main() {\n"
    "    v_uv = vec2(a_pos.x * 0.5 + 0.5, 0.5 - a_pos.y * 0.5);\n"
    "    gl_Position = vec4(a_pos, 0.0, 1.0);\n"
    "}\n";

/*
 * The Cairo base already carries the real Vermilion Ink wallpaper. The shader
 * only adds restrained motion: ripples near the water line, a slow drift over
 * the ink, and a faint pulse around the sun.
 */
static const char *FRAGMENT_SHADER =
    "#version 100\n"
    "#ifdef GL_FRAGMENT_PRECISION_HIGH\n"
    "precision highp float;\n"
    "#else\n"
    "precision mediump float;\n"
    "#endif\n"
    "varying vec2 v_uv;\n"
    "uniform sampler2D u_tex;\n"
    "uniform vec2 u_res;\n"
    "uniform float u_time;\n"
    "uniform float u_animate;\n"
    "float hash(vec2 p) {\n"
    "    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);\n"
    "}\n"
    "void main() {\n"
    "    vec2 uv = v_uv;\n"
    "    float t = u_time * u_animate;\n"
    "    float water = smoothstep(0.70, 0.98, uv.y);\n"
    "    vec2 q = uv;\n"
    "    q.x += sin(uv.y * 90.0 + t * 1.10) * 0.0016 * water;\n"
    "    q.y += cos(uv.x * 70.0 - t * 0.85) * 0.0010 * water;\n"
    "    q += vec2(sin(uv.y * 9.0 + t * 0.18), cos(uv.x * 8.0 - t * 0.15)) * 0.0012 * u_animate;\n"
    "    vec3 col = texture2D(u_tex, q).rgb;\n"
    "    float shimmer = smoothstep(0.994, 1.0, sin(uv.y * 260.0 + sin(uv.x * 7.0 + t * 0.7) * 2.2)) * water;\n"
    "    col += vec3(0.72, 0.80, 0.92) * shimmer * 0.020 * u_animate;\n"
    "    float sun = 1.0 - smoothstep(0.0, 0.34, distance(uv, vec2(0.79, 0.235)));\n"
    "    col += vec3(0.90, 0.34, 0.24) * sun * (0.5 + 0.5 * sin(t * 0.55)) * 0.018 * u_animate;\n"
    "    col += (hash(uv * u_res) - 0.5) * 0.006;\n"
    "    gl_FragColor = vec4(col, 1.0);\n"
    "}\n";

static void gpu_error(TessaGpu *gpu, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vsnprintf(gpu->error, sizeof(gpu->error), fmt, args);
    va_end(args);
    fprintf(stderr, "tessa-panel: gpu: %s\n", gpu->error);
}

static GLuint compile_shader(TessaGpu *gpu, GLenum type, const char *source) {
    GLuint shader = glCreateShader(type);
    if (shader == 0) {
        gpu_error(gpu, "glCreateShader failed");
        return 0;
    }
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);
    GLint ok = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[512];
        GLsizei len = 0;
        glGetShaderInfoLog(shader, sizeof(log), &len, log);
        gpu_error(gpu, "shader compile failed: %.*s", (int)len, log);
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

static int ensure_program(TessaGpu *gpu) {
    if (gpu->program != 0) return 1;

    GLuint vs = compile_shader(gpu, GL_VERTEX_SHADER, VERTEX_SHADER);
    if (vs == 0) return 0;
    GLuint fs = compile_shader(gpu, GL_FRAGMENT_SHADER, FRAGMENT_SHADER);
    if (fs == 0) {
        glDeleteShader(vs);
        return 0;
    }

    GLuint program = glCreateProgram();
    if (program == 0) {
        gpu_error(gpu, "glCreateProgram failed");
        glDeleteShader(vs);
        glDeleteShader(fs);
        return 0;
    }
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
        gpu_error(gpu, "program link failed: %.*s", (int)len, log);
        glDeleteProgram(program);
        return 0;
    }

    gpu->program = program;
    gpu->attr_pos = glGetAttribLocation(program, "a_pos");
    gpu->uniform_tex = glGetUniformLocation(program, "u_tex");
    gpu->uniform_res = glGetUniformLocation(program, "u_res");
    gpu->uniform_time = glGetUniformLocation(program, "u_time");
    gpu->uniform_animate = glGetUniformLocation(program, "u_animate");
    if (gpu->attr_pos < 0 || gpu->uniform_tex < 0 || gpu->uniform_res < 0 ||
        gpu->uniform_time < 0 || gpu->uniform_animate < 0) {
        gpu_error(gpu, "shader interface is incomplete");
        glDeleteProgram(program);
        gpu->program = 0;
        return 0;
    }

    static const GLfloat verts[] = {
        -1.0f, -1.0f,
         3.0f, -1.0f,
        -1.0f,  3.0f,
    };
    glGenBuffers(1, &gpu->vbo);
    if (gpu->vbo == 0) {
        gpu_error(gpu, "glGenBuffers failed");
        glDeleteProgram(program);
        gpu->program = 0;
        return 0;
    }
    glBindBuffer(GL_ARRAY_BUFFER, gpu->vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(verts), verts, GL_STATIC_DRAW);
    return 1;
}

static int choose_config(TessaGpu *gpu, int alpha) {
    EGLint attrs[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, alpha,
        EGL_NONE,
    };
    EGLint count = 0;
    if (!eglChooseConfig(gpu->display, attrs, &gpu->config, 1, &count) || count < 1) {
        return 0;
    }
    return 1;
}

TessaGpu *tessa_gpu_create(struct wl_display *display) {
    TessaGpu *gpu = calloc(1, sizeof(*gpu));
    if (gpu == NULL) return NULL;
    gpu->display = EGL_NO_DISPLAY;
    gpu->context = EGL_NO_CONTEXT;

    TessaGetPlatformDisplayProc get_platform =
        (TessaGetPlatformDisplayProc)eglGetProcAddress("eglGetPlatformDisplayEXT");
    if (get_platform == NULL) {
        get_platform = (TessaGetPlatformDisplayProc)eglGetProcAddress("eglGetPlatformDisplay");
    }
    if (get_platform != NULL) {
        gpu->display = get_platform(EGL_PLATFORM_WAYLAND_KHR, display, NULL);
    }
    if (gpu->display == EGL_NO_DISPLAY) {
        gpu->display = eglGetDisplay((EGLNativeDisplayType)display);
    }
    if (gpu->display == EGL_NO_DISPLAY) {
        gpu_error(gpu, "no Wayland EGL display");
        return gpu;
    }

    EGLint major = 0;
    EGLint minor = 0;
    if (!eglInitialize(gpu->display, &major, &minor)) {
        gpu_error(gpu, "eglInitialize failed (0x%x)", eglGetError());
        return gpu;
    }
    if (!eglBindAPI(EGL_OPENGL_ES_API)) {
        gpu_error(gpu, "eglBindAPI(OpenGL ES) failed (0x%x)", eglGetError());
        return gpu;
    }
    if (!choose_config(gpu, 8) && !choose_config(gpu, 0)) {
        gpu_error(gpu, "no EGL GLES2 window config (0x%x)", eglGetError());
        return gpu;
    }

    EGLint context_attrs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 2,
        EGL_NONE,
    };
    gpu->context = eglCreateContext(gpu->display, gpu->config, EGL_NO_CONTEXT, context_attrs);
    if (gpu->context == EGL_NO_CONTEXT) {
        gpu_error(gpu, "eglCreateContext failed (0x%x)", eglGetError());
        return gpu;
    }

    if (!eglSwapInterval(gpu->display, 0)) {
        /* Not fatal; some drivers ignore the request. */
    }
    gpu->ready = 1;
    fprintf(stderr, "tessa-panel: gpu: EGL %d.%d\n", (int)major, (int)minor);
    return gpu;
}

void tessa_gpu_destroy(TessaGpu *gpu) {
    if (gpu == NULL) return;
    if (gpu->display != EGL_NO_DISPLAY && gpu->context != EGL_NO_CONTEXT) {
        /* Best effort: some drivers require a current context for deletes. */
        if (eglMakeCurrent(gpu->display, EGL_NO_SURFACE, EGL_NO_SURFACE, gpu->context)) {
            if (gpu->program != 0) {
                glDeleteProgram(gpu->program);
                gpu->program = 0;
            }
            if (gpu->vbo != 0) {
                glDeleteBuffers(1, &gpu->vbo);
                gpu->vbo = 0;
            }
        }
        eglMakeCurrent(gpu->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    }
    if (gpu->display != EGL_NO_DISPLAY) {
        if (gpu->context != EGL_NO_CONTEXT) {
            eglDestroyContext(gpu->display, gpu->context);
            gpu->context = EGL_NO_CONTEXT;
        }
        eglTerminate(gpu->display);
        gpu->display = EGL_NO_DISPLAY;
    }
    free(gpu);
}

int tessa_gpu_ready(const TessaGpu *gpu) {
    return gpu != NULL && gpu->ready;
}

const char *tessa_gpu_error(const TessaGpu *gpu) {
    if (gpu == NULL || gpu->error[0] == '\0') return "unavailable";
    return gpu->error;
}

TessaGpuSurface *tessa_gpu_surface_create(
    TessaGpu *gpu,
    struct wl_surface *surface,
    int width,
    int height) {
    if (gpu == NULL || !gpu->ready || surface == NULL || width <= 0 || height <= 0) {
        return NULL;
    }
    TessaGpuSurface *s = calloc(1, sizeof(*s));
    if (s == NULL) return NULL;
    s->gpu = gpu;
    s->width = width;
    s->height = height;
    s->window = wl_egl_window_create(surface, width, height);
    if (s->window == NULL) {
        gpu_error(gpu, "wl_egl_window_create failed");
        free(s);
        return NULL;
    }
    s->egl_surface = eglCreateWindowSurface(
        gpu->display, gpu->config, (EGLNativeWindowType)s->window, NULL);
    if (s->egl_surface == EGL_NO_SURFACE) {
        gpu_error(gpu, "eglCreateWindowSurface failed (0x%x)", eglGetError());
        wl_egl_window_destroy(s->window);
        free(s);
        return NULL;
    }
    if (!eglMakeCurrent(gpu->display, s->egl_surface, s->egl_surface, gpu->context)) {
        gpu_error(gpu, "eglMakeCurrent failed (0x%x)", eglGetError());
        eglDestroySurface(gpu->display, s->egl_surface);
        wl_egl_window_destroy(s->window);
        free(s);
        return NULL;
    }
    if (!ensure_program(gpu)) {
        eglMakeCurrent(gpu->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        eglDestroySurface(gpu->display, s->egl_surface);
        wl_egl_window_destroy(s->window);
        free(s);
        return NULL;
    }
    const GLubyte *version = glGetString(GL_VERSION);
    const GLubyte *renderer = glGetString(GL_RENDERER);
    fprintf(stderr, "tessa-panel: gpu: %s / %s, background %dx%d\n",
            version != NULL ? (const char *)version : "unknown GL",
            renderer != NULL ? (const char *)renderer : "unknown renderer",
            width, height);
    return s;
}

int tessa_gpu_surface_resize(TessaGpuSurface *surface, int width, int height) {
    if (surface == NULL || surface->window == NULL || width <= 0 || height <= 0) return 0;
    if (surface->width == width && surface->height == height) return 1;
    wl_egl_window_resize(surface->window, width, height, 0, 0);
    surface->width = width;
    surface->height = height;
    return 1;
}

void tessa_gpu_surface_destroy(TessaGpuSurface *surface) {
    if (surface == NULL) return;
    TessaGpu *gpu = surface->gpu;
    if (gpu != NULL && gpu->display != EGL_NO_DISPLAY) {
        if (surface->egl_surface != EGL_NO_SURFACE) {
            if (eglMakeCurrent(gpu->display, surface->egl_surface, surface->egl_surface,
                               gpu->context)) {
                if (surface->texture != 0) {
                    glDeleteTextures(1, &surface->texture);
                    surface->texture = 0;
                }
            }
            eglMakeCurrent(gpu->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
            eglDestroySurface(gpu->display, surface->egl_surface);
            surface->egl_surface = EGL_NO_SURFACE;
        }
        if (surface->window != NULL) {
            wl_egl_window_destroy(surface->window);
            surface->window = NULL;
        }
    }
    free(surface);
}

int tessa_gpu_set_base(
    TessaGpuSurface *surface,
    const unsigned char *argb_pixels,
    int width,
    int height,
    int stride) {
    if (surface == NULL || surface->gpu == NULL || !surface->gpu->ready) return 0;
    if (argb_pixels == NULL || width <= 0 || height <= 0 || stride < width * 4) return 0;
    TessaGpu *gpu = surface->gpu;
    if (!eglMakeCurrent(gpu->display, surface->egl_surface, surface->egl_surface, gpu->context)) {
        gpu_error(gpu, "eglMakeCurrent failed while uploading (0x%x)", eglGetError());
        return 0;
    }

    size_t pixels = (size_t)width * (size_t)height;
    if (pixels > SIZE_MAX / 4) return 0;
    unsigned char *rgba = malloc(pixels * 4);
    if (rgba == NULL) {
        gpu_error(gpu, "out of memory uploading wallpaper");
        return 0;
    }
    for (int y = 0; y < height; y++) {
        const unsigned char *src = argb_pixels + (size_t)y * (size_t)stride;
        unsigned char *dst = rgba + (size_t)y * (size_t)width * 4;
        for (int x = 0; x < width; x++) {
            dst[0] = src[2];
            dst[1] = src[1];
            dst[2] = src[0];
            dst[3] = src[3];
            src += 4;
            dst += 4;
        }
    }

    if (surface->texture == 0) {
        glGenTextures(1, &surface->texture);
        if (surface->texture == 0) {
            gpu_error(gpu, "glGenTextures failed");
            free(rgba);
            return 0;
        }
    }
    while (glGetError() != GL_NO_ERROR) {
        /* Clear stale errors before checking the upload. */
    }
    glBindTexture(GL_TEXTURE_2D, surface->texture);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, rgba);
    free(rgba);
    GLenum err = glGetError();
    if (err != GL_NO_ERROR) {
        gpu_error(gpu, "texture upload failed (0x%x)", (unsigned int)err);
        return 0;
    }
    return 1;
}

int tessa_gpu_draw(TessaGpuSurface *surface, float time, int animate) {
    if (surface == NULL || surface->gpu == NULL || !surface->gpu->ready) return 0;
    if (surface->texture == 0) return 0;
    TessaGpu *gpu = surface->gpu;
    if (!eglMakeCurrent(gpu->display, surface->egl_surface, surface->egl_surface, gpu->context)) {
        gpu_error(gpu, "eglMakeCurrent failed while drawing (0x%x)", eglGetError());
        return 0;
    }
    glViewport(0, 0, surface->width, surface->height);
    glDisable(GL_BLEND);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_SCISSOR_TEST);
    glDisable(GL_CULL_FACE);
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    glUseProgram(gpu->program);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, surface->texture);
    glUniform1i(gpu->uniform_tex, 0);
    glUniform2f(gpu->uniform_res, (float)surface->width, (float)surface->height);
    /* Keep the shader clock small enough for mediump fallback devices. */
    glUniform1f(gpu->uniform_time, fmodf(time, 600.0f));
    glUniform1f(gpu->uniform_animate, animate ? 1.0f : 0.0f);

    glBindBuffer(GL_ARRAY_BUFFER, gpu->vbo);
    glEnableVertexAttribArray((GLuint)gpu->attr_pos);
    glVertexAttribPointer((GLuint)gpu->attr_pos, 2, GL_FLOAT, GL_FALSE, 0, (const void *)0);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glDisableVertexAttribArray((GLuint)gpu->attr_pos);

    if (!eglSwapBuffers(gpu->display, surface->egl_surface)) {
        gpu_error(gpu, "eglSwapBuffers failed (0x%x)", eglGetError());
        return 0;
    }
    return 1;
}
