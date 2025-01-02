//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.
const Allocator = std.mem.Allocator;

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len < 2) return error.ExpectedFileName;

    const filename = args[1];

    // TODO: Try reading in chunks
    // 1MB max size currently
    const file = try std.fs.cwd().readFileAlloc(allocator, filename, 1024 * 1024);

    const res = try removeDuplicateAdjacent(allocator, file);
    try stdout.print("{s}", .{res});

    try bw.flush();
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

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const global = struct {
        fn testOne(input: []const u8) anyerror!void {
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(global.testOne, .{});
}

const std = @import("std");

// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
// const lib = @import("ccuniq_lib");
