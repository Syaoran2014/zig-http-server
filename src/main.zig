const std = @import("std");
const http = std.http;
const net = std.net;

const server_addr = "127.0.0.1";
const server_port = 4221;

var filePath: ?[]const u8 = undefined;

pub fn main() !void {
    // const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--directory")) {
            filePath = args.next().?;
            break;
        } else {
            filePath = "/tmp/";
        }
    }

    var address = try net.Address.resolveIp(server_addr, server_port);
    // Address Var is a net.Address Object
    // Listener Var is a net.Server Object
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    try runServer(&listener, allocator);
}

fn runServer(listener: *net.Server, allocator: std.mem.Allocator) !void {
    outer: while (true) {
        const server = try listener.accept();
        defer server.stream.close();

        var client_head_buffer: [1024]u8 = undefined;
        var http_server = http.Server.init(server, &client_head_buffer);

        while (http_server.state == .ready) {
            var request = http_server.receiveHead() catch |err| switch (err) {
                error.HttpHeadersInvalid => continue :outer,
                error.HttpConnectionClosing => continue,
                else => |e| return e,
            };

            try handleRequest(&request, allocator);
        }
    }
}

fn handleRequest(request: *http.Server.Request, allocator: std.mem.Allocator) !void {
    const body = try (try request.reader()).readAllAlloc(allocator, 8192);
    defer allocator.free(body);

    if (std.mem.startsWith(u8, request.head.target, "/index.html")) {
        try request.respond("", .{});
    } else if (std.mem.eql(u8, request.head.target, "/")) {
        //wtf why did this change??
        try request.respond("HTTP-version", .{});
    } else if (std.mem.startsWith(u8, request.head.target, "/echo")) {
        var echo = std.mem.splitAny(u8, request.head.target, "/");
        _ = echo.next();
        _ = echo.next();
        const respEcho = echo.next().?;
        try request.respond(respEcho, .{ .extra_headers = &.{.{ .name = "Content-Type", .value = "text/plain" }} });
    } else if (std.mem.startsWith(u8, request.head.target, "/user-agent")) {
        var it = request.iterateHeaders();
        var respBody: []const u8 = undefined;
        while (it.next()) |header| {
            if (std.mem.eql(u8, header.name, "User-Agent")) {
                respBody = header.value;
            }
        }
        try request.respond(respBody, .{ .extra_headers = &.{.{ .name = "Content-Type", .value = "text/plain" }} });
    } else if (std.mem.startsWith(u8, request.head.target, "/files")) {
        //Step 2: Check if file exists
        //Step 3: If file exists, grab the contents of the file.
        //Step 4: Respond with the contents of the file.

        var file: []const u8 = undefined;
        var targetArray = std.mem.splitBackwardsAny(u8, request.head.target, "/");
        file = targetArray.next().?;

        const absFilePath = try std.mem.concat(allocator, u8, &.{ filePath.?[0..filePath.?.len], file[0..file.len] });

        const fileContent = std.fs.openFileAbsolute(absFilePath, .{}) catch |e| switch (e) {
            error.FileNotFound => {
                try request.respond("", .{ .status = .not_found });
                return;
            },
            else => return e,
        };

        var content = [_]u8{'A'} ** 64;
        const byte_read = try fileContent.read(&content);

        try request.respond(content[0..byte_read], .{ .extra_headers = &.{.{ .name = "Content-Type", .value = "application/octet-stream" }} });
    } else {
        try request.respond("", .{ .status = .not_found });
    }
}
