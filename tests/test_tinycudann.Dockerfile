# syntax=docker/dockerfile:1.4

ARG CUDA_VERSION="11.8.0"
ARG TINYCUDANN_IMAGE="vsiri/blueprint_test:tinycudann"

ARG BASE_IMAGE="nvidia/cuda:${CUDA_VERSION}-runtime-ubi8"

FROM ${TINYCUDANN_IMAGE} AS tinycudann

FROM ${BASE_IMAGE} AS builder

# update shell
SHELL ["/usr/bin/env", "/bin/bash", "-euxvc"]

# cache directory (redirect pip cache to `/cache/pip`)
ENV XDG_CACHE_HOME="/cache"

# Dependencies
RUN dnf install -y \
      ca-certificates \
      curl \
      ; \
    rm -rf /var/cache/yum

# versioned python via miniforge
ARG PYTHON_VERSION="3.10.15"
RUN curl -fsSLo /mini.sh https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh; \
    sh /mini.sh -b -p /conda -s; \
    rm /mini.sh; \
    /conda/bin/conda create -y -p /usr/local "python==${PYTHON_VERSION}"

# python venv
ARG TORCH_VERSION="2.1.2+cu118"
RUN --mount=type=cache,target=/cache/pip,mode=0755 \
    "/usr/local/bin/python" -m venv /venv; \
    /venv/bin/pip3 install --extra-index-url https://download.pytorch.org/whl \
        "torch==${TORCH_VERSION}" "numpy<2";

# tiny-cuda-nn
COPY --from=tinycudann /usr/local /usr/local
RUN /venv/bin/pip3 install /usr/local/share/just/wheels/*.whl;
