# TODO — actionscript-polycall (ActionScript 3)

Status: AS3 binding on Apache Royale -> Node.js, calling the real core via
koffi; tested on Linux and Windows.

- [ ] AIR: an AIR Native Extension (ANE) that exposes polycall.h to AS3 on
      Adobe/HARMAN AIR. Needs the proprietary AIR SDK (licence acceptance);
      the Peer/Polycall API would stay the same over a second backend.
- [ ] macOS: untested (no macOS host; the core has no verified macOS build).

Do not add config parsing or runtime logic here — adapt the core only.
