package org.obinexus.polycall
{
    /** One received message: sender node id, message id and the exact payload bytes. */
    public class PeerMessage
    {
        public var from:String;
        public var id:String;
        public var payload:Uint8Array;

        public function PeerMessage(from:String, id:String, payload:Uint8Array)
        {
            this.from = from;
            this.id = id;
            this.payload = payload;
        }

        /** the payload decoded as UTF-8 */
        public function get text():String
        {
            return NativeCore.decode(payload);
        }
    }
}
