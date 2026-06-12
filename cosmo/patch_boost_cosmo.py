#!/usr/bin/env python3
"""Patch a Boost source tree for Cosmopolitan Libc.

Under Cosmopolitan, errno constants are runtime symbols whose values depend
on the host OS, so they cannot be used in constant expressions. Two Boost
headers put errno macros into enum initializers:

  boost/system/detail/errc.hpp   (boost::system::errc::errc_t)
  boost/asio/error.hpp           (boost::asio::error::basic_errors)

Fix (mirrors what cosmocc's libcxx does for std::errc):
  1. wrap each header in cosmo_errno_linux_push.h / _pop.h so the enums get
     compile-time Linux-sentinel values, and
  2. translate sentinel -> native host errno at runtime in the factory
     functions (make_error_code / make_error_condition), which is the single
     funnel through which these enums become error_code/error_condition
     values (boost::system's operator== with an enum goes through them too).

Usage: patch_boost_cosmo.py <boost-source-root>
Idempotent: files already containing the marker are skipped.
"""

import sys
import os

MARKER = "cosmo_compat"

PUSH_BLOCK = """
#ifdef __COSMOPOLITAN__
// Cosmopolitan: errno constants are runtime symbols; use Linux sentinels at
// compile time and translate back to native values in the make_* factories.
#include <cosmo_compat/cosmo_errno_compat.h>
#include <cosmo_compat/cosmo_errno_linux_push.h>
#endif
"""

POP_BLOCK = """
#ifdef __COSMOPOLITAN__
#include <cosmo_compat/cosmo_errno_linux_pop.h>
#endif
"""


def read(path):
    with open(path) as f:
        return f.read()


def write(path, text):
    with open(path, "w") as f:
        f.write(text)
    print(f"patched {path}")


def insert_after(text, anchor, block):
    idx = text.index(anchor) + len(anchor)
    return text[:idx] + block + text[idx:]


def insert_before(text, anchor, block):
    idx = text.index(anchor)
    return text[:idx] + block + text[idx:]


def replace_exactly_once(text, old, new):
    if text.count(old) != 1:
        raise SystemExit(f"expected exactly one occurrence of:\n{old}")
    return text.replace(old, new)


def guarded_return(original_line, translated_line):
    return (
        "#ifdef __COSMOPOLITAN__\n"
        + translated_line
        + "\n#else\n"
        + original_line
        + "\n#endif"
    )


def patch_system_detail_errc(root):
    path = os.path.join(root, "boost/system/detail/errc.hpp")
    text = read(path)
    if MARKER in text:
        print(f"already patched: {path}")
        return
    text = insert_after(
        text, "#include <boost/system/detail/cerrno.hpp>\n", PUSH_BLOCK
    )
    # pop right before the closing include guard (last #endif in the file)
    last_endif = text.rindex("#endif")
    text = text[:last_endif] + POP_BLOCK + "\n" + text[last_endif:]
    write(path, text)


def patch_system_errc(root):
    path = os.path.join(root, "boost/system/errc.hpp")
    text = read(path)
    if MARKER in text:
        print(f"already patched: {path}")
        return
    text = insert_after(
        text,
        "#include <boost/config.hpp>\n",
        "\n#ifdef __COSMOPOLITAN__\n"
        "#include <cosmo_compat/cosmo_errno_compat.h>\n"
        "#endif\n",
    )
    text = replace_exactly_once(
        text,
        "    return error_code( e, generic_category() );",
        guarded_return(
            "    return error_code( e, generic_category() );",
            "    return error_code( cosmo_compat::native_errno("
            " static_cast<int>( e ) ), generic_category() );",
        ),
    )
    text = replace_exactly_once(
        text,
        "    return error_code( e, generic_category(), loc );",
        guarded_return(
            "    return error_code( e, generic_category(), loc );",
            "    return error_code( cosmo_compat::native_errno("
            " static_cast<int>( e ) ), generic_category(), loc );",
        ),
    )
    text = replace_exactly_once(
        text,
        "    return error_condition( e, generic_category() );",
        guarded_return(
            "    return error_condition( e, generic_category() );",
            "    return error_condition( cosmo_compat::native_errno("
            " static_cast<int>( e ) ), generic_category() );",
        ),
    )
    write(path, text)


def patch_error_condition(root):
    # error_condition has a fast-path constructor for errc::errc_t that
    # stores the enum value directly, bypassing make_error_condition.
    path = os.path.join(root, "boost/system/detail/error_condition.hpp")
    text = read(path)
    if MARKER in text:
        print(f"already patched: {path}")
        return
    text = insert_after(
        text,
        "#include <boost/system/is_error_condition_enum.hpp>\n",
        "\n#ifdef __COSMOPOLITAN__\n"
        "#include <cosmo_compat/cosmo_errno_compat.h>\n"
        "#endif\n",
    )
    old_ctor = (
        "      typename detail::enable_if<boost::system::detail::is_same"
        "<ErrorConditionEnum, errc::errc_t>::value>::type* = 0)"
        " BOOST_NOEXCEPT:\n"
        "        val_( e ), cat_( 0 )\n"
    )
    new_ctor = (
        "      typename detail::enable_if<boost::system::detail::is_same"
        "<ErrorConditionEnum, errc::errc_t>::value>::type* = 0)"
        " BOOST_NOEXCEPT:\n"
        "#ifdef __COSMOPOLITAN__\n"
        "        val_( cosmo_compat::native_errno( static_cast<int>( e ) ) ),"
        " cat_( 0 )\n"
        "#else\n"
        "        val_( e ), cat_( 0 )\n"
        "#endif\n"
    )
    text = replace_exactly_once(text, old_ctor, new_ctor)
    write(path, text)


def patch_asio_error(root):
    path = os.path.join(root, "boost/asio/error.hpp")
    text = read(path)
    if MARKER in text:
        print(f"already patched: {path}")
        return
    text = insert_before(text, "namespace boost {", PUSH_BLOCK + "\n")
    # only basic_errors is errno-based; netdb/addrinfo/misc values are
    # portable literals
    text = replace_exactly_once(
        text,
        "  return boost::system::error_code(\n"
        "      static_cast<int>(e), get_system_category());",
        guarded_return(
            "  return boost::system::error_code(\n"
            "      static_cast<int>(e), get_system_category());",
            "  return boost::system::error_code(\n"
            "      cosmo_compat::native_errno(static_cast<int>(e)),"
            " get_system_category());",
        ),
    )
    # pop before the trailing header-only impl include so that error.ipp
    # (runtime code) sees the real symbolic errno macros again
    text = insert_before(
        text, "#if defined(BOOST_ASIO_HEADER_ONLY)", POP_BLOCK + "\n"
    )
    write(path, text)


# Linux-sentinel values for the socket constants that are runtime symbols
# under Cosmopolitan but appear in Asio's compile-time contexts (enum
# initializers in socket_base.hpp, socket_option template arguments).
# Translated back to native values by cosmo_compat::native_sockopt() at the
# setsockopt/getsockopt funnel.
SOCKET_SENTINELS = [
    ("SOL_SOCKET", 1),
    ("SO_DEBUG", 1), ("SO_REUSEADDR", 2), ("SO_DONTROUTE", 5),
    ("SO_BROADCAST", 6), ("SO_SNDBUF", 7), ("SO_RCVBUF", 8),
    ("SO_KEEPALIVE", 9), ("SO_OOBINLINE", 10), ("SO_LINGER", 13),
    ("SO_RCVLOWAT", 18), ("SO_SNDLOWAT", 19),
    ("SOMAXCONN", 4096),
    ("MSG_EOR", 0x80),  # does not exist under cosmo; see compat header
    ("IP_TTL", 2), ("IP_MULTICAST_IF", 32), ("IP_MULTICAST_TTL", 33),
    ("IP_MULTICAST_LOOP", 34), ("IP_ADD_MEMBERSHIP", 35),
    ("IP_DROP_MEMBERSHIP", 36),
    ("IPV6_UNICAST_HOPS", 16), ("IPV6_MULTICAST_IF", 17),
    ("IPV6_MULTICAST_HOPS", 18), ("IPV6_MULTICAST_LOOP", 19),
    ("IPV6_JOIN_GROUP", 20), ("IPV6_LEAVE_GROUP", 21), ("IPV6_V6ONLY", 26),
    # signal_set_base flags; compile-time only (QLever never passes signal
    # flags to sigaction through Asio, so no runtime translation exists)
    ("SA_RESTART", 0x10000000), ("SA_NOCLDSTOP", 1), ("SA_NOCLDWAIT", 2),
]


def patch_socket_types(root):
    path = os.path.join(root, "boost/asio/detail/socket_types.hpp")
    text = read(path)
    if MARKER in text:
        print(f"already patched: {path}")
        return
    lines = [
        "",
        "#ifdef __COSMOPOLITAN__",
        "// cosmo_compat: these socket constants are runtime symbols under",
        "// Cosmopolitan and cannot be used in Asio's compile-time contexts.",
        "// Use Linux sentinels here; cosmo_compat::native_sockopt() translates",
        "// at the setsockopt/getsockopt funnel (see socket_ops.ipp).",
    ]
    for macro, value in SOCKET_SENTINELS:
        lines.append(f"#undef BOOST_ASIO_OS_DEF_{macro}")
        lines.append(f"#define BOOST_ASIO_OS_DEF_{macro} {value}")
    lines.append("#endif // __COSMOPOLITAN__")
    lines.append("")
    block = "\n".join(lines)
    last_endif = text.rindex("#endif")
    text = text[:last_endif] + block + "\n" + text[last_endif:]
    # IOV_MAX is a runtime symbol under Cosmopolitan and cannot initialize
    # the (enum-feeding) max_iov_len constant; use a conservative literal
    # (Asio caps scatter/gather arrays at 64 buffers anyway).
    text = replace_exactly_once(
        text,
        "# if defined(IOV_MAX)\nconst int max_iov_len = IOV_MAX;\n",
        "# if defined(__COSMOPOLITAN__)\n"
        "const int max_iov_len = 16;\n"
        "# elif defined(IOV_MAX)\n"
        "const int max_iov_len = IOV_MAX;\n",
    )
    write(path, text)


SOCKOPT_TRANSLATE = (
    "{\n#ifdef __COSMOPOLITAN__\n"
    "  cosmo_compat::native_sockopt(level, optname);\n"
    "#endif\n"
)


def patch_socket_ops(root):
    path = os.path.join(root, "boost/asio/detail/impl/socket_ops.ipp")
    text = read(path)
    if MARKER in text:
        print(f"already patched: {path}")
        return
    text = insert_before(
        text,
        "#include <boost/asio/detail/push_options.hpp>",
        "#ifdef __COSMOPOLITAN__\n"
        "#include <cosmo_compat/cosmo_socket_compat.h>\n"
        "#define if_indextoname cosmo_compat_if_indextoname\n"
        "#define if_nametoindex cosmo_compat_if_nametoindex\n"
        "#endif\n\n",
    )
    text = replace_exactly_once(
        text,
        "int setsockopt(socket_type s, state_type& state, int level,"
        " int optname,\n"
        "    const void* optval, std::size_t optlen,"
        " boost::system::error_code& ec)\n{\n",
        "int setsockopt(socket_type s, state_type& state, int level,"
        " int optname,\n"
        "    const void* optval, std::size_t optlen,"
        " boost::system::error_code& ec)\n" + SOCKOPT_TRANSLATE,
    )
    text = replace_exactly_once(
        text,
        "int getsockopt(socket_type s, state_type state, int level,"
        " int optname,\n"
        "    void* optval, size_t* optlen, boost::system::error_code& ec)\n{\n",
        "int getsockopt(socket_type s, state_type state, int level,"
        " int optname,\n"
        "    void* optval, size_t* optlen, boost::system::error_code& ec)\n"
        + SOCKOPT_TRANSLATE,
    )
    write(path, text)


def patch_v6_only(root):
    # ip/v6_only.hpp uses the raw IPPROTO_IPV6/IPV6_V6ONLY macros (not the
    # BOOST_ASIO_OS_DEF aliases) as template arguments.
    path = os.path.join(root, "boost/asio/ip/v6_only.hpp")
    text = read(path)
    if MARKER in text:
        print(f"already patched: {path}")
        return
    text = replace_exactly_once(
        text,
        "#elif defined(IPV6_V6ONLY)\n"
        "typedef boost::asio::detail::socket_option::boolean<\n"
        "    IPPROTO_IPV6, IPV6_V6ONLY> v6_only;\n",
        "#elif defined(__COSMOPOLITAN__)\n"
        "// cosmo_compat: Linux sentinels (IPPROTO_IPV6=41, IPV6_V6ONLY=26),\n"
        "// translated at runtime by cosmo_compat::native_sockopt().\n"
        "typedef boost::asio::detail::socket_option::boolean<41, 26> v6_only;\n"
        "#elif defined(IPV6_V6ONLY)\n"
        "typedef boost::asio::detail::socket_option::boolean<\n"
        "    IPPROTO_IPV6, IPV6_V6ONLY> v6_only;\n",
    )
    write(path, text)


def main():
    root = sys.argv[1]
    patch_system_detail_errc(root)
    patch_system_errc(root)
    patch_error_condition(root)
    patch_asio_error(root)
    patch_socket_types(root)
    patch_socket_ops(root)
    patch_v6_only(root)


if __name__ == "__main__":
    main()
