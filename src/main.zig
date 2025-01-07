const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len < 2) return error.ExpectedFileName;

    const output_file: ?[]u8 = if (args.len == 3) args[2] else null;
    const filename = args[1];
    var file: []u8 = undefined;

    if (std.mem.eql(u8, filename, "-")) {
        const stdin = std.io.getStdIn().reader();
        file = try stdin.readAllAlloc(allocator, 1024 * 1024);
    } else {
        // TODO: Try reading in chunks
        // 1MB max size currently
        file = try std.fs.cwd().readFileAlloc(allocator, filename, 1024 * 1024);
    }

    const res = try removeDuplicateAdjacent(allocator, file);

    if (output_file == null) {
        try stdout.print("{s}", .{res});
        try bw.flush();
    } else {
        const file_writer = try std.fs.cwd().createFile(output_file.?, .{});
        defer file_writer.close();

        try file_writer.writeAll(res);
    }
}

fn removeDuplicateAdjacent(allocator: Allocator, file: []u8) ![]u8 {
    var file_lines = std.mem.splitScalar(u8, file, '\n');

    // TODO: Think of a better way, the res's length may be less or equal than the file.len
    var res = std.ArrayList(u8).init(allocator);
    // Won't do anything
    defer res.deinit();

    var prev: []const u8 = "";

    while (file_lines.next()) |line| {
        if (std.mem.eql(u8, prev, line)) {
            continue;
        }

        prev = line;
        try res.appendSlice(line);
        try res.append('\n');
    }

    // The caller must free memory
    return res.toOwnedSlice();
}
