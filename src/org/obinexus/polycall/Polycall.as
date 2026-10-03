package org.obinexus.polycall
{
    /**
     * ActionScript 3 binding for Polycall (binding ABI v1, Polycall >= 1.1.0).
     *
     * Runs where AS3 is compiled to JavaScript for Node.js (Apache Royale
     * `asnodec`) and calls the REAL native core through koffi. Failures throw
     * PolycallError (status, name, detail); a library that cannot be used
     * throws PolycallLoadError before any call reaches it. The library never
     * returns memory to free: every output is copied out of a caller-owned
     * buffer.
     *
     *   Polycall.runConfig("actionscript-polycallrc");   // = polycall_ffi_run_config(path, 1)
     *   var out:String = Polycall.invoke("127.0.0.1:8084", "inventory", "get", '{"item_id":"widget-a"}');
     *   var peer:Peer = Peer.open("as3-node", "127.0.0.1:0");
     */
    public class Polycall
    {
        public static const OK:int = 0;
        public static const E_INVALID_ARGUMENT:int = -1;
        public static const E_NO_MEMORY:int = -2;
        public static const E_INVALID_HANDLE:int = -3;
        public static const E_TIMEOUT:int = -4;
        public static const E_TRANSPORT:int = -5;
        public static const E_PROTOCOL:int = -6;
        public static const E_NOT_FOUND:int = -7;
        public static const E_AUTH:int = -8;
        public static const E_REMOTE:int = -9;
        public static const E_TOO_LARGE:int = -10;
        public static const E_BUSY:int = -11;
        public static const E_CANCELLED:int = -12;
        public static const E_CONFIG:int = -13;
        public static const E_ADDRESS_IN_USE:int = -14;
        public static const E_UNSUPPORTED:int = -15;
        public static const E_PERMISSION:int = -16;
        public static const E_CLOSED:int = -17;
        public static const E_INTERNAL:int = -18;

        public static const ABI_VERSION:int = 1;
        public static const PEER_ID_MAX:int = 64;
        public static const MESSAGE_ID_MAX:int = 64;
        public static const ENDPOINT_MAX:int = 128;
        public static const PEER_MAX_PAYLOAD:uint = 1048576;
        public static const CALL_MAX_OUTPUT:uint = 1048576;
        /** recv timeout: wait until a message, cancel or close */
        public static const FOREVER:uint = 0xFFFFFFFF;

        /**
         * Load and verify the core now (otherwise the first call does). path
         * overrides POLYCALL_LIBRARY and the platform default names.
         */
        public static function load(path:String = null):void
        {
            NativeCore.load(path);
        }

        /** the loaded library: its path */
        public static function get libraryPath():String
        {
            return NativeCore.load().path;
        }

        public static function get abiVersion():int
        {
            return int(NativeCore.load().fn["polycall_ffi_abi_version"]());
        }

        public static function get version():String
        {
            return NativeCore.load().version;
        }

        /** static name of a status code, e.g. "POLYCALL_E_TIMEOUT: deadline exceeded" */
        public static function strerror(status:int):String
        {
            return NativeCore.load().strerror(status);
        }

        /** detail of the most recent failure on this thread */
        public static function lastError():String
        {
            return NativeCore.load().lastError();
        }

        /** throw PolycallError for a negative status, else return it */
        internal static function check(status:int, operation:String, output:String = null):int
        {
            if (status < 0) {
                var core:NativeCore = NativeCore.load();
                throw new PolycallError(status, core.strerror(status), core.lastError(), operation, output);
            }
            return status;
        }

        /** argument the C API cannot take: E_INVALID_ARGUMENT before the core is called */
        internal static function reject(operation:String, detail:String):void
        {
            throw new PolycallError(E_INVALID_ARGUMENT, NativeCore.load().strerror(E_INVALID_ARGUMENT), detail, operation);
        }

        /** a string argument for a const char * parameter (null stays NULL) */
        internal static function cstr(s:String, what:String, operation:String):String
        {
            if (s != null && s.indexOf(String.fromCharCode(0)) >= 0) reject(operation, what + " contains a NUL character");
            return s;
        }

        /**
         * Validate one configuration file with the core's grammar.
         * run = true (default): exactly polycall_ffi_run_config(path, 1) --
         * unknown keys are errors and tls_enabled=true is E_UNSUPPORTED.
         */
        public static function runConfig(path:String, run:Boolean = true):void
        {
            var core:NativeCore = NativeCore.load();
            check(int(core.fn["polycall_ffi_run_config"](cstr(path, "config_path", "runConfig"), run ? 1 : 0)), "runConfig");
        }

        /** JSON description of a configuration file (polycall_ffi_describe) */
        public static function describe(path:String):String
        {
            var core:NativeCore = NativeCore.load();
            var p:String = cstr(path, "config_path", "describe");
            var n:int = check(int(core.fn["polycall_ffi_describe"](p, null, 0)), "describe");
            var buf:Uint8Array = new Uint8Array(n + 1);
            n = check(int(core.fn["polycall_ffi_describe"](p, buf, n + 1)), "describe");
            return NativeCore.text(buf, n);
        }

        /**
         * polycall_call(): one polycall_rpc round trip (never retried). Named
         * invoke() because a static method called `call` on a class compiled
         * to JavaScript collides with Function.prototype.call. Returns the output
         * JSON; a remote failure throws PolycallError whose `output` is the
         * error object. inputJson null is sent as null. outputCapacity is the
         * caller buffer (default 1 MiB): too small -> E_TOO_LARGE.
         */
        public static function invoke(endpoint:String, service:String, operation:String, inputJson:String = null,
                                    timeoutMs:uint = 5000, outputCapacity:uint = 1048577):String
        {
            var core:NativeCore = NativeCore.load();
            var out:Uint8Array = new Uint8Array(outputCapacity);
            var len:Array = [0];
            var st:int = int(core.fn["polycall_call"](cstr(endpoint, "endpoint", "call"), cstr(service, "service", "call"),
                cstr(operation, "operation", "call"), cstr(inputJson, "input_json", "call"), timeoutMs,
                out, outputCapacity, len));
            var text:String = outputCapacity > 0 ? NativeCore.cstring(out) : "";
            lastCallLength = uint(len[0]);
            check(st, "call " + service + "." + operation, text);
            return text;
        }

        /** out_len of the most recent invoke(): output length, or the size needed on E_TOO_LARGE */
        public static var lastCallLength:uint = 0;
    }
}
