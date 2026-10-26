#ifndef TESSA_MEDIA_H
#define TESSA_MEDIA_H

int tessa_media_start(void);
void tessa_media_stop(void);

/* 1 = play/pause, 2 = next, 3 = previous */
void tessa_media_command(unsigned int code);

#endif
