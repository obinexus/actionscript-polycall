# ActionScript adapter

`org/obinexus/polycall/NativeCore.as` loads the native core with koffi
(Node.js, via Apache Royale's `asnodec`) and declares every binding-ABI-v1
function with its exact `polycall.h` prototype. `Polycall` and `Peer` turn
statuses into `PolycallError` (status, `polycall_strerror` name,
`polycall_last_error` detail); outputs are copied out of caller-owned
buffers. `Polycall.runConfig(path)` is `polycall_ffi_run_config(path, 1)`.
No configuration parsing, no transport of its own.
