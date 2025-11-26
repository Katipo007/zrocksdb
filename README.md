# zrocksdb

[RocksDB](https://github.com/facebook/rocksdb) built with [Zig](https://ziglang.org/).

This is project is still under development, and is not recommended for production use at this stage.
Contributions are welcome.

This does not yet provide a Zig wrapper for using the rocksdb API.
Currently provides:
- A Zig module `zrocksdb`.
- The `rocksdb` static/shared library.
- Access to the rocksdb `include/` directory via the named lazypath `include`.

## Dependencies

### Required

- [Zig](https://ziglang.org/) 0.15.2

## Compatability
Thus far only tested the following platforms:
- x86_64-linux-gnu

## TODO
- Zig wrapper for the C API.
- Build and run the rocksdb tests.
- Integrate the compression libraries that RocksDB supports.