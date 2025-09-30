# syntax=docker/dockerfile:1.4

ARG BASE_IMAGE="quay.io/pypa/manylinux_2_28_x86_64"
ARG VSI_RECIPE_REPO="vsiri/recipe"

# docker recipes
FROM ${VSI_RECIPE_REPO}:cuda AS cuda

# main builder stage
FROM ${BASE_IMAGE} AS builder

# update shell
SHELL ["/usr/bin/env", "/bin/bash", "-euxvc"]

# cache directory (redirect pip cache to `/cache/pip`)
ENV XDG_CACHE_HOME="/cache"

# install CUDA
ARG CUDA_RECIPE_TARGET="devel"
COPY --from=cuda /usr/local /usr/local
RUN shopt -s nullglob; for patch in /usr/local/share/just/container_build_patch/*; do "${patch}"; done

# dependencies
RUN dnf install -y \
        ninja-build \
        gcc-toolset-11 \
        git \
        ; \
    rm -rf /var/cache/yum/*

# python & wheelhouse setup
ARG PYTHON_VERSION="3.10.15"
RUN python_major=${PYTHON_VERSION%%.*}; \
    python_minor=${PYTHON_VERSION#*.}; \
    python_minor=${python_minor%%.*}; \
    python_dir=("/opt/python/cp${python_major}${python_minor}-"cp*[0-9m]); \
    # python venv
    "${python_dir}/bin/python3" -m venv /venv; \
    # wheelhouse directory
    mkdir -p /wheelhouse;

# python build dependencies
ARG TORCH_VERSION="2.1.2+cu118"
RUN --mount=type=cache,target=/cache/pip,mode=0755 \
    if [[ "${TORCH_VERSION}" != *"+cu"* ]]; then \
      echo "TORCH_VERSION=${TORCH_VERSION} missing cuda identifier" >&2; \
      exit 1; \
    fi; \
    torch_url="https://download.pytorch.org/whl/${TORCH_VERSION#*+}"; \
    /venv/bin/pip3 install --extra-index-url ${torch_url} \
        "torch==${TORCH_VERSION}" "numpy<2" setuptools wheel;

# build tinycudann wheel
ARG NINJA_BUILD_CONCURRENCY=
ARG TCNN_CUDA_ARCHITECTURES="70,86"
ARG TINYCUDANN_VERSION="c91138bcd4c6877c8d5e60e483c0581aafc70cce"

RUN cd /tmp; \
    # clone tinycudann with submodules
    git clone https://github.com/NVlabs/tiny-cuda-nn.git; \
    cd tiny-cuda-nn; \
    git checkout ${TINYCUDANN_VERSION}; \
    git submodule update --init --recursive; \
    # activate venv
    source /venv/bin/activate; \
    # activate gcc-toolset-11
    set +u && source scl_source enable gcc-toolset-11 && set -u; \
    # Load the CUDA SDK
    source /usr/local/share/just/user_run_patch/10_load_cuda_env; \
    export CUDA_HOME="/usr/local/cuda"; \
    # Control number of ninja workers during torch extension compile
    # https://pytorch.org/docs/stable/cpp_extension.html#torch.utils.cpp_extension.BuildExtension
    if [ -n "${NINJA_BUILD_CONCURRENCY-}" ]; then export MAX_JOBS=${NINJA_BUILD_CONCURRENCY}; fi; \
    # build wheel
    pip3 wheel bindings/torch -w /wheelhouse-tmp \
        -v --no-deps --no-build-isolation; \
    # cleanup
    rm -rf /tmp/*;

# auditwheel, excluding torch & cuda libraries
RUN EXCLUDE=( \
        # torch libraries
        libc10.so \
        libc10_cuda.so \
        libtorch.so \
        libtorch_cuda.so \
        libtorch_cpu.so \
        libtorch_python.so \
        # cuda libraries
        libcuda.so.1 \
    ); \
    auditwheel repair /wheelhouse-tmp/*.whl -w /wheelhouse \
        $(printf -- '--exclude %s ' "${EXCLUDE[@]}"); \
    rm -rf /tmp/*

# copy output to /usr/local
FROM scratch

COPY --from=builder /wheelhouse /usr/local/share/just/wheels
