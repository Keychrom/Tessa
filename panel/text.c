#include "text.h"

#include <cairo/cairo.h>
#include <pango/pangocairo.h>
#include <stdio.h>

static PangoLayout *tessa_make_layout(
    cairo_t *cr,
    const char *utf8,
    int len,
    const char *family,
    const char *style,
    double size,
    double max_width,
    double spacing) {
    PangoLayout *layout = pango_cairo_create_layout(cr);
    if (!layout) return NULL;

    char font[256];
    snprintf(font, sizeof(font), "%s %s %.1f",
        family && family[0] ? family : "Inter",
        style && style[0] ? style : "Regular",
        size);

    PangoFontDescription *desc = pango_font_description_from_string(font);
    if (desc) {
        pango_layout_set_font_description(layout, desc);
        pango_font_description_free(desc);
    }
    pango_layout_set_text(layout, utf8, len);

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
    PangoLayout *layout = tessa_make_layout(cr, utf8, len, family, style, size, max_width, spacing);
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
    PangoLayout *layout = tessa_make_layout(cr, utf8, len, family, style, size, 0, spacing);
    if (!layout) return 0;
    int pw = 0, ph = 0;
    pango_layout_get_pixel_size(layout, &pw, &ph);
    if (out_height) *out_height = (double)ph;
    g_object_unref(layout);
    return (double)pw;
}
