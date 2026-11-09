#include "text.h"

#include <cairo/cairo.h>
#include <locale.h>
#include <pango/pangocairo.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *tessa_cjk_fallbacks = NULL;

/*
 * Pango's fontconfig fallback often resolves CJK text to Noto Sans CJK KR on
 * systems that also have the JP face, even with a Japanese locale. Pango
 * language attributes do not override that choice; an explicit family list
 * does. Keep the configured family first for Latin text, then prefer the
 * locale's CJK face.
 */
static const char *tessa_pick_cjk_fallbacks(void) {
    const char *locale = getenv("LC_ALL");
    if (!locale || !*locale) locale = getenv("LC_CTYPE");
    if (!locale || !*locale) locale = getenv("LANG");

    if (locale && locale[0] && locale[1]) {
        const char first = (char)(locale[0] | 0x20);
        const char second = (char)(locale[1] | 0x20);
        if (first == 'k' && second == 'o') {
            return "Noto Sans CJK KR, Noto Sans KR, Source Han Sans KR, "
                   "NanumGothic, sans-serif";
        }
        if (first == 'z' && second == 'h') {
            if (strstr(locale, "TW") || strstr(locale, "HK") || strstr(locale, "MO")) {
                return "Noto Sans CJK TC, Noto Sans TC, Source Han Sans TC, "
                       "sans-serif";
            }
            return "Noto Sans CJK SC, Noto Sans SC, Source Han Sans SC, "
                   "WenQuanYi Zen Hei, sans-serif";
        }
    }

    return "Noto Sans CJK JP, Noto Sans JP, Source Han Sans JP, IPAGothic, "
           "IPAPGothic, TakaoPGothic, VL PGothic, sans-serif";
}

void tessa_text_init(void) {
    setlocale(LC_CTYPE, "");
    tessa_cjk_fallbacks = tessa_pick_cjk_fallbacks();
    if (getenv("TESSA_DEBUG")) {
        fprintf(stderr, "tessa-panel: font fallback=%s\n", tessa_cjk_fallbacks);
    }
}

static const char *tessa_fallbacks(void) {
    if (!tessa_cjk_fallbacks) tessa_text_init();
    return tessa_cjk_fallbacks;
}

static void tessa_font_string(
    char *buf,
    size_t len,
    const char *family,
    const char *style,
    double size) {
    snprintf(buf, len, "%s, %s %s %.1f",
        family && family[0] ? family : "Inter",
        tessa_fallbacks(),
        style && style[0] ? style : "Regular",
        size);
}

static PangoLayout *tessa_make_layout(
    cairo_t *cr,
    const char *utf8,
    int len,
    const char *family,
    const char *style,
    double size,
    double max_width,
    double spacing,
    int markup) {
    PangoLayout *layout = pango_cairo_create_layout(cr);
    if (!layout) return NULL;

    char font[512];
    tessa_font_string(font, sizeof(font), family, style, size);

    PangoFontDescription *desc = pango_font_description_from_string(font);
    if (desc) {
        pango_layout_set_font_description(layout, desc);
        pango_font_description_free(desc);
    }
    if (markup) {
        GError *error = NULL;
        if (pango_parse_markup(utf8, len, 0, NULL, NULL, NULL, &error)) {
            pango_layout_set_markup(layout, utf8, len);
        } else {
            if (error) g_error_free(error);
            pango_layout_set_text(layout, utf8, len);
        }
    } else {
        pango_layout_set_text(layout, utf8, len);
    }

    if (max_width > 1.0) {
        pango_layout_set_width(layout, (int)(max_width * PANGO_SCALE));
        pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END);
    }
    if (spacing > 0.001 || spacing < -0.001) {
        PangoAttrList *attrs = pango_attr_list_new();
        if (attrs) {
            PangoAttribute *attr = pango_attr_letter_spacing_new((int)(spacing * PANGO_SCALE));
            pango_attr_list_insert(attrs, attr);
            pango_layout_set_attributes(layout, attrs);
            pango_attr_list_unref(attrs);
        }
    }
    return layout;
}

double tessa_text_draw(
    cairo_t *cr,
    const char *utf8,
    int len,
    const char *family,
    const char *style,
    double size,
    double max_width,
    double spacing,
    double x,
    double y,
    int vertical_center,
    double r,
    double g,
    double b,
    double a,
    double *out_height) {
    if (!cr || !utf8 || len <= 0) return 0;
    PangoLayout *layout = tessa_make_layout(cr, utf8, len, family, style, size, max_width, spacing, 0);
    if (!layout) return 0;

    int pw = 0, ph = 0;
    pango_layout_get_pixel_size(layout, &pw, &ph);

    cairo_save(cr);
    cairo_set_source_rgba(cr, r, g, b, a);
    const double draw_y = vertical_center ? y - (double)ph / 2.0 : y;
    cairo_move_to(cr, x, draw_y);
    pango_cairo_show_layout(cr, layout);
    cairo_restore(cr);

    if (out_height) *out_height = (double)ph;
    g_object_unref(layout);
    return (double)pw;
}

double tessa_text_draw_markup(
    cairo_t *cr,
    const char *utf8,
    int len,
    const char *family,
    const char *style,
    double size,
    double max_width,
    double spacing,
    double x,
    double y,
    int vertical_center,
    double r,
    double g,
    double b,
    double a,
    double *out_height) {
    if (!cr || !utf8 || len <= 0) return 0;
    PangoLayout *layout = tessa_make_layout(cr, utf8, len, family, style, size, max_width, spacing, 1);
    if (!layout) return 0;

    int pw = 0, ph = 0;
    pango_layout_get_pixel_size(layout, &pw, &ph);

    cairo_save(cr);
    cairo_set_source_rgba(cr, r, g, b, a);
    const double draw_y = vertical_center ? y - (double)ph / 2.0 : y;
    cairo_move_to(cr, x, draw_y);
    pango_cairo_show_layout(cr, layout);
    cairo_restore(cr);

    if (out_height) *out_height = (double)ph;
    g_object_unref(layout);
    return (double)pw;
}

double tessa_text_measure(
    cairo_t *cr,
    const char *utf8,
    int len,
    const char *family,
    const char *style,
    double size,
    double spacing,
    double *out_height) {
    if (!cr || !utf8 || len <= 0) return 0;
    PangoLayout *layout = tessa_make_layout(cr, utf8, len, family, style, size, 0, spacing, 0);
    if (!layout) return 0;
    int pw = 0, ph = 0;
    pango_layout_get_pixel_size(layout, &pw, &ph);
    if (out_height) *out_height = (double)ph;
    g_object_unref(layout);
    return (double)pw;
}
