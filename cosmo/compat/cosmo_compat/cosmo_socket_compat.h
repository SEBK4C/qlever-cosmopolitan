// Socket-constant translation for Cosmopolitan Libc.
//
// Like errno values, many socket constants (SOL_SOCKET, SO_*, IPV6_*, IP_*)
// are runtime symbols under Cosmopolitan holding host-native values. The
// patched boost/asio/detail/socket_types.hpp gives the BOOST_ASIO_OS_DEF_*
// macros canonical Linux numeric sentinels so they can be used in Asio's
// compile-time contexts (enum initializers, socket_option template
// arguments); this header provides the runtime sentinel -> native translation
// applied at Asio's setsockopt/getsockopt funnel in socket_ops.ipp.
//
// Constants that are universal literals across all supported OSes
// (AF_INET, SOCK_*, MSG_PEEK/OOB/DONTROUTE, TCP_NODELAY, IPPROTO_*, SHUT_*)
// need no translation. MSG_EOR does not exist under Cosmopolitan; its
// sentinel (0x80) is never translated — do not use
// socket_base::message_end_of_record on cosmo builds.
#ifndef COSMO_COMPAT_COSMO_SOCKET_COMPAT_H
#define COSMO_COMPAT_COSMO_SOCKET_COMPAT_H
#ifdef __COSMOPOLITAN__

#include <netinet/in.h>
#include <sys/socket.h>

namespace cosmo_compat {

// `level` and `optname` carry Linux-sentinel values (see the
// BOOST_ASIO_OS_DEF_* overrides in boost/asio/detail/socket_types.hpp);
// rewrite them to this host's native values. Unknown values pass through
// unchanged (e.g. Asio's custom_socket_option_level).
inline void native_sockopt(int& level, int& optname) noexcept {
  if (level == 1) {  // SOL_SOCKET sentinel
    level = SOL_SOCKET;
    int name = optname;
    if (name == 1) { optname = SO_DEBUG; return; }
    if (name == 2) { optname = SO_REUSEADDR; return; }
    if (name == 5) { optname = SO_DONTROUTE; return; }
    if (name == 6) { optname = SO_BROADCAST; return; }
    if (name == 7) { optname = SO_SNDBUF; return; }
    if (name == 8) { optname = SO_RCVBUF; return; }
    if (name == 9) { optname = SO_KEEPALIVE; return; }
    if (name == 10) { optname = SO_OOBINLINE; return; }
    if (name == 13) { optname = SO_LINGER; return; }
#ifdef SO_RCVLOWAT
    if (name == 18) { optname = SO_RCVLOWAT; return; }
    if (name == 19) { optname = SO_SNDLOWAT; return; }
#endif
#ifdef SO_ACCEPTCONN
    if (name == 30) { optname = SO_ACCEPTCONN; return; }
#endif
    return;
  }
  if (level == 0) {  // IPPROTO_IP (universal literal)
#ifdef IP_TTL
    if (optname == 2) { optname = IP_TTL; return; }
#endif
#ifdef IP_MULTICAST_IF
    if (optname == 32) { optname = IP_MULTICAST_IF; return; }
    if (optname == 33) { optname = IP_MULTICAST_TTL; return; }
    if (optname == 34) { optname = IP_MULTICAST_LOOP; return; }
    if (optname == 35) { optname = IP_ADD_MEMBERSHIP; return; }
    if (optname == 36) { optname = IP_DROP_MEMBERSHIP; return; }
#endif
    return;
  }
  if (level == 41) {  // IPPROTO_IPV6 (universal literal)
#ifdef IPV6_UNICAST_HOPS
    if (optname == 16) { optname = IPV6_UNICAST_HOPS; return; }
#endif
#ifdef IPV6_MULTICAST_IF
    if (optname == 17) { optname = IPV6_MULTICAST_IF; return; }
    if (optname == 18) { optname = IPV6_MULTICAST_HOPS; return; }
    if (optname == 19) { optname = IPV6_MULTICAST_LOOP; return; }
#endif
#ifdef IPV6_JOIN_GROUP
    if (optname == 20) { optname = IPV6_JOIN_GROUP; return; }
    if (optname == 21) { optname = IPV6_LEAVE_GROUP; return; }
#endif
#ifdef IPV6_V6ONLY
    if (optname == 26) { optname = IPV6_V6ONLY; return; }
#endif
    return;
  }
  // IPPROTO_TCP (6): TCP_NODELAY is 1 on all supported OSes — no translation.
}

}  // namespace cosmo_compat

// Cosmopolitan has no if_indextoname/if_nametoindex; Asio only uses them to
// render/parse IPv6 link-local scope ids as interface names. The fallback
// (numeric scope ids) remains fully functional.
inline char* cosmo_compat_if_indextoname(unsigned, char*) noexcept {
  return nullptr;
}
inline unsigned cosmo_compat_if_nametoindex(const char*) noexcept { return 0; }

#endif  // __COSMOPOLITAN__
#endif  // COSMO_COMPAT_COSMO_SOCKET_COMPAT_H
