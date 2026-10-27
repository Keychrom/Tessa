#ifndef TESSA_REGEX_SHIM_H
#define TESSA_REGEX_SHIM_H

void *tessa_regex_create(void);
void tessa_regex_destroy(void *regex);
int tessa_regex_compile(void *regex, const char *pattern);
int tessa_regex_match(void *regex, const char *text);

#endif
