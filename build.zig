pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const opt_linkage = b.option(std.builtin.LinkMode, "link-mode", "") orelse .static;
    const opt_sanitize_c = b.option(std.zig.SanitizeC, "sanitize-c", "") orelse null;
    const opt_sanitize_thread = b.option(bool, "sanitize-thread", "") orelse null;
    const opt_has_altivec = b.option(bool, "has-altivec", "") orelse false;
    const opt_have_power8 = b.option(bool, "have-power8", "") orelse false;
    const opt_use_rtti = b.option(bool, "use-rtti", "") orelse (optimize == .Debug);
    const opt_assert_status_checked = b.option(bool, "assert-status-checked", "") orelse false;
    const opt_use_lto = b.option(bool, "use-lto", "") orelse (optimize != .Debug);
    const opt_no_threeway_crc32c = b.option(bool, "no-threeway=crc32c", "") orelse true;
    const opt_with_windows_utf8_filenames = b.option(bool, "with-windows-utf8-filenames", "") orelse false;
    const opt_have_fallocate = b.option(bool, "have-fallocate", "") orelse (target.result.os.tag == .linux);
    const opt_have_sync_file_range_write = b.option(bool, "have-sync-file-range-write", "") orelse false;
    const opt_have_pthread_mutex_adaptive_np = b.option(bool, "have-pthread-mutex-adaptive-np", "") orelse (target.result.os.tag == .linux);
    const opt_have_malloc_usable_size = b.option(bool, "have-malloc-usable-size", "") orelse false;
    const opt_have_sched_getcpu = b.option(bool, "have-sched-getcpu", "") orelse false;
    const opt_have_auxv_getauxval = b.option(bool, "have-auxv-getauxval", "") orelse false;
    const opt_have_fullfsync = b.option(bool, "have-fullfsync", "") orelse false;

    const step_install = b.getInstallStep();
    const step_check = b.step("check", "Compile without emitting artifacts");
    const step_test = b.step("test", "Run the tests");

    const dep_rocksdb = b.dependency("rocksdb", .{});

    var librocksdb_compile_flags = std.ArrayList([]const u8).empty;
    try librocksdb_compile_flags.append(b.allocator, "-std=c++20");
    try librocksdb_compile_flags.append(b.allocator, "-Wno-invalid-offsetof");
    try librocksdb_compile_flags.append(b.allocator, if (opt_use_rtti) "-DROCKSDB_USE_RTTI" else "-fno-rtti");

    if (optimize != .Debug)
        try librocksdb_compile_flags.append(b.allocator, "-DNDEBUG");
    if (opt_has_altivec)
        try librocksdb_compile_flags.append(b.allocator, "-DHAS_ALTIVEC");
    if (opt_have_power8)
        try librocksdb_compile_flags.append(b.allocator, "-DHAVE_POWER8");
    if (opt_linkage == .dynamic)
        try librocksdb_compile_flags.append(b.allocator, "-DROCKSDB_DLL");
    if (opt_assert_status_checked)
        try librocksdb_compile_flags.appendSlice(b.allocator, &.{ "-fno-elide-constructors", "-DROCKSDB_ASSERT_STATUS_CHECKED" });
    if (opt_no_threeway_crc32c)
        try librocksdb_compile_flags.append(b.allocator, "-DNO_THREEWAY_CRC32C");
    if (opt_with_windows_utf8_filenames)
        try librocksdb_compile_flags.append(b.allocator, "-DROCKSDB_WINDOWS_UTF8_FILENAMES");
    if (opt_have_fallocate)
        try librocksdb_compile_flags.append(b.allocator, "-DROCKSDB_FALLOCATE_PRESENT");
    if (opt_have_sync_file_range_write)
        try librocksdb_compile_flags.append(b.allocator, "-DROCKSDB_RANGESYNC_PRESENT");
    if (opt_have_pthread_mutex_adaptive_np)
        try librocksdb_compile_flags.append(b.allocator, "-DROCKSDB_PTHREAD_ADAPTIVE_MUTEX");
    if (opt_have_malloc_usable_size)
        try librocksdb_compile_flags.append(b.allocator, "-DROCKSDB_MALLOC_USABLE_SIZE");
    if (opt_have_sched_getcpu)
        try librocksdb_compile_flags.append(b.allocator, "-DROCKSDB_SCHED_GETCPU_PRESENT");
    if (opt_have_auxv_getauxval)
        try librocksdb_compile_flags.append(b.allocator, "-DROCKSDB_AUXV_GETAUXVAL_PRESENT");
    if (opt_have_fullfsync)
        try librocksdb_compile_flags.append(b.allocator, "-DHAVE_FULLFSYNC");

    // target specific
    {
        switch (target.result.abi) {
            .gnu => try librocksdb_compile_flags.append(b.allocator, "-fno-builtin-memcmp"),
            .msvc => try librocksdb_compile_flags.append(b.allocator, "/Od /RTC1 /Gm-"),
            else => {},
        }

        switch (target.result.os.tag) {
            .ios => try librocksdb_compile_flags.appendSlice(b.allocator, &.{ "-DOS_MACOSX", "-DIOS_CROSS_COMPILE" }),
            .linux => try librocksdb_compile_flags.append(b.allocator, "-DOS_LINUX"),
            .solaris => try librocksdb_compile_flags.append(b.allocator, "-DOS_SOLARIS"),
            .freebsd => try librocksdb_compile_flags.append(b.allocator, "-DOS_FREEBSD"),
            .netbsd => try librocksdb_compile_flags.append(b.allocator, "-DOS_NETBSD"),
            .openbsd => try librocksdb_compile_flags.append(b.allocator, "-DOS_OPENBSD"),
            .dragonfly => try librocksdb_compile_flags.append(b.allocator, "-DOS_DRAGONFLYBSD"),
            //.android => try cpp_compile_flags.append(b.allocator, "-DOS_ANDROID"),
            .windows => try librocksdb_compile_flags.appendSlice(b.allocator, &.{ "-DWIN32", "-DOS_WIN", "-D_MBCS", "-DWIN64", "-DNOMINMAX" }),
            else => {},
        }
        if (target.result.os.tag.isDarwin())
            try librocksdb_compile_flags.append(b.allocator, "-DOS_MACOSX");
        if (target.result.os.tag != .windows)
            try librocksdb_compile_flags.appendSlice(b.allocator, &.{ "-DROCKSDB_PLATFORM_POSIX", "-DROCKSDB_LIB_IO_POSIX" });
    }

    const gen_build_version = b.addSystemCommand(&.{"sed"});
    {
        const build_date = "";
        const git_sha = "9e14d06143dae681d252cb0434bea667995eaede"; //$(shell git rev-parse HEAD 2>/dev/null)
        const git_tag = ""; //$(shell git symbolic-ref -q --short HEAD 2> /dev/null || git describe --tags --exact-match 2>/dev/null)
        const git_mod = 0; //$(shell git diff-index HEAD --quiet 2>/dev/null; echo $$?)
        const git_date = "2025-11-24 10:48:09"; //$(shell git log -1 --date=format:"%Y-%m-%d %T" --format="%ad" 2>/dev/null)
        const plugin_builtins = "";
        const plugin_externals = "";

        gen_build_version.addArgs(&.{ "-e", b.fmt("s/@GIT_SHA@/{s}/", .{git_sha}) });
        gen_build_version.addArgs(&.{ "-e", b.fmt("s:@GIT_TAG@:{s}:", .{git_tag}) });
        gen_build_version.addArgs(&.{ "-e", b.fmt("s/@GIT_MOD@/{d}/", .{git_mod}) });
        gen_build_version.addArgs(&.{ "-e", b.fmt("s/@BUILD_DATE@/{s}/", .{build_date}) });
        gen_build_version.addArgs(&.{ "-e", b.fmt("s/@GIT_DATE@/{s}/", .{git_date}) });
        gen_build_version.addArgs(&.{ "-e", b.fmt("s/@ROCKSDB_PLUGIN_BUILTINS@/{s}/", .{plugin_builtins}) });
        gen_build_version.addArgs(&.{ "-e", b.fmt("s/@ROCKSDB_PLUGIN_EXTERNS@/{s}/", .{plugin_externals}) });
        gen_build_version.addFileArg(dep_rocksdb.path("util/build_version.cc.in"));
    }
    const build_version_cc = gen_build_version.captureStdOut();

    const mod_rocksdb = b.addModule("rocksdb", .{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
        .sanitize_c = opt_sanitize_c,
        .sanitize_thread = opt_sanitize_thread,
        .strip = optimize != .Debug,
    });
    mod_rocksdb.addIncludePath(dep_rocksdb.path("include"));
    mod_rocksdb.addIncludePath(dep_rocksdb.path(""));
    mod_rocksdb.addCSourceFiles(.{
        .language = .cpp,
        .root = dep_rocksdb.path(""),
        .flags = librocksdb_compile_flags.items,
        .files = &.{
            "cache/cache.cc",
            "cache/cache_entry_roles.cc",
            "cache/cache_key.cc",
            "cache/cache_helpers.cc",
            "cache/cache_reservation_manager.cc",
            "cache/charged_cache.cc",
            "cache/clock_cache.cc",
            "cache/lru_cache.cc",
            "cache/compressed_secondary_cache.cc",
            "cache/secondary_cache.cc",
            "cache/secondary_cache_adapter.cc",
            "cache/sharded_cache.cc",
            "cache/tiered_secondary_cache.cc",
            "db/arena_wrapped_db_iter.cc",
            "db/attribute_group_iterator_impl.cc",
            "db/blob/blob_contents.cc",
            "db/blob/blob_fetcher.cc",
            "db/blob/blob_file_addition.cc",
            "db/blob/blob_file_builder.cc",
            "db/blob/blob_file_cache.cc",
            "db/blob/blob_file_garbage.cc",
            "db/blob/blob_file_meta.cc",
            "db/blob/blob_file_reader.cc",
            "db/blob/blob_garbage_meter.cc",
            "db/blob/blob_log_format.cc",
            "db/blob/blob_log_sequential_reader.cc",
            "db/blob/blob_log_writer.cc",
            "db/blob/blob_source.cc",
            "db/blob/prefetch_buffer_collection.cc",
            "db/builder.cc",
            "db/c.cc",
            "db/coalescing_iterator.cc",
            "db/column_family.cc",
            "db/compaction/compaction.cc",
            "db/compaction/compaction_iterator.cc",
            "db/compaction/compaction_job.cc",
            "db/compaction/compaction_picker.cc",
            "db/compaction/compaction_picker_fifo.cc",
            "db/compaction/compaction_picker_level.cc",
            "db/compaction/compaction_picker_universal.cc",
            "db/compaction/compaction_service_job.cc",
            "db/compaction/compaction_state.cc",
            "db/compaction/compaction_outputs.cc",
            "db/compaction/sst_partitioner.cc",
            "db/compaction/subcompaction_state.cc",
            "db/convenience.cc",
            "db/db_filesnapshot.cc",
            "db/db_impl/compacted_db_impl.cc",
            "db/db_impl/db_impl.cc",
            "db/db_impl/db_impl_compaction_flush.cc",
            "db/db_impl/db_impl_debug.cc",
            "db/db_impl/db_impl_experimental.cc",
            "db/db_impl/db_impl_files.cc",
            "db/db_impl/db_impl_follower.cc",
            "db/db_impl/db_impl_open.cc",
            "db/db_impl/db_impl_readonly.cc",
            "db/db_impl/db_impl_secondary.cc",
            "db/db_impl/db_impl_write.cc",
            "db/db_info_dumper.cc",
            "db/db_iter.cc",
            "db/dbformat.cc",
            "db/error_handler.cc",
            "db/event_helpers.cc",
            "db/experimental.cc",
            "db/external_sst_file_ingestion_job.cc",
            "db/file_indexer.cc",
            "db/flush_job.cc",
            "db/flush_scheduler.cc",
            "db/forward_iterator.cc",
            "db/import_column_family_job.cc",
            "db/internal_stats.cc",
            "db/logs_with_prep_tracker.cc",
            "db/log_reader.cc",
            "db/log_writer.cc",
            "db/malloc_stats.cc",
            "db/manifest_ops.cc",
            "db/memtable.cc",
            "db/memtable_list.cc",
            "db/merge_helper.cc",
            "db/merge_operator.cc",
            "db/multi_scan.cc",
            "db/output_validator.cc",
            "db/periodic_task_scheduler.cc",
            "db/range_del_aggregator.cc",
            "db/range_tombstone_fragmenter.cc",
            "db/repair.cc",
            "db/seqno_to_time_mapping.cc",
            "db/snapshot_impl.cc",
            "db/table_cache.cc",
            "db/table_properties_collector.cc",
            "db/transaction_log_impl.cc",
            "db/trim_history_scheduler.cc",
            "db/version_builder.cc",
            "db/version_edit.cc",
            "db/version_edit_handler.cc",
            "db/version_set.cc",
            "db/wal_edit.cc",
            "db/wal_manager.cc",
            "db/wide/wide_column_serialization.cc",
            "db/wide/wide_columns.cc",
            "db/wide/wide_columns_helper.cc",
            "db/write_batch.cc",
            "db/write_batch_base.cc",
            "db/write_controller.cc",
            "db/write_stall_stats.cc",
            "db/write_thread.cc",
            "env/composite_env.cc",
            "env/env.cc",
            "env/env_chroot.cc",
            "env/env_encryption.cc",
            "env/env_posix.cc",
            "env/file_system.cc",
            "env/fs_on_demand.cc",
            "env/fs_posix.cc",
            "env/fs_remap.cc",
            "env/file_system_tracer.cc",
            "env/io_posix.cc",
            "env/mock_env.cc",
            "env/unique_id_gen.cc",
            "file/delete_scheduler.cc",
            "file/file_prefetch_buffer.cc",
            "file/file_util.cc",
            "file/filename.cc",
            "file/line_file_reader.cc",
            "file/random_access_file_reader.cc",
            "file/read_write_util.cc",
            "file/readahead_raf.cc",
            "file/sequence_file_reader.cc",
            "file/sst_file_manager_impl.cc",
            "file/writable_file_writer.cc",
            "logging/auto_roll_logger.cc",
            "logging/event_logger.cc",
            "logging/log_buffer.cc",
            "memory/arena.cc",
            "memory/concurrent_arena.cc",
            "memory/jemalloc_nodump_allocator.cc",
            "memory/memkind_kmem_allocator.cc",
            "memory/memory_allocator.cc",
            "memtable/alloc_tracker.cc",
            "memtable/hash_linklist_rep.cc",
            "memtable/hash_skiplist_rep.cc",
            "memtable/skiplistrep.cc",
            "memtable/vectorrep.cc",
            "memtable/wbwi_memtable.cc",
            "memtable/write_buffer_manager.cc",
            "monitoring/histogram.cc",
            "monitoring/histogram_windowing.cc",
            "monitoring/in_memory_stats_history.cc",
            "monitoring/instrumented_mutex.cc",
            "monitoring/iostats_context.cc",
            "monitoring/perf_context.cc",
            "monitoring/perf_level.cc",
            "monitoring/persistent_stats_history.cc",
            "monitoring/statistics.cc",
            "monitoring/thread_status_impl.cc",
            "monitoring/thread_status_updater.cc",
            "monitoring/thread_status_updater_debug.cc",
            "monitoring/thread_status_util.cc",
            "monitoring/thread_status_util_debug.cc",
            "options/cf_options.cc",
            "options/configurable.cc",
            "options/customizable.cc",
            "options/db_options.cc",
            "options/offpeak_time_info.cc",
            "options/options.cc",
            "options/options_helper.cc",
            "options/options_parser.cc",
            "port/mmap.cc",
            "port/port_posix.cc",
            "port/win/env_default.cc",
            "port/win/env_win.cc",
            "port/win/io_win.cc",
            "port/win/port_win.cc",
            "port/win/win_logger.cc",
            "port/win/win_thread.cc",
            "port/stack_trace.cc",
            "table/adaptive/adaptive_table_factory.cc",
            "table/block_based/binary_search_index_reader.cc",
            "table/block_based/block.cc",
            "table/block_based/block_based_table_builder.cc",
            "table/block_based/block_based_table_factory.cc",
            "table/block_based/block_based_table_iterator.cc",
            "table/block_based/block_based_table_reader.cc",
            "table/block_based/block_builder.cc",
            "table/block_based/block_cache.cc",
            "table/block_based/block_prefetcher.cc",
            "table/block_based/block_prefix_index.cc",
            "table/block_based/data_block_hash_index.cc",
            "table/block_based/data_block_footer.cc",
            "table/block_based/filter_block_reader_common.cc",
            "table/block_based/filter_policy.cc",
            "table/block_based/flush_block_policy.cc",
            "table/block_based/full_filter_block.cc",
            "table/block_based/hash_index_reader.cc",
            "table/block_based/index_builder.cc",
            "table/block_based/index_reader_common.cc",
            "table/block_based/parsed_full_filter_block.cc",
            "table/block_based/partitioned_filter_block.cc",
            "table/block_based/partitioned_index_iterator.cc",
            "table/block_based/partitioned_index_reader.cc",
            "table/block_based/reader_common.cc",
            "table/block_based/uncompression_dict_reader.cc",
            "table/block_fetcher.cc",
            "table/cuckoo/cuckoo_table_builder.cc",
            "table/cuckoo/cuckoo_table_factory.cc",
            "table/cuckoo/cuckoo_table_reader.cc",
            "table/external_table.cc",
            "table/format.cc",
            "table/get_context.cc",
            "table/iterator.cc",
            "table/merging_iterator.cc",
            "table/compaction_merging_iterator.cc",
            "table/meta_blocks.cc",
            "table/persistent_cache_helper.cc",
            "table/plain/plain_table_bloom.cc",
            "table/plain/plain_table_builder.cc",
            "table/plain/plain_table_factory.cc",
            "table/plain/plain_table_index.cc",
            "table/plain/plain_table_key_coding.cc",
            "table/plain/plain_table_reader.cc",
            "table/sst_file_dumper.cc",
            "table/sst_file_reader.cc",
            "table/sst_file_writer.cc",
            "table/table_factory.cc",
            "table/table_properties.cc",
            "table/two_level_iterator.cc",
            "table/unique_id.cc",
            "test_util/sync_point.cc",
            "test_util/sync_point_impl.cc",
            "test_util/transaction_test_util.cc",
            "tools/dump/db_dump_tool.cc",
            "trace_replay/trace_record_handler.cc",
            "trace_replay/trace_record_result.cc",
            "trace_replay/trace_record.cc",
            "trace_replay/trace_replay.cc",
            "trace_replay/block_cache_tracer.cc",
            "trace_replay/io_tracer.cc",
            "util/async_file_reader.cc",
            "util/auto_tune_compressor.cc",
            //"util/build_version.cc",
            "util/cleanable.cc",
            "util/coding.cc",
            "util/compaction_job_stats_impl.cc",
            "util/comparator.cc",
            "util/compression.cc",
            "util/compression_context_cache.cc",
            "util/concurrent_task_limiter_impl.cc",
            "util/crc32c.cc",
            "util/crc32c_arm64.cc",
            "util/data_structure.cc",
            "util/dynamic_bloom.cc",
            "util/hash.cc",
            "util/murmurhash.cc",
            "util/random.cc",
            "util/rate_limiter.cc",
            "util/ribbon_config.cc",
            "util/slice.cc",
            "util/file_checksum_helper.cc",
            "util/simple_mixed_compressor.cc",
            "util/status.cc",
            "util/stderr_logger.cc",
            "util/string_util.cc",
            "util/thread_local.cc",
            "util/threadpool_imp.cc",
            "util/udt_util.cc",
            "util/write_batch_util.cc",
            "util/xxhash.cc",
            "utilities/agg_merge/agg_merge.cc",
            "utilities/backup/backup_engine.cc",
            "utilities/blob_db/blob_compaction_filter.cc",
            "utilities/blob_db/blob_db.cc",
            "utilities/blob_db/blob_db_impl.cc",
            "utilities/blob_db/blob_db_impl_filesnapshot.cc",
            "utilities/blob_db/blob_file.cc",
            "utilities/cache_dump_load.cc",
            "utilities/cache_dump_load_impl.cc",
            "utilities/cassandra/cassandra_compaction_filter.cc",
            "utilities/cassandra/format.cc",
            "utilities/cassandra/merge_operator.cc",
            "utilities/checkpoint/checkpoint_impl.cc",
            "utilities/compaction_filters.cc",
            "utilities/compaction_filters/remove_emptyvalue_compactionfilter.cc",
            "utilities/convenience/info_log_finder.cc",
            "utilities/counted_fs.cc",
            "utilities/debug.cc",
            "utilities/env_mirror.cc",
            "utilities/env_timed.cc",
            "utilities/fault_injection_env.cc",
            "utilities/fault_injection_fs.cc",
            "utilities/fault_injection_secondary_cache.cc",
            "utilities/leveldb_options/leveldb_options.cc",
            "utilities/memory/memory_util.cc",
            "utilities/merge_operators.cc",
            "utilities/merge_operators/max.cc",
            "utilities/merge_operators/put.cc",
            "utilities/merge_operators/sortlist.cc",
            "utilities/merge_operators/string_append/stringappend.cc",
            "utilities/merge_operators/string_append/stringappend2.cc",
            "utilities/merge_operators/uint64add.cc",
            "utilities/merge_operators/bytesxor.cc",
            "utilities/object_registry.cc",
            "utilities/option_change_migration/option_change_migration.cc",
            "utilities/options/options_util.cc",
            "utilities/persistent_cache/block_cache_tier.cc",
            "utilities/persistent_cache/block_cache_tier_file.cc",
            "utilities/persistent_cache/block_cache_tier_metadata.cc",
            "utilities/persistent_cache/persistent_cache_tier.cc",
            "utilities/persistent_cache/volatile_tier_impl.cc",
            "utilities/secondary_index/secondary_index_iterator.cc",
            "utilities/secondary_index/simple_secondary_index.cc",
            "utilities/simulator_cache/cache_simulator.cc",
            "utilities/simulator_cache/sim_cache.cc",
            "utilities/table_properties_collectors/compact_for_tiering_collector.cc",
            "utilities/table_properties_collectors/compact_on_deletion_collector.cc",
            "utilities/trace/file_trace_reader_writer.cc",
            "utilities/trace/replayer_impl.cc",
            "utilities/transactions/lock/lock_manager.cc",
            "utilities/transactions/lock/point/point_lock_tracker.cc",
            "utilities/transactions/lock/point/point_lock_manager.cc",
            "utilities/transactions/optimistic_transaction.cc",
            "utilities/transactions/optimistic_transaction_db_impl.cc",
            "utilities/transactions/pessimistic_transaction.cc",
            "utilities/transactions/pessimistic_transaction_db.cc",
            "utilities/transactions/snapshot_checker.cc",
            "utilities/transactions/transaction_base.cc",
            "utilities/transactions/transaction_db_mutex_impl.cc",
            "utilities/transactions/transaction_util.cc",
            "utilities/transactions/write_prepared_txn.cc",
            "utilities/transactions/write_prepared_txn_db.cc",
            "utilities/transactions/write_unprepared_txn.cc",
            "utilities/transactions/write_unprepared_txn_db.cc",
            "utilities/ttl/db_ttl_impl.cc",
            "utilities/types_util.cc",
            "utilities/wal_filter.cc",
            "utilities/write_batch_with_index/write_batch_with_index.cc",
            "utilities/write_batch_with_index/write_batch_with_index_internal.cc",
        },
    });
    mod_rocksdb.addCSourceFile(.{
        .language = .cpp,
        .flags = librocksdb_compile_flags.items,
        .file = build_version_cc,
    });

    const lib_rocksdb = b.addLibrary(.{
        .name = "rocksdb",
        .root_module = mod_rocksdb,
        .linkage = opt_linkage,
    });
    lib_rocksdb.lto = if (opt_use_lto) .full else .none;

    b.addNamedLazyPath("include", dep_rocksdb.path("include"));

    const mod_zrocksdb = b.addModule("zrocksdb", .{
        .root_source_file = b.path("zrocksdb.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod_zrocksdb.addIncludePath(dep_rocksdb.path("include"));
    mod_zrocksdb.linkLibrary(lib_rocksdb);

    step_check.dependOn(&lib_rocksdb.step);
    step_install.dependOn(&b.addInstallArtifact(lib_rocksdb, .{}).step);

    // Tests
    {
        const test_write_files = b.addWriteFiles();
        const ctx: TestContext = .{
            .target = target,
            .optimize = optimize,
            .mod_zrocksdb = mod_zrocksdb,
            .cwd = test_write_files.getDirectory(),
            .step_check = step_check,
            .step_test = step_test,
        };
        try add_test(b, "basic-usage", b.path("tests/basic-usage.zig"), ctx);
    }
}

const TestContext = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    mod_zrocksdb: *std.Build.Module,
    step_check: *std.Build.Step,
    step_test: *std.Build.Step,
    cwd: std.Build.LazyPath,
};

fn add_test(b: *std.Build, name: []const u8, source: std.Build.LazyPath, ctx: TestContext) !void {
    const exe_test = b.addTest(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = source,
            .target = ctx.target,
            .optimize = ctx.optimize,
            .imports = &.{
                .{ .name = "zrocksdb", .module = ctx.mod_zrocksdb },
            },
            .link_libc = true,
        }),
    });
    ctx.step_check.dependOn(&exe_test.step);

    const run_test = b.addRunArtifact(exe_test);
    run_test.setCwd(ctx.cwd);
    ctx.step_test.dependOn(&run_test.step);
}

const std = @import("std");
