# zrocksdb

[RocksDB](https://github.com/facebook/rocksdb) built with [Zig](https://ziglang.org/).

This project is still under development, and is not recommended for production use at this stage.
Contributions are welcome.

This does not yet provide a Zig wrapper for using the RocksDB API.
Currently provides:
- A Zig module `zrocksdb` and access to the C API through it.
- The `rocksdb` static/shared library.
- Access to the RocksDB `include/` directory via the named lazypath `include`.
- Support for [snappy](https://github.com/google/snappy) compression library.

## Dependencies

### Required

- [Zig](https://ziglang.org/) 0.15.2

## Compatibility

Thus far only tested the following platforms:
- x86_64-linux-gnu

## TODO

- [x] Build `rocksdb` library.
- [x] `zrocksdb` module providing access to the C API.
- [ ] `zrocksdb` module providing a Zig API.
- [ ] Build and run the RocksDB tests.
- Integrate the compression libraries that RocksDB supports:
  - [ ] zlib
  - [ ] bzip2
  - [ ] lz4
  - [x] snappy
  - [ ] zstandard
