#include "regex_shim.h"

#include <regex.h>
#include <stdlib.h>

void *tessa_regex_create(void) {
    return calloc(1, sizeof(regex_t));
}

void tessa_regex_destroy(void *regex) {
    if (regex == NULL) return;
    regfree((regex_t *)regex);
    free(regex);
}

int tessa_regex_compile(void *regex, const char *pattern) {
    return regcomp((regex_t *)regex, pattern, REG_EXTENDED | REG_NOSUB);
}

int tessa_regex_match(void *regex, const char *text) {
    return regexec((regex_t *)regex, text, 0, NULL, 0) == 0;
}
