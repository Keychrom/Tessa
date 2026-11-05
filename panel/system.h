#ifndef TESSA_SYSTEM_H
#define TESSA_SYSTEM_H

/* Returns the read end of a socketpair carrying framed system state. */
int tessa_system_start(void);
void tessa_system_stop(void);

/* Bitmask of enabled control features (see panel/model.zig). */
void tessa_system_set_features(unsigned int mask);

void tessa_system_wifi_toggle(void);
void tessa_system_wifi_scan(void);
void tessa_system_wifi_connect(const char *ap_path, const char *ssid,
        const char *psk, int hidden);
void tessa_system_wifi_disconnect(void);
void tessa_system_wifi_forget(const char *conn_path);

void tessa_system_bt_toggle(void);
void tessa_system_bt_discovery(int on);
void tessa_system_bt_pair(const char *path);
void tessa_system_bt_connect(const char *path, int connect);
void tessa_system_bt_forget(const char *path);
void tessa_system_bt_agent_reply(int code, const char *text);

void tessa_system_set_brightness(int percent);
void tessa_system_set_profile(const char *name);

#endif
