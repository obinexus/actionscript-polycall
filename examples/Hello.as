package
{
    import org.obinexus.polycall.Peer;
    import org.obinexus.polycall.PeerMessage;
    import org.obinexus.polycall.Polycall;
    import org.obinexus.polycall.PolycallError;

    /**
     * npm run build && node build/example/bin/js-release/index.js
     * Validates actionscript-polycallrc for running, then sends one message
     * between two nodes, through the real Polycall core.
     */
    public class Hello
    {
        private static function print(text:String):void
        {
            process["stdout"]["write"](text);
        }

        public function Hello()
        {
            try {
                print("Polycall " + Polycall.version + ", binding ABI " + Polycall.abiVersion +
                    " (" + Polycall.libraryPath + ")\n");
                Polycall.runConfig("actionscript-polycallrc");
                print("actionscript-polycallrc: valid for running with this build\n");
                var inbox:Peer = Peer.open("as3-inbox", "127.0.0.1:0");
                var outbox:Peer = Peer.open("as3-outbox");
                outbox.send(inbox.endpoint, "hello from ActionScript", "m-1");
                var m:PeerMessage = inbox.recv(5000);
                print(m.from + " sent '" + m.text + "' as " + m.id + "\n");
                outbox.close();
                inbox.close();
            } catch (e:PolycallError) {
                process["stderr"]["write"]("hello: " + e.message + "\n");
                process["exitCode"] = 1;
            }
        }
    }
}
