/*
 * fake_core.c -- NOT Polycall. Stand-in libraries for the loader tests:
 *
 *   -DFAKE_OLD      a 1.0-style library: polycall_get_version only, no
 *                   binding-ABI-v1 symbols
 *   -DFAKE_ABI=2    polycall_ffi_abi_version() returns 2
 *   -DFAKE_PARTIAL  ABI 1, but polycall_peer_health is missing
 *
 * The loader must turn each into a clear PolycallLoadError, never a crash.
 */
#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define FAKE_EXPORT __declspec(dllexport)
#else
#define FAKE_EXPORT __attribute__((visibility("default")))
#endif

#ifndef FAKE_ABI
#define FAKE_ABI 1
#endif

FAKE_EXPORT const char *polycall_get_version(void) { return "1.0.1"; }

#ifndef FAKE_OLD
#define STUB -18 /* POLYCALL_E_INTERNAL */
FAKE_EXPORT int polycall_ffi_abi_version(void) { return FAKE_ABI; }
FAKE_EXPORT int polycall_ffi_version(char *b, int l) { (void)b; (void)l; return STUB; }
FAKE_EXPORT const char *polycall_strerror(int s) { (void)s; return "FAKE"; }
FAKE_EXPORT int polycall_last_error(char *b, size_t c) { (void)b; (void)c; return 0; }
FAKE_EXPORT int polycall_ffi_run_config(const char *p, int r) { (void)p; (void)r; return STUB; }
FAKE_EXPORT int polycall_ffi_describe(const char *p, char *b, int l) { (void)p; (void)b; (void)l; return STUB; }
FAKE_EXPORT int polycall_call(const char *e, const char *s, const char *o, const char *i, uint32_t t,
                              char *out, size_t cap, size_t *len)
{ (void)e; (void)s; (void)o; (void)i; (void)t; (void)out; (void)cap; (void)len; return STUB; }
FAKE_EXPORT int polycall_peer_open(const char *n, const char *b, const char *a, int32_t *h)
{ (void)n; (void)b; (void)a; (void)h; return STUB; }
FAKE_EXPORT int polycall_peer_close(int32_t h) { (void)h; return STUB; }
FAKE_EXPORT int polycall_peer_endpoint(int32_t h, char *b, size_t c) { (void)h; (void)b; (void)c; return STUB; }
FAKE_EXPORT int polycall_peer_node_id(int32_t h, char *b, size_t c) { (void)h; (void)b; (void)c; return STUB; }
FAKE_EXPORT int polycall_peer_register(int32_t h, const char *i, const char *e) { (void)h; (void)i; (void)e; return STUB; }
FAKE_EXPORT int polycall_peer_unregister(int32_t h, const char *i) { (void)h; (void)i; return STUB; }
FAKE_EXPORT int polycall_peer_list(int32_t h, char *b, size_t c, size_t *l) { (void)h; (void)b; (void)c; (void)l; return STUB; }
FAKE_EXPORT int polycall_peer_ping(int32_t h, const char *p, uint32_t t) { (void)h; (void)p; (void)t; return STUB; }
FAKE_EXPORT int polycall_peer_send(int32_t h, const char *p, const void *d, size_t n, const char *m, uint32_t t)
{ (void)h; (void)p; (void)d; (void)n; (void)m; (void)t; return STUB; }
FAKE_EXPORT int polycall_peer_recv(int32_t h, uint32_t t, char *s, size_t sc, char *m, size_t mc,
                                   void *p, size_t pc, size_t *pl)
{ (void)h; (void)t; (void)s; (void)sc; (void)m; (void)mc; (void)p; (void)pc; (void)pl; return STUB; }
FAKE_EXPORT int polycall_peer_cancel(int32_t h) { (void)h; return STUB; }
#ifndef FAKE_PARTIAL
FAKE_EXPORT int polycall_peer_health(int32_t h, char *b, size_t c, size_t *l) { (void)h; (void)b; (void)c; (void)l; return STUB; }
#endif
#endif
