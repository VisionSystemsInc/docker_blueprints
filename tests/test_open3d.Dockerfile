# syntax=docker/dockerfile:1.4

ARG CUDA_VERSION="12.9.1"
ARG BASE_IMAGE="nvidia/cuda:${CUDA_VERSION}-runtime-ubi9"
ARG OPEN3D_IMAGE="vsiri/blueprint_test:open3d"

FROM ${OPEN3D_IMAGE} AS open3d

FROM ${BASE_IMAGE}

# update shell
SHELL ["/usr/bin/env", "/bin/bash", "-euxvc"]

# cache directory (redirect pip cache to `/cache/pip`)
ENV XDG_CACHE_HOME="/cache"

# Dependencies
RUN dnf install -y \
      libX11 \
      libGL \
      ; \
    rm -rf /var/cache/yum

# versioned python via miniforge
ARG PYTHON_VERSION="3.13.12"
RUN curl -fsSLo /mini.sh https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh; \
    sh /mini.sh -b -p /conda -s; \
    rm /mini.sh; \
    /conda/bin/conda create -y -p /usr/local "python==${PYTHON_VERSION}"

# python venv
RUN --mount=type=cache,target=/cache/pip,mode=0755 \
    "/usr/local/bin/python" -m venv /venv;

# open3d
COPY --from=open3d /usr/local /usr/local
RUN /venv/bin/pip3 install /usr/local/share/just/wheels/*.whl;
