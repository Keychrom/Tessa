#ifndef TESSA_NOTIFICATIONS_H
#define TESSA_NOTIFICATIONS_H

/* Start the org.freedesktop.Notifications service on a GLib thread.
 * Returns a nonblocking-friendly read socket for panel events, or -1. */
int tessa_notifications_start(void);

/* Stop the service thread and close its sockets. */
void tessa_notifications_stop(void);

/* Tell the service that the panel removed a notification.
 * reason follows the desktop notification spec: 1 expired, 2 dismissed. */
void tessa_notifications_close(unsigned int id, unsigned int reason);

/* Emit ActionInvoked for a notification action selected in the panel. */
void tessa_notifications_action(unsigned int id, const char *key);

#endif
