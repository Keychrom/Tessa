#ifndef TESSA_AUDIO_H
#define TESSA_AUDIO_H

int tessa_audio_start(const char *status_cmd, const char *up_cmd,
        const char *down_cmd, const char *mute_cmd);
void tessa_audio_stop(void);

/* 1 = volume up, 2 = volume down, 3 = toggle mute */
void tessa_audio_command(unsigned int code);

#endif
