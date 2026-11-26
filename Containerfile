# ShellCheck, built from upstream source as a crunchtools image.
#
# WHY THIS REPO EXISTS. Our tooling ran docker.io/koalaman/shellcheck, a binary
# upstream built on Alpine and wrapped in `FROM scratch`. The image gate trusts
# parents from quay.io/crunchtools, Red Hat's registries and Hummingbird only
# (a1334), and nothing there ships ShellCheck. So the same release is built here.
#
# WHY A UBI BUILDER, AND A DOWNLOADED GHC. ShellCheck is Haskell. No Red Hat or
# Hummingbird image ships GHC, and UBI's repositories carry neither GHC nor
# cabal. So the builder is UBI 10, and GHC and cabal-install are the official
# binary distributions from downloads.haskell.org, each pinned by version AND
# sha256 (the values published in the SHA256SUMS next to them), so a replaced
# tarball fails the build instead of entering it. The "rocky8" bindist is the
# RHEL-family one: it needs only glibc, gmp, ncurses and libnuma, all in UBI 10.
#
#   - ShellCheck v0.11.0, fetched by tag and refused unless HEAD is the commit
#     the (annotated) tag points at: a moved tag cannot change what is built.
#   - GHC 9.8.4. ShellCheck.cabal's bounds are written against GHC 7.10.3
#     through 9.12.1, and upstream's own release builder (builders/linux.x86_64)
#     uses GHC 9.8.2; 9.8.4 is that series' last release.
#   - cabal-install 3.12.1.0, the release that goes with GHC 9.8.
#   - Hackage pinned at INDEX_STATE, plus the cabal.project.freeze committed in
#     this repo (every dependency, exact version and flag set), so the same
#     inputs resolve to the same package versions on every build. Cabal
#     verifies each package's tarball against the hash the index records.
#   - upstream's own steps: `striptests` (drops the in-source QuickCheck tests,
#     as its release build does), -split-sections and --gc-sections, strip.
#
# The release is named once, here; the stages re-declare these without a default
# so a bump cannot build one release and label it as another.
ARG SHELLCHECK_VERSION=0.11.0
# `git ls-remote https://github.com/koalaman/shellcheck 'refs/tags/v0.11.0*'`,
# the peeled (^{}) line: the commit the annotated tag points at.
ARG SHELLCHECK_COMMIT=aac0823e6b58f8a499e856e93738082691cbf212

FROM registry.access.redhat.com/ubi10/ubi:10.3@sha256:87ceab8634a53a36c75a8ba7282f09f11c46ab3e8906db6c6d2b3cd2a7dc4f4e AS toolchain

ARG GHC_VERSION=9.8.4
ARG GHC_SHA256=7e10f00bdc9e552d9fc3d330b27681b340b0653df4741983b49937c2b533a5c4
ARG CABAL_VERSION=3.12.1.0
ARG CABAL_SHA256=24f0a74ba6269204e108327b925de2202e1bfdddb3bd020174a1d76a7feaf42f

# What GHC's `./configure && make install` and the link step need: a C
# toolchain, gmp and ncurses (headers for linking, runtime for GHC itself),
# libffi, libnuma (the rocky8 bindist's RTS links it), perl and xz for the
# unpacking, git for the source. UBI's unentitled repositories carry all of it.
RUN dnf -y --setopt=install_weak_deps=False install \
        gcc gcc-c++ make binutils perl-interpreter xz tar gzip diffutils findutils \
        git-core ca-certificates \
        gmp-devel ncurses-devel libffi-devel zlib-devel numactl-libs \
    && dnf clean all

WORKDIR /tmp/dl
RUN curl -fsSL -o ghc.tar.xz "https://downloads.haskell.org/~ghc/$GHC_VERSION/ghc-$GHC_VERSION-x86_64-rocky8-linux.tar.xz" \
    && echo "$GHC_SHA256  ghc.tar.xz" | sha256sum -c - \
    && tar -xJf ghc.tar.xz \
    && cd "ghc-$GHC_VERSION-x86_64-unknown-linux" \
    && ./configure --prefix=/opt/ghc \
    && make install \
    && cd / && rm -rf /tmp/dl/ghc*
RUN curl -fsSL -o cabal.tar.xz "https://downloads.haskell.org/~cabal/cabal-install-$CABAL_VERSION/cabal-install-$CABAL_VERSION-x86_64-linux-rocky8.tar.xz" \
    && echo "$CABAL_SHA256  cabal.tar.xz" | sha256sum -c - \
    && tar -xJf cabal.tar.xz -C /usr/local/bin cabal \
    && rm -f cabal.tar.xz

ENV PATH=/opt/ghc/bin:$PATH
RUN test "$(ghc --numeric-version)" = "$GHC_VERSION" \
    && test "$(cabal --numeric-version)" = "$CABAL_VERSION"

FROM toolchain AS source

ARG SHELLCHECK_VERSION
ARG SHELLCHECK_COMMIT

WORKDIR /src/shellcheck
RUN git init -q . \
    && git fetch -q --depth 1 https://github.com/koalaman/shellcheck \
        "refs/tags/v$SHELLCHECK_VERSION:refs/tags/v$SHELLCHECK_VERSION" \
    && git checkout -q --detach "v$SHELLCHECK_VERSION" \
    && test "$(git rev-parse HEAD)" = "$SHELLCHECK_COMMIT"

FROM source AS build

ARG SHELLCHECK_VERSION
ARG SHELLCHECK_COMMIT

# One timestamp for the whole Hackage index; cabal.project carries the same
# value, and this build refuses to run if they disagree.
ARG INDEX_STATE=2026-11-25T23:58:12Z

COPY cabal.project cabal.project.freeze ./
RUN grep -qx "index-state: $INDEX_STATE" cabal.project \
    && test "$(git rev-parse HEAD)" = "$SHELLCHECK_COMMIT" \
    && ./striptests \
    && cabal update "hackage.haskell.org,$INDEX_STATE" \
    && cabal build \
        --ghc-options=-split-sections --ghc-options=-optc-Os --ghc-options=-optc-Wl,--gc-sections \
        exe:shellcheck \
    && install -D -m 0555 "$(cabal list-bin exe:shellcheck)" /out/shellcheck \
    && strip -s /out/shellcheck \
    && /out/shellcheck --version | tee /dev/stderr | grep -qx "version: $SHELLCHECK_VERSION"

# WHICH LIBRARIES THE BINARY NEEDS. A fully static binary (what upstream ships)
# needs static libgmp and libc, and UBI 10 has neither: gmp-static is in no
# repository, and glibc-static is codeready-builder only. So the binary is
# dynamic, and `ldd` says exactly what it wants. The list below is checked
# against it: every library not already in the runtime image is copied across.
RUN ldd /out/shellcheck >&2 \
    && extra=$(ldd /out/shellcheck | awk '{print $1}' \
        | grep -vxE 'linux-vdso\.so\.1|libm\.so\.6|libgmp\.so\.10|libc\.so\.6|/lib64/ld-linux-x86-64\.so\.2' || true) \
    && { test -z "$extra" || { echo "shellcheck links libraries this image does not carry: $extra" >&2; exit 1; }; } \
    && cp -L /usr/lib64/libgmp.so.10 /out/libgmp.so.10

# hi/core-runtime is glibc and nothing else (no gmp, no libffi, no shell, no
# grep), so the one library ShellCheck's Haskell runtime needs beyond libc, libgmp, is
# copied from this builder. Not hi/static: that has no libc to load a dynamic
# binary against.
FROM registry.access.redhat.com/hi/core-runtime@sha256:fe49c1e94db2743f99ea08d7bec7b7326595130463f76dd32308e6e122361149

LABEL maintainer="fatherlinux <scott.mccarty@crunchtools.com>"
LABEL description="ShellCheck 0.11.0, built from upstream source; the entrypoint is shellcheck"
LABEL org.opencontainers.image.title="crunchtools/shellcheck"
LABEL org.opencontainers.image.description="ShellCheck 0.11.0 built from the upstream v0.11.0 tag with GHC 9.8.4 and a frozen Hackage"
LABEL org.opencontainers.image.source="https://github.com/crunchtools/shellcheck"
# ShellCheck is GPLv3 (GPL-3.0-only); this repo's own files (Containerfile,
# scaffolding) are AGPL-3.0-or-later like every crunchtools repo.
LABEL org.opencontainers.image.licenses="GPL-3.0-only AND AGPL-3.0-or-later"
LABEL org.opencontainers.image.vendor="Crunchtools"
LABEL org.opencontainers.image.base.name="registry.access.redhat.com/hi/core-runtime@sha256:fe49c1e94db2743f99ea08d7bec7b7326595130463f76dd32308e6e122361149"

COPY --from=build --chown=0:0 --chmod=0555 /out/shellcheck /usr/local/bin/shellcheck
COPY --from=build --chown=0:0 --chmod=0555 /out/libgmp.so.10 /usr/lib64/libgmp.so.10

# 65532:0 is the Hummingbird convention: unprivileged, group 0 so an arbitrary
# uid from a user namespace still works. Consumers mount the checkout read-only
# at /mnt and run `podman run ... <image> file.sh`, so the entrypoint IS
# shellcheck and WORKDIR is where the files are.
USER 65532:0
WORKDIR /mnt
ENTRYPOINT ["/usr/local/bin/shellcheck"]
