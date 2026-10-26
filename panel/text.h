#ifndef TESSA_TEXT_H
#define TESSA_TEXT_H

typedef struct _cairo cairo_t;

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
    double *out_height);

/* Draw Pango markup when it parses cleanly, otherwise fall back to plain text. */
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
    double *out_height);

double tessa_text_measure(
    cairo_t *cr,
    const char *utf8,
    int len,
    const char *family,
    const char *style,
    double size,
    double spacing,
    double *out_height);

#endif
