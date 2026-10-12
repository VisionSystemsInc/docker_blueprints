# syntax=docker/dockerfile:1.4

ARG BASE_IMAGE="quay.io/pypa/manylinux_2_28_x86_64:2025.09.28-1"
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
        git \
        ; \
    rm -rf /var/cache/yum/*

# python & wheelhouse setup
ARG PYTHON_VERSION="3.13.12"
RUN python_major=${PYTHON_VERSION%%.*}; \
    python_minor=${PYTHON_VERSION#*.}; \
    python_minor=${python_minor%%.*}; \
    python_dir=("/opt/python/cp${python_major}${python_minor}-"cp*[0-9m]); \
    # python venv
    "${python_dir}/bin/python3" -m venv /venv; \
    # wheelhouse directories
    mkdir -p /wheelhouse-tmp /wheelhouse;

# python build dependencies
ARG TORCH_VERSION="2.9.1+cu129"
RUN --mount=type=cache,target=/cache/pip,mode=0755 \
    if [[ "${TORCH_VERSION}" != *"+cu"* ]]; then \
        echo "TORCH_VERSION=${TORCH_VERSION} missing cuda identifier" >&2; \
        exit 1; \
    fi; \
    torch_url="https://download.pytorch.org/whl/${TORCH_VERSION#*+}"; \
    /venv/bin/pip3 install --extra-index-url ${torch_url} \
        "torch==${TORCH_VERSION}" setuptools;

# clone SAM-2
ARG SAM2_VERSION="2b90b9f5ceec907a1c18123530e92e794ad901a4"
ENV SAM2_DIR="/sam2" \
    SAM2_URL="https://github.com/facebookresearch/sam2"
RUN mkdir -p "${SAM2_DIR}"; \
    git clone "${SAM2_URL}" "${SAM2_DIR}"; \
    git -C "${SAM2_DIR}" checkout "${SAM2_VERSION}";

# build wheel and save to wheelhouse-tmp
ARG TORCH_CUDA_ARCH_LIST="7.0 8.6"
RUN \
    # activate venv
    source /venv/bin/activate; \
    # Load the CUDA SDK
    source /usr/local/share/just/user_run_patch/10_load_cuda_env; \
    export CUDA_HOME="/usr/local/cuda"; \
    # build wheel
    export SAM2_BUILD_CUDA=1; \
    export SAM2_BUILD_ALLOW_ERRORS=0; \
    pip wheel --no-deps --no-build-isolation -w /wheelhouse-tmp -v "${SAM2_DIR}";

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
        libcudart.so.12 \
    ); \
    auditwheel repair /wheelhouse-tmp/*.whl -w /wheelhouse \
        $(printf -- '--exclude %s ' "${EXCLUDE[@]}"); \
    rm -rf /tmp/*;

# copy output to /usr/local
FROM scratch

COPY --from=builder /wheelhouse /usr/local/share/just/wheels
