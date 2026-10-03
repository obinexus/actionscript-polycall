package org.obinexus.polycall
{
    /**
     * The native Polycall core (binding ABI v1), reached from ActionScript 3
     * compiled to JavaScript for Node.js (Apache Royale, `asnodec`) through
     * the koffi FFI. Internal: the public API is Polycall / Peer.
     *
     * Every member of a JavaScript object (koffi, the library, Buffer,
     * process) is accessed with bracket notation so the Closure release
     * build cannot rename it.
     *
     * Loading: POLYCALL_LIBRARY first, then polycall.dll / libpolycall.dll
     * (Windows), libpolycall.so.1 (Linux), libpolycall.1.dylib (macOS, not
     * claimed). polycall_ffi_abi_version is resolved and checked (== 1)
     * before every other symbol is resolved; failures are a
     * PolycallLoadError, never a crash at first use.
     */
    internal class NativeCore
    {
        public static const ABI_VERSION:int = 1;

        private static var current:NativeCore = null;
        private static var currentKey:String = null;

        /** prototypes, exactly as in polycall.h (strings as const char *) */
        private static const PROTOTYPES:Object = {
            "polycall_ffi_abi_version": "int polycall_ffi_abi_version(void)",
            "polycall_ffi_version": "int polycall_ffi_version(uint8_t *buf, int len)",
            "polycall_strerror": "const char *polycall_strerror(int status)",
            "polycall_last_error": "int polycall_last_error(uint8_t *buf, size_t cap)",
            "polycall_ffi_run_config": "int polycall_ffi_run_config(const char *config_path, int run)",
            "polycall_ffi_describe": "int polycall_ffi_describe(const char *config_path, uint8_t *buf, int len)",
            "polycall_call": "int polycall_call(const char *endpoint, const char *service, const char *operation, const char *input_json, uint32_t timeout_ms, uint8_t *out, size_t out_cap, _Out_ size_t *out_len)",
            "polycall_peer_open": "int polycall_peer_open(const char *node_id, const char *bind_endpoint, const char *auth_token, _Out_ int32_t *out_handle)",
            "polycall_peer_close": "int polycall_peer_close(int32_t h)",
            "polycall_peer_endpoint": "int polycall_peer_endpoint(int32_t h, uint8_t *buf, size_t cap)",
            "polycall_peer_node_id": "int polycall_peer_node_id(int32_t h, uint8_t *buf, size_t cap)",
            "polycall_peer_register": "int polycall_peer_register(int32_t h, const char *peer_id, const char *endpoint)",
            "polycall_peer_unregister": "int polycall_peer_unregister(int32_t h, const char *peer_id)",
            "polycall_peer_list": "int polycall_peer_list(int32_t h, uint8_t *buf, size_t cap, _Out_ size_t *out_len)",
            "polycall_peer_ping": "int polycall_peer_ping(int32_t h, const char *peer, uint32_t timeout_ms)",
            "polycall_peer_send": "int polycall_peer_send(int32_t h, const char *peer, const uint8_t *payload, size_t len, const char *message_id, uint32_t timeout_ms)",
            "polycall_peer_recv": "int polycall_peer_recv(int32_t h, uint32_t timeout_ms, uint8_t *sender, size_t sender_cap, uint8_t *message_id, size_t message_id_cap, uint8_t *payload, size_t payload_cap, _Out_ size_t *payload_len)",
            "polycall_peer_cancel": "int polycall_peer_cancel(int32_t h)",
            "polycall_peer_health": "int polycall_peer_health(int32_t h, uint8_t *buf, size_t cap, _Out_ size_t *out_len)"
        };

        public var path:String;
        public var abi:int;
        public var version:String;
        /** symbol name -> koffi function */
        public var fn:Object;

        public function NativeCore(path:String, fn:Object, abi:int)
        {
            this.path = path;
            this.fn = fn;
            this.abi = abi;
            var buf:Uint8Array = new Uint8Array(32);
            var n:int = fn["polycall_ffi_version"](buf, 32);
            this.version = NativeCore.text(buf, n);
        }

        public static function defaultNames():Array
        {
            var platform:String = String(process["platform"]);
            if (platform == "win32") return ["polycall.dll", "libpolycall.dll"];
            if (platform == "darwin") return ["libpolycall.1.dylib"];
            return ["libpolycall.so.1"];
        }

        /** Load (once per library choice) and verify the core. */
        public static function load(explicitPath:String = null):NativeCore
        {
            var env:Object = process["env"];
            var candidates:Array;
            var explicit:Boolean = true;
            if (explicitPath) candidates = [explicitPath];
            else if (env["POLYCALL_LIBRARY"]) candidates = [String(env["POLYCALL_LIBRARY"])];
            else {
                candidates = defaultNames();
                explicit = false;
            }
            var key:String = candidates.join("|");
            if (current != null && currentKey == key) return current;

            var koffi:Object;
            try {
                koffi = require("koffi");
            } catch (e:Error) {
                throw new PolycallLoadError("(none)", "ffi-unavailable",
                    "the koffi FFI module is not installed (npm install koffi): " + e.message);
            }
            var failures:Array = [];
            for (var i:int = 0; i < candidates.length; i++) {
                var name:String = candidates[i];
                var handle:Object = null;
                try {
                    handle = koffi["load"](name);
                } catch (e2:Error) {
                    failures.push(name + ": " + e2.message);
                    continue;
                }
                var fn:Object = {};
                fn["polycall_ffi_abi_version"] = bind(handle, name, "polycall_ffi_abi_version");
                var abi:int = fn["polycall_ffi_abi_version"]();
                if (abi != ABI_VERSION) {
                    throw new PolycallLoadError(name, "abi-mismatch", "polycall_ffi_abi_version() returned " + abi +
                        ", actionscript-polycall needs " + ABI_VERSION);
                }
                for (var symbol:String in PROTOTYPES) {
                    if (!fn[symbol]) fn[symbol] = bind(handle, name, symbol);
                }
                current = new NativeCore(name, fn, abi);
                currentKey = key;
                return current;
            }
            var searched:String = candidates.join(", ");
            throw new PolycallLoadError(searched, "not-found", "the library could not be loaded (searched " + searched +
                (explicit ? "" : "; set POLYCALL_LIBRARY to its full path") + "): " + failures.join("; "));
        }

        private static function bind(handle:Object, name:String, symbol:String):Object
        {
            try {
                return handle["func"](PROTOTYPES[symbol]);
            } catch (e:Error) {
                throw new PolycallLoadError(name, "missing-symbol", "symbol " + symbol +
                    " is missing: this is not a binding-ABI-v1 library (Polycall >= 1.1.0 is required)");
            }
            return null;
        }

        /** UTF-8 text of buf[0 .. min(n, len - 1)) */
        public static function text(buf:Uint8Array, n:int):String
        {
            if (n < 0) n = 0;
            if (n > buf.length - 1) n = buf.length - 1;
            if (n <= 0) return "";
            return require("buffer")["Buffer"]["from"](buf["buffer"], buf["byteOffset"], n)["toString"]("utf8");
        }

        /** all bytes of buf decoded as UTF-8 */
        public static function decode(buf:Uint8Array):String
        {
            if (buf.length == 0) return "";
            return require("buffer")["Buffer"]["from"](buf["buffer"], buf["byteOffset"], buf.length)["toString"]("utf8");
        }

        /** UTF-8 text up to the first NUL */
        public static function cstring(buf:Uint8Array):String
        {
            var n:int = 0;
            while (n < buf.length && buf[n] != 0) n++;
            return text(buf, n < buf.length ? n : buf.length - 1);
        }

        /** UTF-8 bytes of a string (no NUL) */
        public static function utf8(s:String):Uint8Array
        {
            var b:Object = require("buffer")["Buffer"]["from"](s, "utf8");
            return new Uint8Array(b["buffer"], b["byteOffset"], b["length"]);
        }

        public function strerror(status:int):String
        {
            return String(fn["polycall_strerror"](status));
        }

        public function lastError():String
        {
            var buf:Uint8Array = new Uint8Array(1024);
            var n:int = fn["polycall_last_error"](buf, 1024);
            return text(buf, n);
        }
    }
}
