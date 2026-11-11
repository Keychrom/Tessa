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
    GLuint overlay_program;
    GLuint vbo;
    GLint attr_pos;
    GLint uniform_tex;
    GLint uniform_mark;
    GLint uniform_has_mark;
    GLint uniform_mark_size;
    GLint uniform_res;
    GLint uniform_time;
    GLint uniform_animate;
    GLint uniform_procedural;
    GLint uniform_top;
    GLint uniform_bottom;
    GLint uniform_accent;
    GLint uniform_prev_top;
    GLint uniform_prev_bottom;
    GLint uniform_prev_accent;
    GLint uniform_art;
    GLint uniform_prev_art;
    GLint uniform_fade;
    GLint overlay_attr_pos;
    GLint overlay_uniform_tex;
    GLint overlay_uniform_mat;
    GLint overlay_uniform_alpha;
    int ready;
    char error[256];
};

struct TessaGpuSurface {
    TessaGpu *gpu;
    struct wl_egl_window *window;
    EGLSurface egl_surface;
    GLuint texture;
    GLuint mark;
    int mark_w;
    int mark_h;
    int width;
    int height;
};

static const char *OVERLAY_VERTEX_SHADER =
    "#version 100\n"
    "attribute vec2 a_pos;\n"
    "uniform mat3 u_mat;\n"
    "varying vec2 v_uv;\n"
    "void main() {\n"
    "    v_uv = vec2(a_pos.x * 0.5 + 0.5, 0.5 - a_pos.y * 0.5);\n"
    "    gl_Position = vec4((u_mat * vec3(a_pos, 1.0)).xy, 0.0, 1.0);\n"
    "}\n";

static const char *OVERLAY_FRAGMENT_SHADER =
    "#version 100\n"
    "precision mediump float;\n"
    "varying vec2 v_uv;\n"
    "uniform sampler2D u_tex;\n"
    "uniform float u_alpha;\n"
    "void main() {\n"
    "    gl_FragColor = texture2D(u_tex, v_uv) * u_alpha;\n"
    "}\n";

static const char *VERTEX_SHADER =
    "#version 100\n"
    "attribute vec2 a_pos;\n"
    "varying vec2 v_uv;\n"
    "void main() {\n"
    "    v_uv = vec2(a_pos.x * 0.5 + 0.5, 0.5 - a_pos.y * 0.5);\n"
    "    gl_Position = vec4(a_pos, 0.0, 1.0);\n"
    "}\n";

/*
 * The texture path samples the Cairo wallpaper. The procedural path rebuilds
 * the Vermilion Ink gradient, wash, ink, sun, water, grain, and vignette on the
 * GPU. Both share the same restrained motion and the Cairo-rendered corner
 * mark.
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
    "uniform sampler2D u_mark;\n"
    "uniform float u_has_mark;\n"
    "uniform vec2 u_mark_size;\n"
    "uniform vec2 u_res;\n"
    "uniform float u_time;\n"
    "uniform float u_animate;\n"
    "uniform float u_procedural;\n"
    "uniform vec3 u_top;\n"
    "uniform vec3 u_bottom;\n"
    "uniform vec3 u_accent;\n"
    "uniform vec3 u_prev_top;\n"
    "uniform vec3 u_prev_bottom;\n"
    "uniform vec3 u_prev_accent;\n"
    "uniform float u_art;\n"
    "uniform float u_prev_art;\n"
    "uniform float u_fade;\n"
    "float hash(vec2 p) {\n"
    "    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);\n"
    "}\n"
    "void main() {\n"
    "    vec2 uv = v_uv;\n"
    "    float t = u_time * u_animate;\n"
    "    vec3 top = mix(u_prev_top, u_top, u_fade);\n"
    "    vec3 bottom = mix(u_prev_bottom, u_bottom, u_fade);\n"
    "    vec3 accent = mix(u_prev_accent, u_accent, u_fade);\n"
    "    float art = mix(u_prev_art, u_art, u_fade);\n"
    "    float water = smoothstep(0.70, 0.98, uv.y);\n"
    "    vec3 col;\n"
    "    if (u_procedural > 0.5) {\n"
    "        col = mix(top, bottom, uv.y);\n"
    "        float aspect = u_res.x / u_res.y;\n"
    "        vec2 p = uv + vec2(sin(uv.y * 9.0 + t * 0.18), cos(uv.x * 8.0 - t * 0.15)) * 0.0024 * u_animate;\n"
    "        vec2 d = vec2((p.x - 0.78) * aspect, p.y - 0.24);\n"
    "        col += accent * (0.12 * art) * smoothstep(0.44, 0.0, length(d));\n"
    "        col += vec3(0.10, 0.25, 0.28) * (0.030 * art) * smoothstep(0.42, 0.0, length(vec2((p.x - 0.20) * aspect, p.y - 0.72)));\n"
    "        col += vec3(0.10, 0.25, 0.28) * (0.022 * art) * smoothstep(0.54, 0.0, length(vec2((p.x - 0.64) * aspect, p.y - 0.78)));\n"
    "        col += vec3(0.10, 0.25, 0.28) * (0.020 * art) * smoothstep(0.34, 0.0, length(vec2((p.x - 0.08) * aspect, p.y - 0.30)));\n"
    "        col += vec3(0.10, 0.25, 0.28) * (0.018 * art) * smoothstep(0.26, 0.0, length(vec2((p.x - 0.44) * aspect, p.y - 0.14)));\n"
    "        col += vec3(0.10, 0.25, 0.28) * (0.026 * art) * smoothstep(0.30, 0.0, length(vec2((p.x - 0.88) * aspect, p.y - 0.62)));\n"
    "        vec2 sd = vec2((uv.x - 0.79) * aspect, uv.y - 0.235);\n"
    "        float sr = length(sd) / 0.155;\n"
    "        col += accent * (0.18 * art) * smoothstep(2.8, 0.65, sr);\n"
    "        float disk = 1.0 - smoothstep(0.97, 1.0, sr);\n"
    "        float grad = clamp((0.39 - uv.y) / 0.31, 0.0, 1.0);\n"
    "        vec3 sun = mix(vec3(0.55, 0.15, 0.15), vec3(0.93, 0.47, 0.35), grad);\n"
    "        col = mix(col, sun, disk * mix(0.26, 0.58, grad) * art);\n"
    "        col += accent * (0.18 * art) * smoothstep(0.03, 0.0, abs(sr - 1.26));\n"
    "        for (int k = 0; k < 6; k++) {\n"
    "            float fy = 0.80 + 0.028 * float(k) + sin(uv.x * 6.283 + t * 0.6 + float(k)) * 0.004 * water;\n"
    "            float line = smoothstep(0.004, 0.0, abs(uv.y - fy));\n"
    "            col += vec3(1.0) * line * (0.010 + 0.004 * float(k)) * art;\n"
    "        }\n"
    "        col += (hash(uv * u_res) - 0.5) * 0.006;\n"
    "        float vig = smoothstep(0.5, 1.0, length((uv - 0.5) * vec2(1.0, 1.2)));\n"
    "        col *= 1.0 - 0.38 * vig;\n"
    "        float shimmer = smoothstep(0.994, 1.0, sin(uv.y * 260.0 + sin(uv.x * 7.0 + t * 0.7) * 2.2)) * water;\n"
    "        col += vec3(0.72, 0.80, 0.92) * shimmer * 0.045 * u_animate;\n"
    "        float sunpulse = 1.0 - smoothstep(0.0, 0.34, distance(uv, vec2(0.79, 0.235)));\n"
    "        col += vec3(0.90, 0.34, 0.24) * sunpulse * (0.5 + 0.5 * sin(t * 0.55)) * 0.036 * u_animate;\n"
    "    } else {\n"
    "        vec2 q = uv;\n"
    "        q.x += sin(uv.y * 90.0 + t * 1.10) * 0.0032 * water;\n"
    "        q.y += cos(uv.x * 70.0 - t * 0.85) * 0.0020 * water;\n"
    "        q += vec2(sin(uv.y * 9.0 + t * 0.18), cos(uv.x * 8.0 - t * 0.15)) * 0.0024 * u_animate;\n"
    "        col = texture2D(u_tex, q).rgb;\n"
    "        float shimmer = smoothstep(0.994, 1.0, sin(uv.y * 260.0 + sin(uv.x * 7.0 + t * 0.7) * 2.2)) * water;\n"
    "        col += vec3(0.72, 0.80, 0.92) * shimmer * 0.045 * u_animate;\n"
    "        float sunpulse = 1.0 - smoothstep(0.0, 0.34, distance(uv, vec2(0.79, 0.235)));\n"
    "        col += vec3(0.90, 0.34, 0.24) * sunpulse * (0.5 + 0.5 * sin(t * 0.55)) * 0.036 * u_animate;\n"
    "        col += (hash(uv * u_res) - 0.5) * 0.006;\n"
    "    }\n"
    "    if (u_has_mark > 0.5 && u_procedural > 0.5) {\n"
    "        vec2 m = (uv - (vec2(1.0) - u_mark_size)) / u_mark_size;\n"
    "        if (all(greaterThanEqual(m, vec2(0.0))) && all(lessThanEqual(m, vec2(1.0)))) {\n"
    "            vec4 mk = texture2D(u_mark, m);\n"
    "            col = col * (1.0 - mk.a) + mk.rgb;\n"
    "        }\n"
    "    }\n"
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
        char log[1024];
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
        char log[1024];
        GLsizei len = 0;
        glGetProgramInfoLog(program, sizeof(log), &len, log);
        gpu_error(gpu, "program link failed: %.*s", (int)len, log);
        glDeleteProgram(program);
        return 0;
    }

    gpu->program = program;
    gpu->attr_pos = glGetAttribLocation(program, "a_pos");
    gpu->uniform_tex = glGetUniformLocation(program, "u_tex");
    gpu->uniform_mark = glGetUniformLocation(program, "u_mark");
    gpu->uniform_has_mark = glGetUniformLocation(program, "u_has_mark");
    gpu->uniform_mark_size = glGetUniformLocation(program, "u_mark_size");
    gpu->uniform_res = glGetUniformLocation(program, "u_res");
    gpu->uniform_time = glGetUniformLocation(program, "u_time");
    gpu->uniform_animate = glGetUniformLocation(program, "u_animate");
    gpu->uniform_procedural = glGetUniformLocation(program, "u_procedural");
    gpu->uniform_top = glGetUniformLocation(program, "u_top");
    gpu->uniform_bottom = glGetUniformLocation(program, "u_bottom");
    gpu->uniform_accent = glGetUniformLocation(program, "u_accent");
    gpu->uniform_prev_top = glGetUniformLocation(program, "u_prev_top");
    gpu->uniform_prev_bottom = glGetUniformLocation(program, "u_prev_bottom");
    gpu->uniform_prev_accent = glGetUniformLocation(program, "u_prev_accent");
    gpu->uniform_art = glGetUniformLocation(program, "u_art");
    gpu->uniform_prev_art = glGetUniformLocation(program, "u_prev_art");
    gpu->uniform_fade = glGetUniformLocation(program, "u_fade");
    if (gpu->attr_pos < 0 || gpu->uniform_tex < 0 || gpu->uniform_mark < 0 ||
        gpu->uniform_has_mark < 0 || gpu->uniform_mark_size < 0 ||
        gpu->uniform_res < 0 || gpu->uniform_time < 0 || gpu->uniform_animate < 0 ||
        gpu->uniform_procedural < 0 || gpu->uniform_top < 0 ||
        gpu->uniform_bottom < 0 || gpu->uniform_accent < 0 ||
        gpu->uniform_prev_top < 0 || gpu->uniform_prev_bottom < 0 ||
        gpu->uniform_prev_accent < 0 || gpu->uniform_art < 0 ||
        gpu->uniform_prev_art < 0 || gpu->uniform_fade < 0) {
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

static int ensure_overlay_program(TessaGpu *gpu) {
    if (gpu->overlay_program != 0) return 1;
    GLuint vs = compile_shader(gpu, GL_VERTEX_SHADER, OVERLAY_VERTEX_SHADER);
    if (vs == 0) return 0;
    GLuint fs = compile_shader(gpu, GL_FRAGMENT_SHADER, OVERLAY_FRAGMENT_SHADER);
    if (fs == 0) {
        glDeleteShader(vs);
        return 0;
    }
    GLuint program = glCreateProgram();
    if (program == 0) {
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
        char log[1024];
        GLsizei len = 0;
        glGetProgramInfoLog(program, sizeof(log), &len, log);
        gpu_error(gpu, "overlay program link failed: %.*s", (int)len, log);
        glDeleteProgram(program);
        return 0;
    }
    gpu->overlay_program = program;
    gpu->overlay_attr_pos = glGetAttribLocation(program, "a_pos");
    gpu->overlay_uniform_tex = glGetUniformLocation(program, "u_tex");
    gpu->overlay_uniform_mat = glGetUniformLocation(program, "u_mat");
    gpu->overlay_uniform_alpha = glGetUniformLocation(program, "u_alpha");
    if (gpu->overlay_attr_pos < 0 || gpu->overlay_uniform_tex < 0 ||
        gpu->overlay_uniform_mat < 0 || gpu->overlay_uniform_alpha < 0) {
        gpu_error(gpu, "overlay shader interface is incomplete");
        glDeleteProgram(program);
        gpu->overlay_program = 0;
        return 0;
    }
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

    eglSwapInterval(gpu->display, 0);
    gpu->ready = 1;
    fprintf(stderr, "tessa-panel: gpu: EGL %d.%d\n", (int)major, (int)minor);
    return gpu;
}

void tessa_gpu_destroy(TessaGpu *gpu) {
    if (gpu == NULL) return;
    if (gpu->display != EGL_NO_DISPLAY && gpu->context != EGL_NO_CONTEXT) {
        if (eglMakeCurrent(gpu->display, EGL_NO_SURFACE, EGL_NO_SURFACE, gpu->context)) {
            if (gpu->program != 0) {
                glDeleteProgram(gpu->program);
                gpu->program = 0;
            }
            if (gpu->overlay_program != 0) {
                glDeleteProgram(gpu->overlay_program);
                gpu->overlay_program = 0;
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
                if (surface->texture != 0) glDeleteTextures(1, &surface->texture);
                if (surface->mark != 0) glDeleteTextures(1, &surface->mark);
                surface->texture = 0;
                surface->mark = 0;
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

static int upload_texture(
    TessaGpuSurface *surface,
    GLuint *texture,
    const unsigned char *argb_pixels,
    int width,
    int height,
    int stride,
    const char *what) {
    if (surface == NULL || surface->gpu == NULL || !surface->gpu->ready) return 0;
    if (argb_pixels == NULL || width <= 0 || height <= 0 || stride < width * 4) return 0;
    TessaGpu *gpu = surface->gpu;
    if (!eglMakeCurrent(gpu->display, surface->egl_surface, surface->egl_surface, gpu->context)) {
        gpu_error(gpu, "eglMakeCurrent failed while uploading %s (0x%x)", what, eglGetError());
        return 0;
    }

    size_t pixels = (size_t)width * (size_t)height;
    if (pixels > SIZE_MAX / 4) return 0;
    unsigned char *rgba = malloc(pixels * 4);
    if (rgba == NULL) {
        gpu_error(gpu, "out of memory uploading %s", what);
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

    if (*texture == 0) {
        glGenTextures(1, texture);
        if (*texture == 0) {
            gpu_error(gpu, "glGenTextures failed for %s", what);
            free(rgba);
            return 0;
        }
    }
    while (glGetError() != GL_NO_ERROR) {
    }
    glBindTexture(GL_TEXTURE_2D, *texture);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, rgba);
    free(rgba);
    GLenum err = glGetError();
    if (err != GL_NO_ERROR) {
        gpu_error(gpu, "%s upload failed (0x%x)", what, (unsigned int)err);
        return 0;
    }
    return 1;
}

int tessa_gpu_set_base(
    TessaGpuSurface *surface,
    const unsigned char *argb_pixels,
    int width,
    int height,
    int stride) {
    return upload_texture(surface, &surface->texture, argb_pixels, width, height, stride,
                          "wallpaper texture");
}

int tessa_gpu_set_mark(
    TessaGpuSurface *surface,
    const unsigned char *argb_pixels,
    int width,
    int height,
    int stride) {
    if (!upload_texture(surface, &surface->mark, argb_pixels, width, height, stride, "corner mark")) {
        return 0;
    }
    surface->mark_w = width;
    surface->mark_h = height;
    return 1;
}

void tessa_gpu_clear_mark(TessaGpuSurface *surface) {
    if (surface == NULL || surface->gpu == NULL || !surface->gpu->ready) return;
    TessaGpu *gpu = surface->gpu;
    if (!eglMakeCurrent(gpu->display, surface->egl_surface, surface->egl_surface, gpu->context)) {
        return;
    }
    if (surface->mark != 0) glDeleteTextures(1, &surface->mark);
    surface->mark = 0;
    surface->mark_w = 0;
    surface->mark_h = 0;
}

int tessa_gpu_draw(TessaGpuSurface *surface, const TessaGpuParams *params) {
    if (surface == NULL || surface->gpu == NULL || !surface->gpu->ready || params == NULL) {
        return 0;
    }
    if (params->procedural == 0 && surface->texture == 0) return 0;
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
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, surface->mark);
    glUniform1i(gpu->uniform_mark, 1);
    glUniform1f(gpu->uniform_has_mark, surface->mark != 0 ? 1.0f : 0.0f);
    glUniform2f(gpu->uniform_mark_size,
                surface->width > 0 ? (float)surface->mark_w / (float)surface->width : 0.0f,
                surface->height > 0 ? (float)surface->mark_h / (float)surface->height : 0.0f);
    glUniform2f(gpu->uniform_res, (float)surface->width, (float)surface->height);
    glUniform1f(gpu->uniform_time, fmodf(params->time, 600.0f));
    glUniform1f(gpu->uniform_animate, params->animate ? 1.0f : 0.0f);
    glUniform1f(gpu->uniform_procedural, params->procedural ? 1.0f : 0.0f);
    glUniform3fv(gpu->uniform_top, 1, params->top);
    glUniform3fv(gpu->uniform_bottom, 1, params->bottom);
    glUniform3fv(gpu->uniform_accent, 1, params->accent);
    glUniform3fv(gpu->uniform_prev_top, 1, params->prev_top);
    glUniform3fv(gpu->uniform_prev_bottom, 1, params->prev_bottom);
    glUniform3fv(gpu->uniform_prev_accent, 1, params->prev_accent);
    glUniform1f(gpu->uniform_art, params->art);
    glUniform1f(gpu->uniform_prev_art, params->prev_art);
    glUniform1f(gpu->uniform_fade, params->fade);

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

int tessa_gpu_draw_overlay(TessaGpuSurface *surface, const TessaGpuOverlayParams *params) {
    if (surface == NULL || surface->gpu == NULL || !surface->gpu->ready || params == NULL) {
        return 0;
    }
    if (surface->texture == 0) return 0;
    TessaGpu *gpu = surface->gpu;
    if (!eglMakeCurrent(gpu->display, surface->egl_surface, surface->egl_surface, gpu->context)) {
        gpu_error(gpu, "eglMakeCurrent failed while drawing overlay (0x%x)", eglGetError());
        return 0;
    }
    if (!ensure_overlay_program(gpu)) return 0;
    glViewport(0, 0, surface->width, surface->height);
    float dim = params->dim;
    if (dim < 0.0f) dim = 0.0f;
    if (dim > 1.0f) dim = 1.0f;
    glClearColor(0.0f, 0.0f, 0.0f, dim);
    glClear(GL_COLOR_BUFFER_BIT);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_SCISSOR_TEST);
    glDisable(GL_CULL_FACE);
    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

    glUseProgram(gpu->overlay_program);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, surface->texture);
    glUniform1i(gpu->overlay_uniform_tex, 0);
    glUniformMatrix3fv(gpu->overlay_uniform_mat, 1, GL_FALSE, params->matrix);
    glUniform1f(gpu->overlay_uniform_alpha, params->alpha);

    glBindBuffer(GL_ARRAY_BUFFER, gpu->vbo);
    glEnableVertexAttribArray((GLuint)gpu->overlay_attr_pos);
    glVertexAttribPointer((GLuint)gpu->overlay_attr_pos, 2, GL_FLOAT, GL_FALSE, 0, (const void *)0);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glDisableVertexAttribArray((GLuint)gpu->overlay_attr_pos);

    if (!eglSwapBuffers(gpu->display, surface->egl_surface)) {
        gpu_error(gpu, "eglSwapBuffers failed while drawing overlay (0x%x)", eglGetError());
        return 0;
    }
    return 1;
}
