const std = @import("std");
const c = @import("zrocksdb").c;
const c_allocator = std.heap.c_allocator;

test "Basic Usage" {
    var temp_dir = std.testing.tmpDir(.{});
    defer temp_dir.cleanup();

    try temp_dir.dir.setAsCwd();

    const db_name = "testdb";
    const opts = c.rocksdb_options_create();
    defer c.rocksdb_options_destroy(opts);
    c.rocksdb_options_set_create_if_missing(opts, 1);
    c.rocksdb_options_set_error_if_exists(opts, 1);
    c.rocksdb_options_set_compression(opts, c.rocksdb_snappy_compression);

    var err: ?[*:0]const u8 = null;
    const db = c.rocksdb_open(opts, @ptrCast(db_name), @ptrCast(&err));
    defer c.rocksdb_close(db);
    if (err) |error_message| {
        defer {
            c_allocator.free(std.mem.sliceTo(error_message, 0));
            err = null;
        }

        std.log.err("Failed to open database: {s}", .{error_message});
        return error.failed_to_open_database;
    }

    const key = "foo";
    const stored_value = "bar";
    {
        const wo = c.rocksdb_writeoptions_create();
        defer c.rocksdb_writeoptions_destroy(wo);
        c.rocksdb_put(db, wo, key, key.len, stored_value, stored_value.len, @ptrCast(&err));
        if (err) |error_message| {
            defer {
                c_allocator.free(std.mem.sliceTo(error_message, 0));
                err = null;
            }

            std.log.err("Failed to put key: {s}", .{error_message});
            return error.failed_to_put_key;
        }
    }

    {
        const ro = c.rocksdb_readoptions_create();
        defer c.rocksdb_readoptions_destroy(ro);
        var retrieved_len: usize = undefined;
        const retrieved_ptr = c.rocksdb_get(db, ro, key, key.len, &retrieved_len, @ptrCast(&err));
        if (err) |error_message| {
            defer {
                c_allocator.free(std.mem.sliceTo(error_message, 0));
                err = null;
            }

            std.log.err("Failed to get key: {s}", .{std.mem.sliceTo(error_message, 0)});
            return error.failed_to_get_key;
        }
        const retrieved_value = retrieved_ptr[0..retrieved_len];
        std.log.info("get key len: {d}, value: {s}\n", .{ retrieved_len, retrieved_value });
        try std.testing.expectEqualStrings(stored_value, retrieved_value);
    }
}
