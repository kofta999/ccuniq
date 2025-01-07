const std = @import("std");
const Allocator = std.mem.Allocator;
const ArgIterator = std.process.ArgIterator;
const testing = std.testing;

const Config = struct {
    /// Input file, if (-) is present get input from standard input
    input_file: ?[]const u8 = null,
    /// Output file, if not present output to standard output
    output_file: ?[]const u8 = null,
    /// (-c, --count) adds a new first column that contains a count of the number of times a line appears in the input file
    count: bool = false,
    /// (-d, --repeated) outputs only repeated lines
    repeated: bool = false,
    /// (-u) outputs only unique lines
    unique: bool = false,

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
            } else if (streql(arg, "-u")) {
                config.unique = true;
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

    const res = try uniq(allocator, file, config);
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

fn uniq(allocator: Allocator, file: []const u8, config: Config) ![]u8 {
    var file_lines = std.mem.splitScalar(u8, file, '\n');

    var res = std.ArrayList(u8).init(allocator);
    // Won't do anything
    defer res.deinit();

    var i: u32 = 1;

    while (file_lines.next()) |curr| {
        const next = file_lines.peek() orelse "";

        if (std.mem.eql(u8, curr, next)) {
            i += 1;
            continue;
        }

        if (config.repeated) {
            if (i > 1) {
                if (config.count) {
                    var buf: [256]u8 = undefined;
                    const str = try std.fmt.bufPrint(&buf, "{}", .{i});

                    try res.appendSlice(str);
                    try res.append(' ');
                }
                try res.appendSlice(curr);
                try res.append('\n');
            }
        } else if (config.unique) {
            if (i == 1) {
                if (config.count) {
                    var buf: [256]u8 = undefined;
                    const str = try std.fmt.bufPrint(&buf, "{}", .{i});

                    try res.appendSlice(str);
                    try res.append(' ');
                }

                try res.appendSlice(curr);
                try res.append('\n');
            }
        } else {
            if (config.count) {
                var buf: [256]u8 = undefined;
                const str = try std.fmt.bufPrint(&buf, "{}", .{i});

                try res.appendSlice(str);
                try res.append(' ');
            }

            try res.appendSlice(curr);
            try res.append('\n');
        }

        i = 1;
    }

    // The caller must free memory
    return res.toOwnedSlice();
}

test "uniq - basic functionality" {
    const allocator = testing.allocator;

    // Basic test with repeated lines
    {
        const input =
            \\apple
            \\apple
            \\banana
            \\cherry
            \\cherry
            \\
        ;
        const expected =
            \\apple
            \\banana
            \\cherry
            \\
        ;
        const config = Config{};
        const result = try uniq(allocator, input, config);
        defer allocator.free(result);
        try testing.expectEqualStrings(expected, result);
    }

    // Test with count flag
    {
        const input =
            \\apple
            \\apple
            \\banana
            \\cherry
            \\cherry
            \\
        ;
        const expected =
            \\2 apple
            \\1 banana
            \\2 cherry
            \\
        ;
        const config = Config{ .count = true };
        const result = try uniq(allocator, input, config);
        defer allocator.free(result);
        try testing.expectEqualStrings(expected, result);
    }

    // Test with repeated flag
    {
        const input =
            \\apple
            \\apple
            \\banana
            \\cherry
            \\cherry
            \\
        ;
        const expected =
            \\apple
            \\cherry
            \\
        ;
        const config = Config{ .repeated = true };
        const result = try uniq(allocator, input, config);
        defer allocator.free(result);
        try testing.expectEqualStrings(expected, result);
    }

    // Test with unique flag
    {
        const input =
            \\apple
            \\apple
            \\banana
            \\cherry
            \\cherry
            \\
        ;
        const expected =
            \\banana
            \\
        ;
        const config = Config{ .unique = true };
        const result = try uniq(allocator, input, config);
        defer allocator.free(result);
        try testing.expectEqualStrings(expected, result);
    }

    // Test with repeated and count flags
    {
        const input =
            \\apple
            \\apple
            \\banana
            \\cherry
            \\cherry
            \\
        ;
        const expected =
            \\2 apple
            \\2 cherry
            \\
        ;
        const config = Config{ .repeated = true, .count = true };
        const result = try uniq(allocator, input, config);
        defer allocator.free(result);
        try testing.expectEqualStrings(expected, result);
    }
}

test "uniq - edge cases" {
    const allocator = testing.allocator;

    // Empty input
    {
        const input = "";
        const expected = "";
        const config = Config{};
        const result = try uniq(allocator, input, config);
        defer allocator.free(result);
        try testing.expectEqualStrings(expected, result);
    }

    // Single line
    {
        const input = "apple\n";
        const expected = "apple\n";
        const config = Config{};
        const result = try uniq(allocator, input, config);
        defer allocator.free(result);
        try testing.expectEqualStrings(expected, result);
    }

    // All lines identical
    {
        const input =
            \\same
            \\same
            \\same
            \\
        ;
        const expected = "same\n";
        const config = Config{};
        const result = try uniq(allocator, input, config);
        defer allocator.free(result);
        try testing.expectEqualStrings(expected, result);
    }

    // No repeated lines
    {
        const input =
            \\a
            \\b
            \\c
            \\
        ;
        const expected =
            \\a
            \\b
            \\c
            \\
        ;
        const config = Config{};
        const result = try uniq(allocator, input, config);
        defer allocator.free(result);
        try testing.expectEqualStrings(expected, result);
    }
}
