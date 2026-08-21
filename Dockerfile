# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Infiniti151

FROM registry.fedoraproject.org/fedora:44

RUN dnf update -y && \
    dnf install -y \
        gcc \
        gcc-c++ \
        clang \
        libcxx \
        libcxx-devel \
        lld \
        cmake \
        meson \
        make \
        ninja-build \
        git \
        wget \
        unzip \
        pkg-config \
        autoconf \
        automake \
        libtool \
        fuse-devel \
        fuse3-devel \
        mbedtls-devel \
        perl-FindBin \
        perl-IPC-Cmd \
        ruby-devel \
        openssl-devel \
        gcc-arm-linux-gnu \
        gcc-c++-arm-linux-gnu \
        binutils-arm-linux-gnu \
        file \
        dpkg \
        dpkg-dev \
        apt-utils \
        fakeroot \
        pinentry-tty \
        gnupg2-smime && \
    dnf clean all

WORKDIR /workspace

RUN mkdir -p /workspace/output /workspace/cache