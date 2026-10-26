#ifndef TESSA_TRAY_H
#define TESSA_TRAY_H

int tessa_tray_start(void);
void tessa_tray_stop(void);

/* 1 = Activate, 2 = SecondaryActivate */
void tessa_tray_activate(unsigned int index, unsigned int code);

#endif
