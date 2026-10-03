# ActionScript tests

`node tests/run-tests.js` (npm test) compiles `TestMain.as` and
`../examples/Hello.as` with Apache Royale `asnodec`, starts the C CLI
processes (runtime, daemon, `peer serve` node) and runs the AS3 test
against the REAL core: no mock. Loader cases use the stand-in libraries of
`fixtures/fake_core.c`. Exit 77 = SKIP (something needed was missing),
never a pass. AIR / Flash Player are not tested (proprietary, licence).
