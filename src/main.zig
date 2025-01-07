const std = @import("std");
const Allocator = std.mem.Allocator;
const ArgIterator = std.process.ArgIterator;

const Config = struct {
    input_file: ?[]const u8 = null,
    output_file: ?[]const u8 = null,
    /// (-c, --count) adds a new first column that contains a count of the number of times a line appears in the input file
    count: bool = false,
    /// (-d, --repeated) outputs only repeated lines
    repeated: bool = false,

    fn streql(a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }

    fn init(args: *ArgIterator) Config {
        var config = Config{};
        var is_input_set = false;

        // Skip exe name
        _ = args.next();

        while (args.next()) |arg| {
            if (streql(arg, "-c") or streql(arg, "--count")) {
                config.count = true;
            } else if (streql(arg, "-")) {
                is_input_set = true;
            } else if (!is_input_set) {
                is_input_set = true;
                config.input_file = arg;
            } else if (streql(arg, "-d") or streql(arg, "--repeated")) {
                config.repeated = true;
            } else {
                config.output_file = arg;
            }
        }

        return config;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var args = std.process.args();
    const config = Config.init(&args);

    var file: []u8 = undefined;

    if (config.input_file == null) {
        const stdin = std.io.getStdIn().reader();
        file = try stdin.readAllAlloc(allocator, 1024 * 1024);
    } else {
        // TODO: Try reading in chunks
        // 1MB max size currently
        file = try std.fs.cwd().readFileAlloc(allocator, config.input_file.?, 1024 * 1024);
    }

    const res = try uniq(allocator, file, config.count, config.repeated);
    defer allocator.free(res);

    if (config.output_file == null) {
        try stdout.print("{s}", .{res});
        try bw.flush();
    } else {
        const file_writer = try std.fs.cwd().createFile(config.output_file.?, .{});
        defer file_writer.close();

        try file_writer.writeAll(res);
    }
}

fn uniq(allocator: Allocator, file: []u8, count: bool, repeated: bool) ![]u8 {
    var file_lines = std.mem.splitScalar(u8, file, '\n');

    var res = std.ArrayList(u8).init(allocator);
    // Won't do anything
    defer res.deinit();

    var prev: []const u8 = file_lines.next().?;
    var i: u32 = 1;

    while (file_lines.next()) |line| {
        if (std.mem.eql(u8, prev, line)) {
            i += 1;
            continue;
        }

        if (repeated) {
            if (i > 1) {
                if (count) {
                    var buf: [256]u8 = undefined;
                    const str = try std.fmt.bufPrint(&buf, "{}", .{i});

                    try res.appendSlice(str);
                    try res.append(' ');
                }
                try res.appendSlice(prev);
                try res.append('\n');
            }
        } else {
            if (count) {
                var buf: [256]u8 = undefined;
                const str = try std.fmt.bufPrint(&buf, "{}", .{i});

                try res.appendSlice(str);
                try res.append(' ');
            }
            try res.appendSlice(prev);
            try res.append('\n');
        }

        prev = line;
        i = 1;
    }

    // The caller must free memory
    return res.toOwnedSlice();
}
