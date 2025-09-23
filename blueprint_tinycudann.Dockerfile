ARG BASE_IMAGE=quay.io/pypa/manylinux_2_28_x86_64
ARG VSI_RECIPE_REPO='vsiri/recipe'

# docker recipes
FROM ${VSI_RECIPE_REPO}:cuda AS cuda

# main builder stage
FROM ${BASE_IMAGE} AS builder

# update shell
SHELL ["/usr/bin/env", "/bin/bash", "-euxvc"]

# install CUDA
ARG CUDA_RECIPE_TARGET=devel
COPY --from=cuda /usr/local /usr/local
RUN shopt -s nullglob; for patch in /usr/local/share/just/container_build_patch/*; do "${patch}"; done

# dependencies
RUN dnf install -y \
        ninja-build \
        gcc-toolset-11 \
        git \
        ; \
    rm -rf /var/cache/yum/*

# setup: python version, create wheelhouse
ARG PYTHON_VERSION=3.10.15
ENV PYTHON_ACTIVATE="/opt/python_activate.env"
RUN python_major=${PYTHON_VERSION%%.*}; \
    python_minor=${PYTHON_VERSION#*.}; \
    python_minor=${python_minor%%.*}; \
    python_dir=("/opt/python/cp${python_major}${python_minor}-"cp*[0-9m]); \
    # save python executable info to file
    touch "${PYTHON_ACTIVATE}"; \
    echo "PYBIN=${python_dir}/bin" >> "${PYTHON_ACTIVATE}"; \
    echo 'PYTHON=${PYBIN}/python' >> "${PYTHON_ACTIVATE}"; \
    echo 'PIP=${PYBIN}/pip' >> "${PYTHON_ACTIVATE}"; \
    # create wheelhouse
    mkdir -p /wheelhouse;

# install torch, optionally keeping wheel
ARG TORCH_KEEP_WHEEL=0
ARG TORCH_VERSION
RUN source "${PYTHON_ACTIVATE}"; \
    # download torch
    "${PIP}" download --extra-index-url https://download.pytorch.org/whl \
        "torch==${TORCH_VERSION}" --no-deps -d /wheelhouse; \
    # install torch
    "${PIP}" install --no-cache-dir /wheelhouse/torch*.whl; \
    # optionally keep/delete wheel after install
    if [ "${TORCH_KEEP_WHEEL}" != "1" ]; then \
      rm /wheelhouse/*.whl; \
    fi;

# additional python build dependencies
RUN source "${PYTHON_ACTIVATE}"; \
    "${PIP}" install --no-cache-dir setuptools;

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
    # activate python environment & gcc-toolset-11
    source "${PYTHON_ACTIVATE}"; \
    set +u && source scl_source enable gcc-toolset-11 && set -u; \
    # Load the CUDA SDK
    source /usr/local/share/just/user_run_patch/10_load_cuda_env; \
    export CUDA_HOME="/usr/local/cuda"; \
    # Control number of ninja workers during torch extension compile
    # https://pytorch.org/docs/stable/cpp_extension.html#torch.utils.cpp_extension.BuildExtension
    if [ -n "${NINJA_BUILD_CONCURRENCY-}" ]; then export MAX_JOBS=${NINJA_BUILD_CONCURRENCY}; fi; \
    # build wheel
    "${PIP}" wheel bindings/torch -w /wheelhouse/tmp \
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
    auditwheel repair /wheelhouse/tmp/*.whl -w /wheelhouse \
        $(printf -- '--exclude %s ' "${EXCLUDE[@]}") ; \
    rm -rf /tmp/* /wheelhouse/tmp;

# copy output to /usr/local
FROM scratch

COPY --from=builder /wheelhouse /usr/local/share/just/wheels
