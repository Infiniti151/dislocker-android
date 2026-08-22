# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Infiniti151

FROM registry.fedoraproject.org/fedora:44

ARG TERMUX_FUSE3_VERSION=3.16.2-1
ARG TERMUX_FUSE3_URL=https://packages.termux.dev/apt/termux-root/pool/stable/libf/libfuse3/libfuse3_${TERMUX_FUSE3_VERSION}_aarch64.deb

RUN dnf update -y && \
    dnf install -y \
        cmake \
        git \
        wget \
        unzip \
        pkg-config \
        file \
        apt-utils \
        dpkg \
        dpkg-dev && \
    dnf clean all

# ---------------------------------------------------------------------------
# Termux FUSE 3 development files
# ---------------------------------------------------------------------------

RUN mkdir -p /opt/termux-fuse3 && \
    wget -O /tmp/libfuse3.deb "$TERMUX_FUSE3_URL" && \
    dpkg-deb -x /tmp/libfuse3.deb /opt/termux-fuse3 && \
    rm -f /tmp/libfuse3.deb

WORKDIR /workspace

RUN mkdir -p /workspace/output /workspace/cache