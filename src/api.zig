//! Central protocol and schema version registry.
//!
//! Clients negotiate the line protocol with `HELLO`. Capabilities are additive:
//! an older client ignores names it does not know, and a newer client can use
//! `tessa_version` plus the individual API versions to decide what to call.

const std = @import("std");

pub const tessa_version = "0.2.5";

pub const line_protocol: u8 = 1;
pub const jsonrpc: u8 = 1;
pub const state_schema: u8 = 1;
pub const config_schema: u8 = 1;
pub const extension_api: u8 = 1;
pub const layout_api: u8 = 2;
pub const effect_api: u8 = 2;

pub const capabilities =
    "state,config,events,subscriptions,config-compare,perf,rendering,special,groups,extensions,effects2,shell-modules";

pub fn writeVersionJson(writer: anytype) !void {
    try writer.print(
        "{{\"tessa\":\"{s}\",\"line\":{d},\"jsonrpc\":{d},\"state\":{d},\"config\":{d},\"extension\":{d},\"layout\":{d},\"effect\":{d}}}",
        .{
            tessa_version,
            line_protocol,
            jsonrpc,
            state_schema,
            config_schema,
            extension_api,
            layout_api,
            effect_api,
        },
    );
}

test "capabilities include extension surfaces" {
    try std.testing.expect(std.mem.indexOf(u8, capabilities, "extensions") != null);
    try std.testing.expect(std.mem.indexOf(u8, capabilities, "effects2") != null);
}
