package
{
    import org.obinexus.polycall.Peer;
    import org.obinexus.polycall.PeerMessage;
    import org.obinexus.polycall.Polycall;
    import org.obinexus.polycall.PolycallError;
    import org.obinexus.polycall.PolycallLoadError;

    /**
     * Real-core test of actionscript-polycall: ActionScript 3 compiled to
     * JavaScript by Apache Royale (asnodec) and run by Node.js against the
     * REAL Polycall library (no mock). Driven by tests/run-tests.js, which
     * passes (environment):
     *   QA_RUNTIME / QA_DAEMON  `polycall start` / `polycall daemon start`
     *   QA_CNODE                `polycall peer serve --node-id cnode` (token QA_TOKEN)
     *   QA_FIXTURES             configuration fixtures
     *   QA_SPECIAL              a fixture name with quotes, spaces and $()
     *   POLYCALL_CLI, QA_TAG
     * AS3_TEST_MODE=loader only loads the library and prints the outcome.
     */
    public class TestMain
    {
        private var npass:int = 0;
        private var nfail:int = 0;
        private var env:Object;
        private var F:String;

        public function TestMain()
        {
            env = process["env"];
            if (env["AS3_TEST_MODE"] == "loader") {
                loaderProbe();
                return;
            }
            F = String(env["QA_FIXTURES"]);
            out("actionscript-polycall: AS3 (Apache Royale -> Node.js " + process["version"] + ") against the real core");
            try {
                testLibrary();
                testConfig();
                testCall("polycall start", String(env["QA_RUNTIME"]));
                testCall("polycall daemon", String(env["QA_DAEMON"]));
                testPeers();
                testInterop();
            } catch (e:Error) {
                fail("uncaught " + e.name + ": " + e.message, "");
            }
            testAsync(finish);
        }

        // ---- output -------------------------------------------------------------

        private function out(line:String):void
        {
            process["stdout"]["write"](line + "\n");
        }

        private function pass(what:String):void
        {
            npass++;
            out("PASS  " + what);
        }

        private function fail(what:String, detail:String):void
        {
            nfail++;
            out("FAIL  " + what + (detail ? "  [" + detail + "]" : ""));
        }

        private function check(cond:Boolean, what:String, detail:String = ""):void
        {
            if (cond) pass(what);
            else fail(what, detail);
        }

        private function name(status:int):String
        {
            var s:String = Polycall.strerror(status);
            var i:int = s.indexOf(":");
            return i < 0 ? s : s.substr(0, i);
        }

        /** fn() must throw PolycallError(status); returns the error */
        private function expectError(fn:Function, status:int, what:String):PolycallError
        {
            try {
                fn();
            } catch (e:PolycallError) {
                check(e.status == status && e.statusName == Polycall.strerror(status),
                    what + " -> " + name(status) + " (got " + name(e.status) + ")", e.message);
                return e;
            } catch (e2:Error) {
                fail(what + " -> " + name(status), "threw " + e2.name + ": " + e2.message);
                return null;
            }
            fail(what + " -> " + name(status), "no error was thrown");
            return null;
        }

        private function ok(fn:Function, what:String):*
        {
            try {
                var r:* = fn();
                pass(what);
                return r;
            } catch (e:Error) {
                fail(what, e.message);
            }
            return null;
        }

        private function now():Number
        {
            return new Date().getTime();
        }

        private function bytesEqual(a:Uint8Array, b:Uint8Array):Boolean
        {
            if (a.length != b.length) return false;
            for (var i:int = 0; i < a.length; i++) if (a[i] != b[i]) return false;
            return true;
        }

        private function utf8(s:String):Uint8Array
        {
            var b:Object = require("buffer")["Buffer"]["from"](s, "utf8");
            return new Uint8Array(b["buffer"], b["byteOffset"], b["length"]);
        }

        private function b64(u:Uint8Array):String
        {
            return require("buffer")["Buffer"]["from"](u["buffer"], u["byteOffset"], u.length)["toString"]("base64");
        }

        private function got(peer:Peer, from:String, id:String, payload:Uint8Array):Boolean
        {
            var m:PeerMessage = peer.recv(5000);
            return m.from == from && (id == null || m.id == id) && bytesEqual(m.payload, payload);
        }

        /** run the C CLI; returns {status, stdout (Buffer)} */
        private function cli(args:Array):Object
        {
            var r:Object = require("child_process")["spawnSync"](String(env["POLYCALL_CLI"]), args,
                { "env": env, "timeout": 30000, "windowsHide": true });
            return { "status": r["status"], "stdout": r["stdout"] };
        }

        // ---- loader probe ----------------------------------------------------------

        private function loaderProbe():void
        {
            var r:Object = {};
            try {
                Polycall.load();
                r["ok"] = true;
                r["path"] = Polycall.libraryPath;
                r["version"] = Polycall.version;
                r["abi"] = Polycall.abiVersion;
            } catch (e:PolycallLoadError) {
                r["ok"] = false;
                r["name"] = e.name;
                r["reason"] = e.reason;
                r["library"] = e.library;
                r["message"] = e.message;
            } catch (e2:Error) {
                r["ok"] = false;
                r["name"] = e2.name;
                r["message"] = e2.message;
            }
            out(JSON.stringify(r));
        }

        // ---- tests -------------------------------------------------------------------

        private function testLibrary():void
        {
            var names:Array = ["OK", "E_INVALID_ARGUMENT", "E_NO_MEMORY", "E_INVALID_HANDLE", "E_TIMEOUT",
                "E_TRANSPORT", "E_PROTOCOL", "E_NOT_FOUND", "E_AUTH", "E_REMOTE", "E_TOO_LARGE", "E_BUSY",
                "E_CANCELLED", "E_CONFIG", "E_ADDRESS_IN_USE", "E_UNSUPPORTED", "E_PERMISSION", "E_CLOSED", "E_INTERNAL"];
            check(Polycall.abiVersion == 1, "Polycall.abiVersion == 1");
            check(/^1\.\d+\.\d+$/.test(Polycall.version), "Polycall.version -> " + Polycall.version + " (" + Polycall.libraryPath + ")");
            var consts:Array = [Polycall.OK, Polycall.E_INVALID_ARGUMENT, Polycall.E_NO_MEMORY, Polycall.E_INVALID_HANDLE,
                Polycall.E_TIMEOUT, Polycall.E_TRANSPORT, Polycall.E_PROTOCOL, Polycall.E_NOT_FOUND, Polycall.E_AUTH,
                Polycall.E_REMOTE, Polycall.E_TOO_LARGE, Polycall.E_BUSY, Polycall.E_CANCELLED, Polycall.E_CONFIG,
                Polycall.E_ADDRESS_IN_USE, Polycall.E_UNSUPPORTED, Polycall.E_PERMISSION, Polycall.E_CLOSED, Polycall.E_INTERNAL];
            var all:Boolean = true;
            for (var i:int = 0; i < names.length; i++) {
                if (name(-i) != "POLYCALL_" + names[i] || consts[i] != -i) all = false;
            }
            check(all, "strerror names all 19 codes and the Polycall.E_* constants match");
            check(name(-99) == "POLYCALL_E_UNKNOWN", "strerror(unknown)");
            var e:PolycallError = expectError(function():void { Polycall.runConfig(F + "/missing-polycallrc"); },
                Polycall.E_NOT_FOUND, "a failing call throws PolycallError");
            check(e != null && e.detail.indexOf("missing-polycallrc") >= 0 && e.code == "POLYCALL_E_NOT_FOUND",
                "PolycallError carries status, name and detail: " + (e ? e.message : ""));
            ok(function():void { Polycall.runConfig(F + "/as3-polycallrc"); }, "a succeeding call");
            check(Polycall.lastError() == "", "lastError() is empty after a success");
        }

        private function testConfig():void
        {
            var uni:String = F + "/ünïcødé-ディレクトリ/as3-polycallrc";
            ok(function():void { Polycall.runConfig(F + "/as3-polycallrc"); }, "runConfig shipped actionscript-polycallrc (run = true)");
            ok(function():void { Polycall.runConfig(F + "/as3-polycallrc", false); }, "runConfig run = false");
            var e:PolycallError = expectError(function():void { Polycall.runConfig(F + "/bad-polycallrc", false); },
                Polycall.E_CONFIG, "invalid file");
            check(e != null && e.detail != "", "invalid-file detail: " + (e ? e.detail : ""));
            ok(function():void { Polycall.runConfig(F + "/unknown-polycallrc", false); }, "unknown key, run = false (warning)");
            expectError(function():void { Polycall.runConfig(F + "/unknown-polycallrc"); }, Polycall.E_CONFIG, "unknown key, run = true (strict)");
            ok(function():void { Polycall.runConfig(F + "/tls-polycallrc", false); }, "tls_enabled=true, run = false");
            expectError(function():void { Polycall.runConfig(F + "/tls-polycallrc"); }, Polycall.E_UNSUPPORTED, "tls_enabled=true refused for running");
            expectError(function():void { Polycall.runConfig(null); }, Polycall.E_INVALID_ARGUMENT, "runConfig(null)");
            expectError(function():void { Polycall.runConfig(""); }, Polycall.E_INVALID_ARGUMENT, "runConfig(\"\")");
            e = expectError(function():void { Polycall.runConfig("a" + String.fromCharCode(0) + "b"); },
                Polycall.E_INVALID_ARGUMENT, "a path with a NUL character is refused by the binding");
            ok(function():void { Polycall.runConfig(uni); }, "non-ASCII (UTF-8) config path");
            ok(function():void { Polycall.runConfig(F + "/" + env["QA_SPECIAL"]); }, "path with quotes, spaces and $(): " + env["QA_SPECIAL"]);
            var j:String = ok(function():String { return Polycall.describe(F + "/as3-polycallrc"); }, "describe");
            check(j != null && j.charAt(0) == "{" && j.indexOf("log_level") > 0, "describe -> JSON of " + (j ? j.length : 0) + " characters");
            j = ok(function():String { return Polycall.describe(uni); }, "describe non-ASCII path");
            expectError(function():void { Polycall.describe(F + "/missing-polycallrc"); }, Polycall.E_NOT_FOUND, "describe missing file");
        }

        private function testCall(label:String, ep:String):void
        {
            var want:String = '{"item_id":"widget-a","quantity":42,"in_stock":true}';
            var r:String = ok(function():String { return Polycall.invoke(ep, "inventory", "get", '{"item_id":"widget-a"}'); },
                "[" + label + "] inventory.get");
            check(r == want && Polycall.lastCallLength == want.length, "[" + label + "] output " + r);
            r = ok(function():String { return Polycall.invoke(ep, "debug", "echo", '{"text":"héllo — 世界"}'); }, "[" + label + "] debug.echo");
            check(r != null && r.indexOf("héllo — 世界") >= 0, "[" + label + "] UTF-8 round trip: " + r);
            r = ok(function():String { return Polycall.invoke(ep, "debug", "echo", null); }, "[" + label + "] input null");
            check(r == '{"echo":null}', "[" + label + "] null input is sent as null");
            var e:PolycallError = expectError(function():void { Polycall.invoke(ep, "debug", "no_such_op", "{}"); },
                Polycall.E_NOT_FOUND, "[" + label + "] unknown operation");
            check(e != null && e.output.indexOf("operation.unknown") >= 0, "[" + label + "] error.output = " + (e ? e.output : ""));
            e = expectError(function():void { Polycall.invoke(ep, "inventory", "get", '{"item_id":"nope"}'); },
                Polycall.E_REMOTE, "[" + label + "] remote error");
            check(e != null && e.output.indexOf("item.unknown") >= 0, "[" + label + "] remote error object: " + (e ? e.output : ""));
            expectError(function():void { Polycall.invoke(ep, "debug", "sleep", '{"ms":3000}', 300); }, Polycall.E_TIMEOUT, "[" + label + "] deadline");
            expectError(function():void { Polycall.invoke(ep, "debug", "echo", "{bad json"); }, Polycall.E_INVALID_ARGUMENT, "[" + label + "] invalid input JSON");
            expectError(function():void { Polycall.invoke(ep, "debug", "echo", "1", 0); }, Polycall.E_INVALID_ARGUMENT, "[" + label + "] timeout 0");
            expectError(function():void { Polycall.invoke(ep, "debug", "echo", "1", 600001); }, Polycall.E_INVALID_ARGUMENT, "[" + label + "] timeout 600001");
            ok(function():String { return Polycall.invoke(ep, "debug", "echo", "1", 600000); }, "[" + label + "] timeout 600000 accepted");
            expectError(function():void { Polycall.invoke(ep, "debug", "echo", "1", Polycall.FOREVER); }, Polycall.E_INVALID_ARGUMENT, "[" + label + "] timeout 0xFFFFFFFF");
            expectError(function():void { Polycall.invoke(ep, "inventory", "get", '{"item_id":"widget-a"}', 5000, 8); },
                Polycall.E_TOO_LARGE, "[" + label + "] 8-byte output buffer");
            check(Polycall.lastCallLength == want.length, "[" + label + "] out_len = " + Polycall.lastCallLength + " needed");
            expectError(function():void { Polycall.invoke(ep, "inventory", "get", '{"item_id":"widget-a"}', 5000, want.length); },
                Polycall.E_TOO_LARGE, "[" + label + "] buffer == length (no room for NUL)");
            r = ok(function():String { return Polycall.invoke(ep, "inventory", "get", '{"item_id":"widget-a"}', 5000, want.length + 1); },
                "[" + label + "] buffer == length + 1");
            expectError(function():void { Polycall.invoke(ep, "", "get"); }, Polycall.E_INVALID_ARGUMENT, "[" + label + "] empty service");
            var big:String = '"' + new Array(1048600).join("a") + '"';
            expectError(function():void { Polycall.invoke(ep, "debug", "echo", big); }, Polycall.E_TOO_LARGE, "[" + label + "] input over the 1 MiB frame");
            if (label == "polycall daemon") {
                expectError(function():void { Polycall.invoke("127.0.0.1:1", "debug", "echo"); }, Polycall.E_TRANSPORT, "call with no runtime");
                expectError(function():void { Polycall.invoke("no-port", "debug", "echo"); }, Polycall.E_INVALID_ARGUMENT, "call malformed endpoint");
            }
        }

        private function testPeers():void
        {
            var a:Peer = Peer.open("alpha", "127.0.0.1:0");
            var b:Peer = Peer.open("beta", "127.0.0.1:0", "");
            check(a.handle > 0 && b.handle > 0 && a.handle != b.handle, "Peer.open alpha / beta -> handles " + a.handle + ", " + b.handle);
            var ea:String = a.endpoint;
            var eb:String = b.endpoint;
            check(/^127\.0\.0\.1:\d+$/.test(ea) && ea != eb, "endpoints " + ea + " / " + eb);
            check(a.nodeId == "alpha", "nodeId");
            expectError(function():void { a.endpointInto(5); }, Polycall.E_TOO_LARGE, "endpoint into a 5-byte buffer");
            var so:Peer = Peer.open("sendonly");
            check(so.endpoint == "", "send-only node (bind null) has endpoint \"\"");
            a.register("beta", eb);
            b.register("alpha", ea);
            pass("alpha and beta register each other");

            a.send("beta", "hello beta", "m-a2b");
            check(got(b, "alpha", "m-a2b", utf8("hello beta")), "alpha -> beta (registered id): exact bytes, sender, id");
            b.send(ea, "hello alpha", "m-b2a");
            check(got(a, "beta", "m-b2a", utf8("hello alpha")), "beta -> alpha (host:port)");
            so.send(eb, "from send-only", "m-so");
            check(got(b, "sendonly", "m-so", utf8("from send-only")), "send-only node -> beta");
            a.send("beta", "generated");
            var m:PeerMessage = b.recv(5000);
            check(m.id != "" && m.text == "generated", "a message id was generated (" + m.id + ")");

            a.send(eb, new Uint8Array(0), "empty");
            check(got(b, "alpha", "empty", new Uint8Array(0)), "empty payload");
            var u:Uint8Array = utf8("héllo — 世界 🌍");
            a.send(eb, u, "utf8");
            check(got(b, "alpha", "utf8", u), "UTF-8 payload byte-identical");
            var bin:Uint8Array = new Uint8Array(259);
            for (var i:int = 0; i < 256; i++) bin[i] = i;
            bin[258] = 1;
            a.send(eb, bin, "binary");
            check(got(b, "alpha", "binary", bin), "binary payload (all 256 values + NULs) byte-identical");
            var max:Uint8Array = new Uint8Array(1048577);
            for (i = 0; i < max.length; i++) max[i] = (i * 131 + 7) & 255;
            a.send(eb, max.subarray(0, 1048576), "max", 20000);
            m = b.recv(20000);
            check(m.id == "max" && bytesEqual(m.payload, max.subarray(0, 1048576)), "exactly 1 MiB byte-identical");
            expectError(function():void { a.send(eb, max, "over"); }, Polycall.E_TOO_LARGE, "1 MiB + 1 refused");
            expectError(function():void { b.recv(300); }, Polycall.E_TIMEOUT, "the 1 MiB + 1 payload was not delivered");

            a.send(eb, bin.subarray(0, 100), "queued");
            expectError(function():void { b.recv(5000, 10); }, Polycall.E_TOO_LARGE, "10-byte receive buffer");
            check(b.lastPayloadLength == 100, "payload_len = " + b.lastPayloadLength + " needed");
            check(got(b, "alpha", "queued", bin.subarray(0, 100)), "the message stayed queued and arrives whole");

            ok(function():void { a.ping("beta", 2000); }, "ping registered id");
            a.register("impostor", eb);
            expectError(function():void { a.ping("impostor", 2000); }, Polycall.E_PROTOCOL, "ping checks the node id");
            expectError(function():void { a.send("impostor", "x", "to-impostor"); }, Polycall.E_PROTOCOL, "send checks the acknowledging id");
            m = b.recv(2000);
            check(m.id == "to-impostor", "(beta stored it: E_PROTOCOL = not known delivered to that id)");
            expectError(function():void { a.send("nobody", "x"); }, Polycall.E_NOT_FOUND, "send to an unknown id");

            var g:Peer = Peer.open("gamma", "127.0.0.1:0");
            var eg:String = g.endpoint;
            a.send(eg, "x", "own-1");
            check(got(g, "alpha", "own-1", utf8("x")), "gamma received from alpha");
            check(g.list() == "{}", "gamma's registry stays {} (receiving never registers)");
            expectError(function():void { g.send("alpha", "x"); }, Polycall.E_NOT_FOUND, "gamma cannot address alpha by id");
            var l:String = a.list();
            check(l.indexOf('"beta":"' + eb + '"') >= 0 && l.indexOf('"impostor":') >= 0 && a.lastLength == l.length, "alpha's registry: " + l);
            l = b.list();
            check(l.indexOf('"alpha":') >= 0 && l.indexOf("impostor") < 0, "beta's registry is its own: " + l);
            expectError(function():void { a.list(5); }, Polycall.E_TOO_LARGE, "list into a 5-byte buffer");
            check(a.lastLength > 5, "out_len = " + a.lastLength + " needed");
            a.unregister("impostor");
            expectError(function():void { a.unregister("impostor"); }, Polycall.E_NOT_FOUND, "unregister twice");

            a.send(eb, "once", "dup");
            a.send(eb, "once", "dup");
            check(got(b, "alpha", "dup", utf8("once")), "duplicate id: first copy received");
            expectError(function():void { b.recv(500); }, Polycall.E_TIMEOUT, "duplicate delivered once");

            var s:Peer = Peer.open("secure", "127.0.0.1:0", "as3-secret");
            var es:String = s.endpoint;
            var t:Peer = Peer.open("trusted", null, "as3-secret");
            var x:Peer = Peer.open("mallory", null, "wrong");
            expectError(function():void { a.send(es, "x", "no-token"); }, Polycall.E_AUTH, "send without the token");
            expectError(function():void { x.send(es, "x", "bad-token"); }, Polycall.E_AUTH, "send with a wrong token");
            t.send(es, "authorised", "good-token");
            check(got(s, "trusted", "good-token", utf8("authorised")), "only the authorised message arrived");
            x.close();

            g.close();
            expectError(function():void { a.send(eg, "void", "void", 2000); }, Polycall.E_TRANSPORT, "send to a dead peer");
            expectError(function():void { a.ping(eg, 1000); }, Polycall.E_TRANSPORT, "ping a dead peer");
            var t0:Number = now();
            expectError(function():void { b.recv(0); }, Polycall.E_TIMEOUT, "recv timeout 0 (poll)");
            check(now() - t0 < 150, "poll returned at once");
            t0 = now();
            expectError(function():void { b.recv(300); }, Polycall.E_TIMEOUT, "recv timeout 300 ms");
            var dt:Number = now() - t0;
            check(dt >= 250 && dt < 3000, "waited " + dt + " ms");
            var h:String = b.health();
            check(h.indexOf('"node_id":"beta"') >= 0, "health: " + h.substr(0, 100));

            var id63:String = new Array(64).join("i");
            ok(function():void { Peer.open(id63).close(); }, "open + close with a 63-byte node id");
            expectError(function():void { Peer.open(id63 + "i"); }, Polycall.E_INVALID_ARGUMENT, "64-byte node id");
            expectError(function():void { Peer.open("bad id!", "127.0.0.1:0"); }, Polycall.E_INVALID_ARGUMENT, "invalid node id");
            expectError(function():void { Peer.open("x", "0.0.0.0:0"); }, Polycall.E_CONFIG, "non-loopback bind without a token");
            expectError(function():void { Peer.open("dupbind", ea); }, Polycall.E_ADDRESS_IN_USE, "bind alpha's endpoint again");
            expectError(function():void { a.register("bad id", eb); }, Polycall.E_INVALID_ARGUMENT, "register an invalid id");
            expectError(function():void { a.send(eb, "x", "bad id"); }, Polycall.E_INVALID_ARGUMENT, "invalid message id");

            expectError(function():void { g.close(); }, Polycall.E_INVALID_HANDLE, "double close");
            expectError(function():void { g.send(eb, "x"); }, Polycall.E_INVALID_HANDLE, "send after close");
            expectError(function():void { g.recv(0); }, Polycall.E_INVALID_HANDLE, "recv after close");
            expectError(function():void { g.endpointInto(128); }, Polycall.E_INVALID_HANDLE, "endpoint after close");
            expectError(function():void { g.cancel(); }, Polycall.E_INVALID_HANDLE, "cancel after close");
            expectError(function():void { Peer.fromHandle(0).close(); }, Polycall.E_INVALID_HANDLE, "handle 0");
            expectError(function():void { Peer.fromHandle(-1).close(); }, Polycall.E_INVALID_HANDLE, "handle -1");
            expectError(function():void { Peer.fromHandle(0x7FFFFFFF).close(); }, Polycall.E_INVALID_HANDLE, "handle INT32_MAX");
            ok(function():void { b.cancel(); }, "cancel with no receiver waiting");
            expectError(function():void { b.recv(0); }, Polycall.E_TIMEOUT, "a later recv waits normally");

            s.close();
            t.close();
            so.close();
            b.close();
            a.close();
            pass("closed every node");
        }

        private function testInterop():void
        {
            var cnode:String = String(env["QA_CNODE"]);
            var tag:String = String(env["QA_TAG"]);
            var w:Peer = Peer.open("as3node", "127.0.0.1:0", String(env["QA_TOKEN"]));
            var ew:String = w.endpoint;
            var text:Uint8Array = utf8("from ActionScript ✓");
            w.send(cnode, text, "a2c-text-" + tag);
            var r:Object = cli(["--format", "json", "peer", "recv", "--to", cnode, "-t", "5000"]);
            var j:String = String(r["stdout"]);
            check(r["status"] == 0 && j.indexOf('"from":"as3node"') >= 0 && j.indexOf('"id":"a2c-text-' + tag + '"') >= 0 &&
                j.indexOf('"payload_b64":"' + b64(text) + '"') >= 0, "C CLI `peer recv` got the AS3 node's exact bytes, sender and id");
            var bin:Uint8Array = new Uint8Array([0x43, 0, 0x74, 0x6f, 0x61, 0x73, 0x33, 0, 0xff, 0]);
            w.send(cnode, bin, "a2c-bin-" + tag);
            r = cli(["peer", "recv", "--raw", "--to", cnode, "-t", "5000"]);
            var raw:Object = r["stdout"];
            check(r["status"] == 0 && bytesEqual(new Uint8Array(raw["buffer"], raw["byteOffset"], raw["length"]), bin),
                "C CLI `peer recv --raw` got the binary payload byte-identical");
            r = cli(["peer", "send", "--from", "cnode", "--to", ew, "--id", "c2a-" + tag, "--payload-file", F + "/c2a.bin"]);
            check(r["status"] == 0, "C CLI `peer send` -> AS3 node acknowledged");
            check(got(w, "cnode", "c2a-" + tag, bin), "AS3 node received the C CLI's exact bytes (with NULs), sender cnode");
            r = cli(["peer", "health", "--to", ew]);
            check(r["status"] == 0, "C CLI `peer health` on the AS3 node");
            var plain:Peer = Peer.open("plain");
            expectError(function():void { plain.send(cnode, "x"); }, Polycall.E_AUTH, "AS3 node without the token -> C node");
            plain.close();
            w.close();
        }

        // ---- async: blocked receives woken from this thread, concurrent senders ----

        private function later(ms:int, fn:Function):void
        {
            require("timers")["setTimeout"](fn, ms);
        }

        private function testAsync(done:Function):void
        {
            var self:TestMain = this;
            var r:Peer;
            try {
                r = Peer.open("blocker", "127.0.0.1:0");
            } catch (e:Error) {
                fail("open blocker", e.message);
                done();
                return;
            }
            var t0:Number = now();
            r.recvAsync(Polycall.FOREVER, function(err:PolycallError, m:PeerMessage):void {
                var dt:Number = now() - t0;
                self.check(err != null && err.status == Polycall.E_CANCELLED && dt >= 250,
                    "recvAsync(FOREVER) blocked on a worker thread woke with E_CANCELLED after " + dt + " ms", err ? err.message : "no error");
                var sender:Peer = Peer.open("waker");
                var t1:Number = now();
                r.recvAsync(Polycall.FOREVER, function(err2:PolycallError, m2:PeerMessage):void {
                    self.check(err2 == null && m2 != null && m2.from == "waker" && m2.text == "wake up",
                        "a message sent from this thread woke a blocked recvAsync", err2 ? err2.message : "");
                    sender.close();
                    var t2:Number = now();
                    r.recvAsync(Polycall.FOREVER, function(err3:PolycallError, m3:PeerMessage):void {
                        var dt3:Number = now() - t2;
                        self.check(err3 != null && err3.status == Polycall.E_CLOSED && dt3 >= 250,
                            "close() woke a blocked recvAsync with E_CLOSED after " + dt3 + " ms", err3 ? err3.message : "no error");
                        self.expectError(function():void { r.close(); }, Polycall.E_INVALID_HANDLE, "closing it again");
                        self.concurrency(done);
                    });
                    self.later(300, function():void { r.close(); });
                });
                self.later(200, function():void { sender.send(r.endpoint, "wake up", "wake"); });
            });
            later(300, function():void { r.cancel(); self.pass("cancel() from the main thread"); });
        }

        private function concurrency(done:Function):void
        {
            var self:TestMain = this;
            var recv:Peer = Peer.open("receiver", "127.0.0.1:0");
            var ep:String = recv.endpoint;
            var senders:Array = [];
            var k:int;
            for (k = 0; k < 4; k++) senders.push(Peer.open("sender-" + k));
            var shared:Peer = Peer.open("shared");
            var pending:int = 4 * 25 + 50;
            var failures:int = 0;
            var onSent:Function = function(err:PolycallError):void {
                if (err) failures++;
                if (--pending == 0) {
                    self.check(failures == 0, "150 concurrent sendAsync calls (4 nodes x 25 + 50 on one shared handle) acknowledged",
                        failures + " failed");
                    var seen:Object = {};
                    var unique:int = 0, bad:int = 0;
                    for (var i:int = 0; i < 150; i++) {
                        try {
                            var m:PeerMessage = recv.recv(5000);
                            var key:String = m.from + "/" + m.id;
                            if (m.text != "payload " + m.from + " " + m.id) bad++;
                            if (!seen[key]) unique++;
                            seen[key] = true;
                        } catch (e:Error) {
                            bad++;
                        }
                    }
                    self.check(unique == 150 && bad == 0, "the receiver got all 150 messages once with the right sender, id and bytes",
                        "unique " + unique + ", bad " + bad);
                    self.expectError(function():void { recv.recv(200); }, Polycall.E_TIMEOUT, "no extra messages");
                    for (var j:int = 0; j < 4; j++) senders[j].close();
                    shared.close();
                    recv.close();
                    done();
                }
            };
            for (k = 0; k < 4; k++) {
                for (var n:int = 0; n < 25; n++) {
                    var id:String = "m" + n;
                    (senders[k] as Peer).sendAsync(ep, "payload sender-" + k + " " + id, id, 10000, onSent);
                }
            }
            for (n = 0; n < 50; n++) shared.sendAsync(ep, "payload shared s" + n, "s" + n, 10000, onSent);
        }

        private function finish():void
        {
            out("actionscript-polycall: " + npass + " passed, " + nfail + " failed");
            process["exitCode"] = nfail ? 1 : 0;
        }
    }
}
