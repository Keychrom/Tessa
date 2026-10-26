pub const c = @cImport({
    @cDefine("_GNU_SOURCE", "1");
    // ReleaseSafe enables glibc fortify wrappers that translate-c cannot handle.
    @cDefine("_FORTIFY_SOURCE", "0");

    @cInclude("wayland-client.h");
    @cInclude("wayland-client-protocol.h");
    @cInclude("layer-shell-client-protocol.h");
    @cInclude("text-input-client-protocol.h");

    @cInclude("cairo/cairo.h");
    @cInclude("text.h");

    @cInclude("xkbcommon/xkbcommon.h");

    @cInclude("dirent.h");
    @cInclude("fcntl.h");
    @cInclude("math.h");
    @cInclude("poll.h");
    @cInclude("signal.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("sys/mman.h");
    @cInclude("sys/socket.h");
    @cInclude("sys/stat.h");
    @cInclude("sys/types.h");
    @cInclude("sys/un.h");
    @cInclude("time.h");
    @cInclude("unistd.h");
});
