# syntax=docker/dockerfile:1.4

ARG BASE_IMAGE="quay.io/pypa/manylinux_2_28_x86_64:2025.09.28-1"
ARG VSI_RECIPE_REPO="vsiri/recipe"

# docker recipes
FROM ${VSI_RECIPE_REPO}:cuda AS cuda

# main builder stage
FROM ${BASE_IMAGE} AS builder

# update shell
SHELL ["/usr/bin/env", "/bin/bash", "-euxvc"]

# install CUDA
ARG CUDA_RECIPE_TARGET="devel"
COPY --from=cuda /usr/local /usr/local
RUN shopt -s nullglob; for patch in /usr/local/share/just/container_build_patch/*; do "${patch}"; done

# dependencies
RUN dnf install -y \
        libXcursor-devel \
        libXinerama-devel \
        libXi-devel \
        libxkbcommon-devel \
        libXrandr-devel \
        mesa-libGLU-devel \
        wayland-devel \
        # could be used to speed build via USE_SYSTEM_* cmake options,
        # however open3d seems to use a lot of custom versions/patches
        # libcurl-devel \
        # libjpeg-turbo-devel \
        # openssl-devel \
        ; \
    rm -rf /var/cache/dnf/*

# clone
ARG OPEN3D_VERSION="v0.19.0"
RUN git clone https://github.com/isl-org/Open3D.git /open3d/source; \
    git -C /open3d/source checkout "${OPEN3D_VERSION}";

# workarounds
RUN cd /open3d/source; \
    # remove Development.Embed from find_package(python)
    sed -i 's|COMPONENTS Interpreter Development)|COMPONENTS Interpreter Development.Module)|g' \
        ./CMakeLists.txt; \
    # stdgpu library directory
    sed -i 's|/lib|/lib64|g' ./3rdparty/stdgpu/stdgpu.cmake; \
    # remove "-DPYTHON_EXTRA_LIBRARIES" as this will be handled by auditwheel
    sed -i 's/^[^#]*-DPYTHON_EXTRA_LIBRARIES/#&/' \
        ./cpp/pybind/CMakeLists.txt; \
    # additionally print openssl in configuration summary
    sed -i 's/ZeroMQ/ZeroMQ openssl/g' \
        ./cmake/Open3DPrintConfigurationSummary.cmake; \
    # avoid "open3d-cpu" even when building without GPU capabilities
    sed -i 's/name += "-cpu"/#&/g' ./python/setup.py; \
    # don't artifically name the python wheel "manylinux"
    sed -i 's/plat = f"manylinux/#&/g' ./python/setup.py; \
    # complete!
    echo "workarounds complete";

# python venv
ARG PYTHON_VERSION="3.13.12"
RUN \
    # manylinux python directory
    python_major=${PYTHON_VERSION%%.*}; \
    python_minor=${PYTHON_VERSION#*.}; \
    python_minor=${python_minor%%.*}; \
    python_dir=("/opt/python/cp${python_major}${python_minor}-"cp*[0-9m]); \
    #
    # create python venv & add build dependencies
    "${python_dir}/bin/python3" -m venv /venv; \
    source /venv/bin/activate; \
    pip install \
        ninja \
        setuptools \
        # avoid CMAKE_POLICY_VERSION_MINIMUM issues for 3rd party dependencies
        "cmake<4" \
        # USE_SYSTEM_PYBIND11 cmake option
        # note pybind11 3.0 appears to require open3d>0.19.0
        "pybind11[global]<3" \
        ;

# build twice - once for CPU, once for GPU
# https://github.com/isl-org/Open3D/issues/4371#issuecomment-985943887
#
# Note the two builds don't play well with BUILD_SHARED_LIBS=ON, as both cpu
# and gpu builds produce identically named libopen3d.so files with different
# capabilities, but only one gets loaded at runtime.
#
# set BUILD_CUDA_MODULE=ON to build cuda capabilities. Note this will
# increase the installed python package size by nearly 1GB.
# Use CMAKE_CUDA_ARCHITECTURES to control the CUDA architectures.

# setup
RUN \
    # create build directory
    mkdir -p /open3d/build; \
    # common cmake options saved to disk
    CMAKE_COMMON_OPTS=( \
        -S /open3d/source \
        # -B /open3d/build \
        -G Ninja \
        -D BUILD_GUI=OFF \
        -D BUILD_WEBRTC=OFF \
        -D BUILD_EXAMPLES=OFF \
        # disable hash on build version
        -D DEVELOPER_BUILD=OFF \
        # python options
        -D BUILD_PYTHON_MODULE=ON \
        -D Python3_ROOT=/venv \
        # system packages to speed build process
        # see notes above regarding adding these system packages
        # -D USE_SYSTEM_CURL=ON \
        # -D USE_SYSTEM_JPEG=ON \
        # -D USE_SYSTEM_OPENSSL=ON \
        -D USE_SYSTEM_PYBIND11=ON \
    ); \
    declare -p CMAKE_COMMON_OPTS > /open3d/common.sh

# CPU build
ARG NINJA_BUILD_CONCURRENCY=
RUN cd /open3d/build; \
    source /venv/bin/activate; \
    source /open3d/common.sh; \
    cmake "${CMAKE_COMMON_OPTS[@]}" | tee -a /open3d/config-cpu.log; \
    ninja ${NINJA_BUILD_CONCURRENCY:+ -j${NINJA_BUILD_CONCURRENCY}};

# GPU build
ARG BUILD_CUDA_MODULE=OFF
ARG CMAKE_CUDA_ARCHITECTURES=86-real

RUN if [ "${BUILD_CUDA_MODULE}" == "ON" ]; then \
        cd /open3d/build; \
        source /venv/bin/activate; \
        source /open3d/common.sh; \
        cmake \
            "${CMAKE_COMMON_OPTS[@]}" \
            -D CMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc \
            -D BUILD_CUDA_MODULE=ON \
            -D CMAKE_CUDA_ARCHITECTURES="${CMAKE_CUDA_ARCHITECTURES}" \
            | tee -a /open3d/config-gpu.log; \
        ninja ${NINJA_BUILD_CONCURRENCY:+ -j${NINJA_BUILD_CONCURRENCY}}; \
    fi;

# build `pip-package` cmake target to create base python wheel
RUN source /venv/bin/activate; \
    cd /open3d/build; \
    ninja pip-package ${NINJA_BUILD_CONCURRENCY:+ -j${NINJA_BUILD_CONCURRENCY}};

# auditwheel
RUN \
    # add libtbb.so to LD_LIBRARY_PATH
    TBB_SO="$(find /open3d/build -name 'libtbb.so' | head -n1)"; \
    TBB_LIBRARY_PATH="$(dirname "${TBB_SO}")"; \
    export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}:}${TBB_LIBRARY_PATH}"; \
    # auditwheel
    mkdir -p /wheelhouse; \
    SOURCE_WHEEL="$(find /open3d/build -type f -name '*.whl' | head -n1)"; \
    auditwheel repair "${SOURCE_WHEEL}" -w /wheelhouse;

# final wheel in clean environment
FROM scratch

COPY --from=builder /wheelhouse /usr/local/share/just/wheels
