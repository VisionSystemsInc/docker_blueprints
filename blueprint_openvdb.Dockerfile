# syntax=docker/dockerfile:1.4

ARG BASE_IMAGE="quay.io/pypa/manylinux_2_28_x86_64:2025.09.28-1"
ARG VSI_RECIPE_REPO="vsiri/recipe"

# docker recipes
FROM ${VSI_RECIPE_REPO}:cuda AS cuda

# main builder stage
FROM ${BASE_IMAGE} AS builder

# update shell
SHELL ["/usr/bin/env", "/bin/bash", "-euxvc"]

# install CUDA (only used when NANOVDB_USE_CUDA=ON)
ARG CUDA_RECIPE_TARGET="devel"
COPY --from=cuda /usr/local /usr/local
RUN shopt -s nullglob; for patch in /usr/local/share/just/container_build_patch/*; do "${patch}"; done

# dependencies
RUN dnf install -y \
        ninja-build \
        zlib-devel \
        ; \
    rm -rf /var/cache/dnf/*

# oneTBB (system tbb-devel on EL8 is 2018, OpenVDB requires >= 2021)
# https://github.com/uxlfoundation/oneTBB/tags
ARG TBB_VERSION="v2022.3.0"
RUN git clone --depth 1 -b "${TBB_VERSION}" https://github.com/uxlfoundation/oneTBB.git /tmp/tbb; \
    cmake \
        -S /tmp/tbb \
        -B /tmp/tbb/build \
        -G Ninja \
        -D CMAKE_BUILD_TYPE=Release \
        -D CMAKE_INSTALL_PREFIX=/usr/local \
        -D TBB_TEST=OFF \
        -D TBB_EXAMPLES=OFF \
        -D TBB_STRICT=OFF \
        ; \
    cmake --build /tmp/tbb/build --target install; \
    rm -rf /tmp/*

# zstd (system libzstd-devel on EL8 is 1.4.4, OpenVDB>=14 requires >= 1.5.2)
# https://github.com/facebook/zstd/tags
ARG ZSTD_VERSION="v1.5.7"
RUN git clone --depth 1 -b "${ZSTD_VERSION}" https://github.com/facebook/zstd.git /tmp/zstd; \
    cmake \
        -S /tmp/zstd/build/cmake \
        -B /tmp/zstd/build/cmake/build \
        -G Ninja \
        -D CMAKE_BUILD_TYPE=Release \
        -D CMAKE_INSTALL_PREFIX=/usr/local \
        -D ZSTD_BUILD_PROGRAMS=OFF \
        -D ZSTD_BUILD_TESTS=OFF \
        -D ZSTD_BUILD_STATIC=OFF \
        ; \
    cmake --build /tmp/zstd/build/cmake/build --target install; \
    rm -rf /tmp/*

# clone
# https://github.com/AcademySoftwareFoundation/openvdb/tags
ARG OPENVDB_VERSION="v14.0.0"
RUN git clone https://github.com/AcademySoftwareFoundation/openvdb.git /openvdb/source; \
    git -C /openvdb/source checkout "${OPENVDB_VERSION}";

# python venv & build dependencies
ARG PYTHON_VERSION="3.13.12"
RUN \
    # manylinux python directory
    python_major=${PYTHON_VERSION%%.*}; \
    python_minor=${PYTHON_VERSION#*.}; \
    python_minor=${python_minor%%.*}; \
    python_dir=("/opt/python/cp${python_major}${python_minor}-"cp*[0-9m]); \
    #
    # create python venv & add build dependencies
    # (see [build-system] in openvdb's pyproject.toml)
    "${python_dir}/bin/python3" -m venv /venv; \
    source /venv/bin/activate; \
    pip install \
        cmake \
        nanobind \
        ninja \
        numpy \
        scikit-build-core \
        ;

# build wheel
#
# OpenVDB's top-level pyproject.toml (scikit-build-core) produces a single
# "openvdb" wheel that contains both the `openvdb` and `nanovdb` python
# packages, along with libopenvdb.so.
#
# set NANOVDB_USE_CUDA=ON to build the nanovdb CUDA functionality
# (nanovdb.cuda). Use NANOVDB_CUDA_ARCHITECTURES to control the CUDA
# architectures.
ARG NANOVDB_USE_CUDA="OFF"
ARG NANOVDB_CUDA_ARCHITECTURES="75;86"
ARG NINJA_BUILD_CONCURRENCY=
RUN source /venv/bin/activate; \
    mkdir -p /wheelhouse-tmp; \
    #
    # parallel build
    export CMAKE_BUILD_PARALLEL_LEVEL="${NINJA_BUILD_CONCURRENCY:-$(nproc)}"; \
    #
    # cmake options, layered on top of [tool.scikit-build.cmake.define]
    CMAKE_DEFINES=( \
        CMAKE_PREFIX_PATH="/usr/local" \
        nanobind_DIR="$(python -m nanobind --cmake_dir)" \
        # no command line tools in the wheel
        OPENVDB_BUILD_BINARIES=OFF \
        NANOVDB_BUILD_TOOLS=OFF \
        USE_CCACHE=OFF \
        # nanovdb cuda support
        NANOVDB_USE_CUDA="${NANOVDB_USE_CUDA}" \
    ); \
    if [ "${NANOVDB_USE_CUDA}" == "ON" ]; then \
      CMAKE_DEFINES+=( \
        CMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc \
        CMAKE_CUDA_ARCHITECTURES="${NANOVDB_CUDA_ARCHITECTURES}" \
      ); \
    fi; \
    #
    # build wheel
    pip wheel /openvdb/source -w /wheelhouse-tmp -v --no-deps --no-build-isolation \
        -C build-dir=/openvdb/build \
        $(printf -- '-Ccmake.define.%s ' "${CMAKE_DEFINES[@]}");

# auditwheel, excluding cuda driver library
RUN EXCLUDE=( \
        # cuda libraries
        libcuda.so.1 \
        libcudart.so.* \
    ); \
    mkdir -p /wheelhouse; \
    export LD_LIBRARY_PATH="/usr/local/lib64:/usr/local/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"; \
    auditwheel repair /wheelhouse-tmp/*.whl -w /wheelhouse \
        $(printf -- '--exclude %s ' "${EXCLUDE[@]}");

# copy output to /usr/local
FROM scratch

COPY --from=builder /wheelhouse /usr/local/share/just/wheels
