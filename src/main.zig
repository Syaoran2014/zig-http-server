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

    // Allows Concurrent Connections properly....
    while (true) {
        var server = try listener.accept();
        // defer server.stream.close();
        var handle = try std.Thread.spawn(.{ .allocator = allocator }, createConnection, .{ &server, allocator });
        handle.detach();
    }
}

fn createConnection(Conn: *net.Server.Connection, allocator: std.mem.Allocator) !void {
    outer: while (true) {
        // const server = try listener.accept();
        // defer server.stream.close();

        var client_head_buffer: [1024]u8 = undefined;
        var http_server = http.Server.init(Conn.*, &client_head_buffer);

        while (http_server.state == .ready) {
            var request = http_server.receiveHead() catch |err| switch (err) {
                error.HttpHeadersInvalid => continue :outer,
                error.HttpConnectionClosing => continue,
                error.HttpHeadersUnreadable => continue,
                else => |e| return e,
            };
            try handleRequest(&request, allocator);
        }
    }
}

const Routes = enum {
    echo,
    useragent,
    files,
    null,
    root,
};

fn handleRequest(request: *http.Server.Request, allocator: std.mem.Allocator) !void {
    const body = try (try request.reader()).readAllAlloc(allocator, 8192);
    defer allocator.free(body);
    var headers = request.iterateHeaders();

    //Creates Target array to later use.
    var targets = std.ArrayList([]const u8).init(allocator);
    defer targets.deinit();
    var requestTargets = std.mem.splitAny(u8, request.head.target, "/");
    while (requestTargets.next()) |targ| {
        if (targ.len == 0) continue;
        try targets.append(targ);
    }

    // Actually makes the Array and changes it to an Enum I can Switch from.
    const targetArray = targets.items;
    var route: ?Routes = null;
    if (targetArray.len == 0) {
        route = Routes.root; // If Array len is 0, can assume "localhost:4221/"
    } else if (std.mem.eql(u8, targetArray[0], "user-agent")) { //Special Case, can't use hypens in enums.
        //Due to this "localhost:4221/useragent" now works
        route = std.meta.stringToEnum(Routes, "useragent");
    } else {
        route = std.meta.stringToEnum(Routes, targetArray[0]);
    }

    //If route is null, can assume bad request.
    if (route == null) {
        try request.respond("", .{ .status = .bad_request });
        return;
    }

    switch (request.head.method) {
        http.Method.GET => {
            switch (route.?) {
                Routes.echo => {
                    if (targetArray[1].len > 0) {
                        try request.respond(targetArray[1], .{ .extra_headers = &.{.{ .name = "Content-Type", .value = "text/plain" }} });
                    } else {
                        try request.respond("", .{ .status = .bad_request });
                    }
                },
                Routes.useragent => {
                    var respBody: []const u8 = undefined;
                    while (headers.next()) |header| {
                        if (std.mem.eql(u8, header.name, "User-Agent")) {
                            respBody = header.value;
                        }
                    }
                    try request.respond(respBody, .{ .extra_headers = &.{.{ .name = "Content-Type", .value = "text/plain" }} });
                },
                Routes.files => {
                    if (targetArray[1].len > 0) {
                        const absFilePath = try std.mem.concat(allocator, u8, &.{ filePath.?[0..filePath.?.len], targetArray[1][0..targetArray[1].len] });
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
                        try request.respond("", .{ .status = .bad_request });
                    }
                },
                else => try request.respond("", .{}),
            }
        },
        http.Method.POST => {
            switch (route.?) {
                Routes.files => {
                    if (body.len == 0) {
                        try request.respond("", .{ .status = .bad_request });
                        return;
                    }
                    if (targetArray[1].len == 0) {
                        try request.respond("", .{ .status = .bad_request });
                        return;
                    }
                    const absFilePath = try std.mem.concat(allocator, u8, &.{ filePath.?[0..filePath.?.len], targetArray[1][0..targetArray[1].len] });
                    const file: std.fs.File = try std.fs.createFileAbsolute(absFilePath, .{});
                    defer file.close();

                    const byteWritten = try file.write(body);
                    if (byteWritten > 0) {
                        try request.respond("", .{ .status = .created });
                    } else {
                        try request.respond("", .{ .status = .internal_server_error });
                    }
                },
                else => try request.respond("", .{ .status = .bad_request }),
            }
        },
        else => try request.respond("", .{ .status = .bad_request }),
    }
}
