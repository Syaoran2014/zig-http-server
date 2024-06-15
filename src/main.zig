const std = @import("std");
const http = std.http;
const net = std.net;

const server_addr = "127.0.0.1";
const server_port = 4221;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

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

        try handleRequest(&request, allocator);

        try stdout.print("client connected!", .{});
    }
}

fn handleRequest(request: *http.Server.Request, allocator: std.mem.Allocator) !void {
    const body = try (try request.reader()).readAllAlloc(allocator, 8192);
    defer allocator.free(body);

    if (std.mem.startsWith(u8, request.head.target, "/index.html")) {
        try request.respond("", .{});
    } else if (std.mem.eql(u8, request.head.target, "/")) {
        try request.respond("", .{});
    } else if (std.mem.startsWith(u8, request.head.target, "/echo")) {
        var echo = std.mem.splitAny(u8, request.head.target, "/");
        _ = echo.next();
        _ = echo.next();
        const respEcho = echo.next().?;
        try request.respond(respEcho, .{});
    } else {
        try request.respond("", .{ .status = .not_found });
    }
}
