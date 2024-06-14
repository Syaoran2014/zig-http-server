const std = @import("std");
const http = std.http;
const net = std.net;

const server_addr = "127.0.0.1";
const server_port = 4221;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var address = try net.Address.resolveIp(server_addr, server_port);
    // Address Var is a net.Address Object
    // Server Var is a net.Server Object
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    const server = try listener.accept();
    defer server.stream.close();

    var client_head_buffer: [1024]u8 = undefined;
    var http_server = http.Server.init(server, &client_head_buffer);

    while (http_server.state == .ready) {
        var request = http_server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => continue,
            else => |e| return e,
        };

        _ = try request.respond("", .{});

        try stdout.print("client connected!", .{});
    }
}
