// Copyright 2026, University of Freiburg,
// Chair of Algorithms and Data Structures.

/*
 * Generic `std::char_traits` implementation for non-character types.
 *
 * libc++ >= 18 (used e.g. by the Cosmopolitan toolchain) removed the generic
 * base template of `std::char_traits`, so instantiating `std::basic_string` /
 * `std::basic_string_view` with a non-character type (as QLever does with
 * `NormalizedChar` and `uint8_t`) no longer compiles there. This header
 * provides a standards-conforming traits implementation that specializations
 * can inherit from; the members are instantiated lazily, so types for which
 * e.g. `to_char_type` makes no sense still work as string content types.
 *
 * On libstdc++ the generic base template still exists, but defining the
 * specializations unconditionally is harmless and keeps behavior identical
 * across standard libraries (for `NormalizedChar` the specialization is
 * required to be legal anyway, as it involves a program-defined type).
 */

#ifndef QLEVER_SRC_BACKPORTS_CHAR_TRAITS_H
#define QLEVER_SRC_BACKPORTS_CHAR_TRAITS_H

#include <cstddef>
#include <cwchar>
#include <ios>

namespace ql {

template <typename CharT>
struct GenericCharTraits {
  using char_type = CharT;
  using int_type = unsigned long;
  using off_type = std::streamoff;
  using pos_type = std::streampos;
  using state_type = std::mbstate_t;

  static constexpr void assign(char_type& r, const char_type& a) noexcept {
    r = a;
  }
  static constexpr bool eq(const char_type& a, const char_type& b) noexcept {
    return a == b;
  }
  static constexpr bool lt(const char_type& a, const char_type& b) noexcept {
    return a < b;
  }
  static constexpr int compare(const char_type* s1, const char_type* s2,
                               std::size_t n) noexcept {
    for (std::size_t i = 0; i < n; ++i) {
      if (lt(s1[i], s2[i])) {
        return -1;
      }
      if (lt(s2[i], s1[i])) {
        return 1;
      }
    }
    return 0;
  }
  static constexpr std::size_t length(const char_type* s) noexcept {
    std::size_t len = 0;
    while (!eq(s[len], char_type())) {
      ++len;
    }
    return len;
  }
  static constexpr const char_type* find(const char_type* s, std::size_t n,
                                         const char_type& a) noexcept {
    for (std::size_t i = 0; i < n; ++i) {
      if (eq(s[i], a)) {
        return s + i;
      }
    }
    return nullptr;
  }
  static constexpr char_type* move(char_type* s1, const char_type* s2,
                                   std::size_t n) noexcept {
    if (s1 < s2) {
      for (std::size_t i = 0; i < n; ++i) {
        assign(s1[i], s2[i]);
      }
    } else if (s2 < s1) {
      for (std::size_t i = n; i > 0; --i) {
        assign(s1[i - 1], s2[i - 1]);
      }
    }
    return s1;
  }
  static constexpr char_type* copy(char_type* s1, const char_type* s2,
                                   std::size_t n) noexcept {
    for (std::size_t i = 0; i < n; ++i) {
      assign(s1[i], s2[i]);
    }
    return s1;
  }
  static constexpr char_type* assign(char_type* s, std::size_t n,
                                     char_type a) noexcept {
    for (std::size_t i = 0; i < n; ++i) {
      assign(s[i], a);
    }
    return s;
  }
  // The following members are only required by iostreams and are therefore
  // never instantiated for pure string/string_view content types.
  static constexpr int_type eof() noexcept { return static_cast<int_type>(-1); }
  static constexpr int_type not_eof(int_type c) noexcept {
    return eq_int_type(c, eof()) ? 0 : c;
  }
  static constexpr char_type to_char_type(int_type c) noexcept {
    return static_cast<char_type>(c);
  }
  static constexpr int_type to_int_type(char_type c) noexcept {
    return static_cast<int_type>(c);
  }
  static constexpr bool eq_int_type(int_type c1, int_type c2) noexcept {
    return c1 == c2;
  }
};

}  // namespace ql

#endif  // QLEVER_SRC_BACKPORTS_CHAR_TRAITS_H
