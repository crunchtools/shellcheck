# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial image: ShellCheck v0.11.0 built from upstream source, replacing
  `docker.io/koalaman/shellcheck:v0.11.0` in our tooling. The tag is fetched
  and refused unless it is commit `aac0823e`. The build runs on
  `registry.access.redhat.com/ubi10/ubi:10.3` (pinned by digest) with GHC 9.8.4
  and cabal-install 3.12.1.0 from downloads.haskell.org, each pinned by version
  and sha256, against Hackage pinned at index-state `2026-11-25T23:58:12Z` and
  a committed `cabal.project.freeze`.
- The runtime is `registry.access.redhat.com/hi/core-runtime` plus the one
  library the binary needs beyond glibc, `libgmp.so.10`, copied from the
  builder. A fully static binary (upstream's) needs static gmp and glibc, which
  UBI 10 does not ship.
- Entrypoint is `/usr/local/bin/shellcheck` (root-owned, 0555), user `65532:0`,
  `WORKDIR /mnt`, so `podman run --rm -v .:/mnt:ro,z -w /mnt <image> a.sh` works.
- `image-contract` check: the binary against a clean fixture.
