# Using the QLever APE binaries

The release artifacts `qlever-index`, `qlever-server` and
`PrintIndexVersionMain` are [Actually Portable
Executables](https://justine.lol/ape.html): each file is simultaneously a
valid Linux/FreeBSD/OpenBSD/NetBSD ELF, a macOS Mach-O, a Windows PE and a
POSIX shell script, containing fat x86_64 + aarch64 code. There is no
installer, no runtime, and no dependency to set up — the ICU data archive
(`icudt76l.dat`) is embedded inside each binary's zip section and found
automatically at `/zip/icu`.

## Quick start

```sh
# fetch (curl avoids browser quarantine attributes on macOS)
curl -LO https://github.com/SEBK4C/qlever-cosmopolitan/releases/latest/download/qlever-index
curl -LO https://github.com/SEBK4C/qlever-cosmopolitan/releases/latest/download/qlever-server
chmod +x qlever-index qlever-server

# build an index from an RDF file (Turtle/NTriples)
./qlever-index -i myindex -F ttl -f mydata.ttl

# serve it
./qlever-server -i myindex -p 7001 -m 4GB

# query it
curl -s http://localhost:7001 \
  --data-urlencode 'query=SELECT * WHERE { ?s ?p ?o } LIMIT 5' \
  -H 'Accept: application/sparql-results+json'
```

All regular QLever options work as documented upstream
(`--help` for the full list).

## Platform notes

| Platform | How to run |
|---|---|
| Linux (x86_64, aarch64) | `./qlever-server …` directly. If your system has a conflicting `binfmt_misc` handler for `MZ` files (e.g. WINE), either run via `sh ./qlever-server …` or [register the APE loader](https://github.com/jart/cosmopolitan/blob/master/ape/apeinstall.sh). |
| macOS (Intel, Apple Silicon) | `./qlever-server …`. If downloaded with a browser instead of curl, clear quarantine first: `xattr -d com.apple.quarantine qlever-server`. |
| Windows (x86_64) | Rename to `qlever-server.exe` and run from cmd/PowerShell. |
| FreeBSD / OpenBSD / NetBSD | `./qlever-server …` (or `sh ./qlever-server …`). |

`sh ./qlever-server` works on every POSIX system regardless of kernel
configuration — the file's header is a shell script that bootstraps the
embedded loader.

On first run the APE loader may extract itself to `~/.ape-*`; this is
normal and happens once.

### Converting to a plain native binary

If you prefer a regular platform-native executable (e.g. for containers or
tools that `exec` the binary directly), assimilate it in place:

```sh
# from the cosmocc toolchain (https://cosmo.zip/pub/cosmocc/)
assimilate -x qlever-server   # -x = ELF x86_64; see --help for other targets
```

This is one-way: the file stops being portable.

## Things to know

- **ICU data is embedded.** Unicode collation and locale handling work with
  zero setup. The binaries' zip section can be inspected with any unzip
  tool (`unzip -l qlever-server`), but only modify it with an APE-aware
  `zip` (https://cosmo.zip/pub/cosmos/bin/zip) — a stock Info-ZIP mangles
  the header.
- **Memory**: `qlever-server -m` caps query memory; index building of large
  datasets is memory-hungry exactly like upstream QLever.
- **Allocator**: these builds use Cosmopolitan's malloc; upstream's
  optional jemalloc is not included. IndexBuilder throughput on huge
  datasets has not yet been benchmarked against native builds.
- **Test status**: the Linux x86_64 build path is exercised by QLever's e2e
  suite (scientists collection, all checked queries). Other OSes/arches
  are expected to work by APE construction but have not been part of the
  conformance gate yet — reports welcome.

## Versioning

The binaries are built from this fork at the commit recorded in the release
notes (upstream base: ad-freiburg/qlever). `PrintIndexVersionMain` prints
the index-format version JSON; index files are interchangeable with a
native QLever build of the same upstream commit.
