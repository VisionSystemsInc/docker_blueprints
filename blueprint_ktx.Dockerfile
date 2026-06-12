ARG BASE_IMAGE="quay.io/pypa/manylinux_2_28_x86_64:2025.09.28-1"
FROM "${BASE_IMAGE}" AS builder

SHELL ["/usr/bin/env", "/bin/bash", "-euxvc"]

# dependencies
RUN dnf install -y \
        ninja-build \
        ; \
    rm -rf /var/cache/dnf/*

# clone
ARG KTX_VERSION="v4.4.2"

RUN git clone https://github.com/KhronosGroup/KTX-Software.git /ktx/source; \
    git -C /ktx/source checkout "${KTX_VERSION}";

# RUN mkdir -p /ktx/source; \
#     cd tmp; \
#     URL="https://github.com/KhronosGroup/KTX-Software/archive/refs/tags/v${KTX_VERSION}.tar.gz"; \
#     curl -fsSL "${URL}" -o ktx.tgz; \
#     tar xf ktx.tgz -C /ktx/source --strip-components=1; \
#     rm /tmp/*;

# build libktx
RUN mkdir -p /ktx/build; \
    cd /ktx/build; \
    #
    # configure
    cmake \
        -S /ktx/source \
        -B /ktx/build \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DKTX_FEATURE_TOOLS=OFF \
        ; \
    #
    # build && install
    ninja; \
    ninja install;

# pyktx
ARG PYTHON_VERSION="3.13.12"
RUN \
    # setup
    export LIBKTX_VERSION="${KTX_VERSION}"; \
    export LD_LIBRARY_PATH="/usr/local/lib64"; \
    mkdir -p /wheelhouse /wheelhouse-tmp; \
    #
    # manylinux python directory
    python_major=${PYTHON_VERSION%%.*}; \
    python_minor=${PYTHON_VERSION#*.}; \
    python_minor=${python_minor%%.*}; \
    python_dir=("/opt/python/cp${python_major}${python_minor}-"cp*[0-9m]); \
    #
    # create python venv & install build dependencies
    "${python_dir}/bin/python3" -m venv /venv; \
    source /venv/bin/activate; \
    pip install -r /ktx/source/interface/python_binding/requirements.txt; \
    #
    # build pyktx wheel
    pip wheel /ktx/source/interface/python_binding -w /wheelhouse-tmp \ 
        -v --no-deps --no-build-isolation; \
    #
    # repair wheel
    auditwheel repair /wheelhouse-tmp/*.whl -w /wheelhouse;

# copy output to /usr/local
FROM scratch

COPY --from=builder /wheelhouse /usr/local/share/just/wheels
