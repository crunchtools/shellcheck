# crunchtools/shellcheck

[ShellCheck](https://www.shellcheck.net) v0.11.0, built from upstream source.
Published as `quay.io/crunchtools/shellcheck`. The entrypoint is `shellcheck`.

## Why

Our rule is that images come only from `quay.io/crunchtools`, Red Hat's
registries and Hummingbird. We used `docker.io/koalaman/shellcheck`, which is
none of those, and nothing in those registries ships ShellCheck. So we build it.

## How it is built

ShellCheck is Haskell, and no Red Hat or Hummingbird image ships GHC. The
Containerfile builds on UBI 10, downloads the official GHC 9.8.4 and
cabal-install 3.12.1.0 binary distributions from downloads.haskell.org (each
pinned by version and sha256), fetches the `v0.11.0` tag (refused unless it is
the pinned commit), and builds with cabal against Hackage pinned at an
`index-state` and the committed `cabal.project.freeze`. The result is copied
with `libgmp.so.10` onto `hi/core-runtime`, glibc only. Upstream's fully static
binary needs static gmp and glibc, which UBI 10 does not ship. The image is built
by GitHub Actions, never by hand.

To bump ShellCheck: change the version and commit ARGs, regenerate
`cabal.project.freeze` (`cabal freeze` in the source stage) and move
`index-state` in both `cabal.project` and the Containerfile.

## Verify the signature

The release is signed with the fleet key, which lives in the constitution repo:

```
cosign verify --insecure-ignore-tlog \
  --key https://raw.githubusercontent.com/crunchtools/constitution/main/keys/crunchtools-bootc.pub \
  quay.io/crunchtools/shellcheck:latest
```

## Use

```
podman run --rm -v .:/mnt:ro,z -w /mnt quay.io/crunchtools/shellcheck:latest a.sh b.sh
```

Exit status and output match the upstream image's. Licensed GPL-3.0-only
(ShellCheck) and AGPL-3.0-or-later (this repo).
