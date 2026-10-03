package org.obinexus.polycall
{
    /**
     * A Polycall peer node (polycall_peer_*): its own registry and inbox,
     * exchanging payloads directly with other nodes (polycall-peer/1).
     * Failures throw PolycallError.
     *
     * Synchronous methods block the calling thread inside the core. The
     * *Async methods run the same core call on a koffi worker thread and
     * call back(error:PolycallError, result) on the main thread, so a
     * receive can wait (even Polycall.FOREVER) while this thread calls
     * cancel() or close(), which wake it with E_CANCELLED / E_CLOSED. The
     * detail of an async failure is recorded by the core on the worker
     * thread and is not readable from here; the error carries the status
     * and its name.
     */
    public class Peer
    {
        private var _handle:int;

        public function Peer(handle:int)
        {
            _handle = handle;
        }

        /**
         * Open a node. bindEndpoint "host:port" (port 0 = ephemeral), or
         * null for a send-only node; authToken null/"" = no authentication.
         */
        public static function open(nodeId:String, bindEndpoint:String = null, authToken:String = null):Peer
        {
            var core:NativeCore = NativeCore.load();
            var h:Array = [0];
            Polycall.check(int(core.fn["polycall_peer_open"](Polycall.cstr(nodeId, "node_id", "Peer.open"),
                Polycall.cstr(bindEndpoint, "bind_endpoint", "Peer.open"),
                Polycall.cstr(authToken, "auth_token", "Peer.open"), h)), "Peer.open");
            return new Peer(int(h[0]));
        }

        /** a Peer object for an existing handle (e.g. one opened elsewhere in this process) */
        public static function fromHandle(handle:int):Peer
        {
            return new Peer(handle);
        }

        public function get handle():int
        {
            return _handle;
        }

        private static function fn(name:String):Object
        {
            return NativeCore.load().fn[name];
        }

        /** Stop the listener and release the node; a second close throws E_INVALID_HANDLE. */
        public function close():void
        {
            Polycall.check(int(fn("polycall_peer_close")(_handle)), "Peer.close");
        }

        private function text(name:String, cap:int, operation:String):String
        {
            var buf:Uint8Array = new Uint8Array(cap);
            Polycall.check(int(fn(name)(_handle, buf, cap)), operation);
            return NativeCore.cstring(buf);
        }

        /** bound "host:port" ("" for a send-only node) */
        public function get endpoint():String
        {
            return text("polycall_peer_endpoint", Polycall.ENDPOINT_MAX, "Peer.endpoint");
        }

        public function get nodeId():String
        {
            return text("polycall_peer_node_id", Polycall.PEER_ID_MAX, "Peer.nodeId");
        }

        /** endpoint into a caller buffer of `capacity` bytes (E_TOO_LARGE when too small) */
        public function endpointInto(capacity:int):String
        {
            return text("polycall_peer_endpoint", capacity, "Peer.endpoint");
        }

        /** add or replace peerId -> endpoint in THIS node's registry */
        public function register(peerId:String, endpoint:String):void
        {
            Polycall.check(int(fn("polycall_peer_register")(_handle, Polycall.cstr(peerId, "peer_id", "Peer.register"),
                Polycall.cstr(endpoint, "endpoint", "Peer.register"))), "Peer.register");
        }

        public function unregister(peerId:String):void
        {
            Polycall.check(int(fn("polycall_peer_unregister")(_handle,
                Polycall.cstr(peerId, "peer_id", "Peer.unregister"))), "Peer.unregister");
        }

        private function json(name:String, operation:String, capacity:int):String
        {
            var len:Array = [0];
            var cap:int = capacity > 0 ? capacity : 512;
            var buf:Uint8Array = new Uint8Array(cap);
            var st:int = int(fn(name)(_handle, buf, cap, len));
            if (st == Polycall.E_TOO_LARGE && capacity <= 0) {
                cap = int(len[0]) + 1;
                buf = new Uint8Array(cap);
                st = int(fn(name)(_handle, buf, cap, len));
            }
            lastLength = uint(len[0]);
            Polycall.check(st, operation);
            return NativeCore.text(buf, int(len[0]));
        }

        /** out_len of the last list()/health(): text length, or the size needed on E_TOO_LARGE */
        public var lastLength:uint = 0;

        /** THIS node's registry as JSON {"id":"host:port",...}; capacity 0 = as large as needed */
        public function list(capacity:int = 0):String
        {
            return json("polycall_peer_list", "Peer.list", capacity);
        }

        /** this node's health JSON; capacity 0 = as large as needed */
        public function health(capacity:int = 0):String
        {
            return json("polycall_peer_health", "Peer.health", capacity);
        }

        /** GET /health on peer (registered id or "host:port"); for an id, under that id */
        public function ping(peer:String, timeoutMs:uint = 3000):void
        {
            Polycall.check(int(fn("polycall_peer_ping")(_handle, Polycall.cstr(peer, "peer", "Peer.ping"), timeoutMs)),
                "Peer.ping");
        }

        private static function bytes(payload:*):Uint8Array
        {
            if (payload == null) return new Uint8Array(0);
            if (payload is Uint8Array) return payload as Uint8Array;
            return NativeCore.utf8(String(payload));
        }

        /**
         * Deliver payload (Uint8Array, binary-safe; a String is sent as
         * UTF-8) to peer (registered id or "host:port"). Exactly one
         * attempt; retry with the SAME messageId (null = generated).
         */
        public function send(peer:String, payload:*, messageId:String = null, timeoutMs:uint = 5000):void
        {
            var data:Uint8Array = bytes(payload);
            Polycall.check(int(fn("polycall_peer_send")(_handle, Polycall.cstr(peer, "peer", "Peer.send"), data,
                data.length, Polycall.cstr(messageId, "message_id", "Peer.send"), timeoutMs)), "Peer.send");
        }

        /** payload length the last recv() reported (the size needed on E_TOO_LARGE) */
        public var lastPayloadLength:uint = 0;

        /**
         * Take the oldest message (timeoutMs 0 = poll, Polycall.FOREVER =
         * wait). capacity is the payload buffer: a larger message throws
         * E_TOO_LARGE (lastPayloadLength = needed) and stays queued.
         */
        public function recv(timeoutMs:uint = 5000, capacity:uint = 1048576):PeerMessage
        {
            var s:Uint8Array = new Uint8Array(Polycall.PEER_ID_MAX);
            var m:Uint8Array = new Uint8Array(Polycall.MESSAGE_ID_MAX);
            var p:Uint8Array = new Uint8Array(capacity);
            var len:Array = [0];
            var st:int = int(fn("polycall_peer_recv")(_handle, timeoutMs, s, s.length, m, m.length, p, capacity, len));
            lastPayloadLength = uint(len[0]);
            Polycall.check(st, "Peer.recv");
            return new PeerMessage(NativeCore.cstring(s), NativeCore.cstring(m), p.subarray(0, int(len[0])));
        }

        /** Wake every receive currently blocked on this node with E_CANCELLED. */
        public function cancel():void
        {
            Polycall.check(int(fn("polycall_peer_cancel")(_handle)), "Peer.cancel");
        }

        private static function asyncError(st:int, operation:String):PolycallError
        {
            return new PolycallError(st, NativeCore.load().strerror(st),
                "", operation);
        }

        /** recv on a worker thread: callback(error:PolycallError, message:PeerMessage) */
        public function recvAsync(timeoutMs:uint, callback:Function, capacity:uint = 1048576):void
        {
            var s:Uint8Array = new Uint8Array(Polycall.PEER_ID_MAX);
            var m:Uint8Array = new Uint8Array(Polycall.MESSAGE_ID_MAX);
            var p:Uint8Array = new Uint8Array(capacity);
            var len:Array = [0];
            var self:Peer = this;
            fn("polycall_peer_recv")["async"](_handle, timeoutMs, s, s.length, m, m.length, p, capacity, len,
                function(err:Object, result:Object):void {
                    if (err) {
                        callback(new PolycallError(Polycall.E_INTERNAL, "koffi", String(err), "Peer.recvAsync"), null);
                        return;
                    }
                    var st:int = int(result);
                    self.lastPayloadLength = uint(len[0]);
                    if (st < 0) callback(asyncError(st, "Peer.recvAsync"), null);
                    else callback(null, new PeerMessage(NativeCore.cstring(s), NativeCore.cstring(m),
                        p.subarray(0, int(len[0]))));
                });
        }

        /** send on a worker thread: callback(error:PolycallError) */
        public function sendAsync(peer:String, payload:*, messageId:String, timeoutMs:uint, callback:Function):void
        {
            var data:Uint8Array = bytes(payload);
            var to:String = Polycall.cstr(peer, "peer", "Peer.sendAsync");
            var id:String = Polycall.cstr(messageId, "message_id", "Peer.sendAsync");
            fn("polycall_peer_send")["async"](_handle, to, data, data.length, id, timeoutMs,
                function(err:Object, result:Object):void {
                    if (err) callback(new PolycallError(Polycall.E_INTERNAL, "koffi", String(err), "Peer.sendAsync"));
                    else if (int(result) < 0) callback(asyncError(int(result), "Peer.sendAsync"));
                    else callback(null);
                });
        }
    }
}
