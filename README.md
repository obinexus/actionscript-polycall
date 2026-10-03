# actionscript-polycall

ActionScript 3 binding for [Polycall](https://github.com/obinexus/polycall)
(binding ABI v1, Polycall >= 1.1.0).

## Where it runs — and where it does not

| AS3 runtime | status |
| --- | --- |
| **Apache Royale → Node.js** (`asnodec` compiles AS3 to JavaScript; Apache-2.0, from npm) | **supported and tested** (Linux x86-64; Windows x64 with both the MSVC `polycall.dll` and the UCRT64 `libpolycall.dll`). The AS3 classes call the **real native core** in-process through the [koffi](https://koffi.dev) FFI. |
| Adobe / HARMAN AIR, Flash Player | **not supported, not tested.** They are proprietary runtimes whose licence terms must be accepted; AIR reaches C only through an AIR Native Extension (ANE) built with the AIR SDK (`FlashRuntimeExtensions.h`). No ANE is provided. |
| Royale in a browser | not supported: a browser cannot load a native library. |

## API (`org.obinexus.polycall`)

```actionscript
import org.obinexus.polycall.*;

Polycall.runConfig("actionscript-polycallrc");              // polycall_ffi_run_config(path, 1)
var out:String = Polycall.invoke("127.0.0.1:8084", "inventory", "get", '{"item_id":"widget-a"}');

var inbox:Peer = Peer.open("as3-inbox", "127.0.0.1:0");
var outbox:Peer = Peer.open("as3-outbox");                   // no bind = send-only
outbox.send(inbox.endpoint, "hello", "m-1");                 // String (UTF-8) or Uint8Array
var m:PeerMessage = inbox.recv(5000);                        // m.from, m.id, m.payload (Uint8Array), m.text

inbox.recvAsync(Polycall.FOREVER, function(err:PolycallError, msg:PeerMessage):void { ... });
inbox.cancel();                                              // wakes it: err.status == Polycall.E_CANCELLED
```

| class | members |
| --- | --- |
| `Polycall` | `load(path)`, `libraryPath`, `abiVersion`, `version`, `strerror(code)`, `lastError()`, `runConfig(path, run = true)`, `describe(path)`, `invoke(endpoint, service, operation, inputJson = null, timeoutMs = 5000, outputCapacity = 1 MiB + 1)`, `lastCallLength`, the 19 status constants `OK`, `E_*`, limits, `FOREVER` |
| `Peer` | `open(nodeId, bind = null, token = null)`, `fromHandle(h)`, `handle`, `endpoint`, `nodeId`, `endpointInto(cap)`, `register`, `unregister`, `list(cap)`, `health(cap)`, `ping`, `send`, `recv(timeoutMs, capacity)`, `cancel`, `close`, `recvAsync`, `sendAsync`, `lastLength`, `lastPayloadLength` |
| `PeerMessage` | `from`, `id`, `payload`, `text` |
| `PolycallError` | thrown for every negative status: `status`, `statusName` (`polycall_strerror`), `code`, `detail` (`polycall_last_error`), `operation`, `output` (the remote error object for `invoke`) |
| `PolycallLoadError` | the library cannot be used: `reason` = `not-found`, `missing-symbol` (e.g. a 1.0 library), `abi-mismatch`, `ffi-unavailable` |

Notes:

- `polycall_call` is `Polycall.invoke`: a static method named `call` on a
  class compiled to JavaScript collides with `Function.prototype.call`.
- Too-small caller buffers keep the C semantics: `invoke(..., outputCapacity)`,
  `recv(timeout, capacity)`, `list(cap)`, `health(cap)`, `endpointInto(cap)`
  throw `E_TOO_LARGE` and report the needed size (`lastCallLength`,
  `lastPayloadLength`, `lastLength`); a too-large message stays queued.
- `recvAsync` / `sendAsync` run the core call on a koffi worker thread and
  call back on the main thread, so a receive can block (even
  `Polycall.FOREVER`) while the main thread calls `cancel()` or `close()`.
  The detail of an async failure is recorded by the core on that worker
  thread and is not available; the error carries the status and its name.
- A string containing a NUL character cannot be passed as a C string and is
  refused with `E_INVALID_ARGUMENT` before the core is called.
- Loading: `POLYCALL_LIBRARY`, then `polycall.dll` / `libpolycall.dll`
  (Windows), `libpolycall.so.1` (Linux). `polycall_ffi_abi_version()` is
  checked (== 1) before any other symbol is resolved, and every symbol is
  resolved up front. macOS (`libpolycall.1.dylib`) is not claimed: the core
  has no verified macOS build.
- The library never returns memory to free; every output is copied from a
  caller-owned buffer.

## Build and test

Requires Node.js >= 22, Java 8+ (for the Royale compiler) and the core.

```sh
npm ci                      # koffi + @apache-royale/royale-js (dev)
npm run build               # scripts/build.js (Royale, node target) -> build/example, build/test
node build/example/bin/js-release/index.js
npm test                    # tests/run-tests.js
```

`npm test` compiles `tests/TestMain.as` and `examples/Hello.as` with Royale
(`scripts/build.js` runs the compiler jar exactly as the `asnodec` launcher
does, but without that launcher's `asnodec.bat` step, which current Node.js
refuses to spawn on Windows), starts a `polycall start` runtime, a `polycall daemon start`
daemon and a `polycall peer serve` C node, and runs the AS3 test against the
real library (`POLYCALL_LIBRARY`, `POLYCALL_CLI`): the binding-ABI checklist
(configuration incl. strict/TLS/non-ASCII path, `invoke` against the runtime
and the daemon, peers both ways with exact bytes, 1 MiB / 1 MiB + 1,
registry ownership, duplicates, auth, dead peer, timeouts, handles), payloads
both ways with the C CLI, a blocked `recvAsync` woken by `cancel()`,
`close()` and a message, 150 concurrent `sendAsync` calls (own nodes and one
shared handle), and the loader errors (missing / old / ABI-2 / partial
library). Exit 77 = something needed is missing (SKIP), never a pass. A
prebuilt compiler output can be reused with `AS3_POLYCALL_BUILD_DIR`
(`npm ci --omit=dev` then needs no Java).

`package.json` is a private build manifest (Royale + koffi); this binding is
not published to any registry.

Configuration override: [`actionscript-polycallrc`](actionscript-polycallrc)
(the core's own grammar, `polycall config validate`).

## License

MIT — OBINexus Computing / Nnamdi Michael Okpala
