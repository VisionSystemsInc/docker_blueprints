
ARG CUDA_VERSION=11.8.0
ARG BASE_IMAGE="nvidia/cuda:${CUDA_VERSION}-runtime-ubi8"
ARG TINYCUDANN_IMAGE=vsiri/blueprint_test:tinycudann

FROM ${TINYCUDANN_IMAGE} AS tinycudann

FROM ${BASE_IMAGE} AS builder

# update shell
SHELL ["/usr/bin/env", "/bin/bash", "-euxvc"]

# Dependencies
RUN dnf install -y \
      ca-certificates \
      curl \
      ; \
    rm -rf /var/cache/yum

# versioned python via miniforge
ARG PYTHON_VERSION=3.10.15
RUN curl -fsSLo /mini.sh https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh; \
    sh /mini.sh -b -p /conda -s; \
    rm /mini.sh; \
    /conda/bin/conda create -y -p /usr/local "python==${PYTHON_VERSION}"

# create virtual environment
RUN "/usr/local/bin/python" -m venv /venv;

# install python modules
COPY --from=tinycudann /usr/local /usr/local
RUN /venv/bin/pip3 install --no-cache-dir --extra-index-url https://download.pytorch.org/whl \
        /usr/local/share/just/wheels/*.whl 'numpy<2';
