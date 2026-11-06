#ifndef TESSA_PANEL_C_IMPORT_H
#define TESSA_PANEL_C_IMPORT_H

#define _GNU_SOURCE 1
#define _FORTIFY_SOURCE 0

#include <wayland-client.h>
#include <wayland-client-protocol.h>
#include <layer-shell-client-protocol.h>
#include <text-input-client-protocol.h>
#include <wlr-data-control-unstable-v1-client-protocol.h>
#include <wlr-screencopy-unstable-v1-client-protocol.h>
#include <ext-foreign-toplevel-list-v1-client-protocol.h>
#include <ext-image-capture-source-v1-client-protocol.h>
#include <ext-image-copy-capture-v1-client-protocol.h>

#include <cairo/cairo.h>
#include "text.h"
#include "gpu.h"
#include "preview.h"

#include <xkbcommon/xkbcommon.h>

#include <dirent.h>
#include <fcntl.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#endif
