ARG BASE_IMAGE="quay.io/pypa/manylinux_2_28_x86_64:2025.09.28-1"
FROM "${BASE_IMAGE}" AS builder

SHELL ["/usr/bin/env", "/bin/bash", "-euxvc"]

# dependencies
RUN dnf install -y \
        gmp-devel \
        mesa-libGLU-devel \
        mpfr-devel \
        qt5-qtbase-devel \
        xerces-c-devel \
        ; \
    rm -rf /var/cache/dnf/*

# embree
# https://github.com/RenderKit/embree/#linux-installation
ARG EMBREE_VERSION="4.4.1"
RUN URL="https://github.com/embree/embree/releases/download/v${EMBREE_VERSION}/embree-${EMBREE_VERSION}.x86_64.linux.tar.gz"; \
    curl -fsSL "${URL}" -o /tmp/embree.tgz; \
    mkdir -p /embree; \
    tar -xvf /tmp/embree.tgz -C /embree; \
    rm -rf /tmp/*;

# tbb
# https://github.com/uxlfoundation/oneTBB/blob/master/INSTALL.md#install-from-release-packages
ARG TBB_VERSION="2023.1.0"
RUN URL="https://github.com/uxlfoundation/oneTBB/releases/download/v${TBB_VERSION}/oneapi-tbb-${TBB_VERSION}-lin.tgz"; \
    curl -fsSL "${URL}" -o /tmp/tbb.tgz; \
    mkdir -p /tbb; \
    tar -xvf /tmp/tbb.tgz --strip-components=1 -C /tbb; \
    rm -rf /tmp/*;

# clone pymeshlab
ARG PYMESHLAB_VERSION="v2025.7.post1"
RUN git clone https://github.com/cnr-isti-vclab/pymeshlab.git /pymeshlab/source; \
    cd /pymeshlab/source; \
    git checkout "${PYMESHLAB_VERSION}"; \
    git submodule update --init --recursive;

# run cmake to download 3rd party dependencies
# downloaded source code stored in /pymeshlab/source/src/meshlab/src/external/downloads
RUN \
    # update lib3mf to v2.5.0 (version 2.4.1 fails to compile)
    LIB3MF_CMAKE="/pymeshlab/source/src/meshlab/src/external/lib3mf.cmake"; \
    sed -i 's|\(set(LIB3MF_VERSION \).*|\1"2.5.0")|' "${LIB3MF_CMAKE}"; \
    sed -i 's|\(set(LIB3MF_MD5 \).*|\1a2b876d095555b5c3e473e63dbe06634)|' "${LIB3MF_CMAKE}"; \
    #
    # download 3rd party dependencies using a dummy build directory
    mkdir -p /tmp/dummy; \
    cmake -S /pymeshlab/source -B /tmp/dummy; \
    rm -rf /tmp/*;

# additional source code modifications
RUN \
    # CMakeLists.txt: limit python components, use system pybind11
    sed -i "s|add_subdirectory(pybind11)|find_package(Python REQUIRED COMPONENTS Interpreter Development.Module)\nfind_package(pybind11 REQUIRED)|g" \
        "/pymeshlab/source/src/pymeshlab/CMakeLists.txt";

# python selection & venv
ARG PYTHON_VERSION="3.13.12"
RUN python_major=${PYTHON_VERSION%%.*}; \
    python_minor=${PYTHON_VERSION#*.}; \
    python_minor=${python_minor%%.*}; \
    python_dir=("/opt/python/cp${python_major}${python_minor}-"cp*[0-9m]); \
    #
    # python venv with build dependencies
    "${python_dir}/bin/python3" -m venv /venv; \
    source /venv/bin/activate; \
    pip install "cmake<4" ninja pybind11[global] setuptools wheel;

# build pymeshlab
RUN mkdir -p /pymeshlab/build /pymeshlab/install; \
    cd /pymeshlab/build; \
    source /venv/bin/activate; \
    #
    # configure
    cmake \
        -S /pymeshlab/source \
        -B /pymeshlab/build \
        -G Ninja \
        -D CMAKE_BUILD_TYPE=Release \
        -D CMAKE_INSTALL_PREFIX=/pymeshlab/install \
        -D embree_DIR="/embree/lib64/cmake/embree-${EMBREE_VERSION}" \
        -D TBB_DIR="/tbb/lib/cmake/tbb" \
        ; \
    #
    # build && install
    ninja; \
    ninja install;

# build wheel
RUN mkdir -p /tmp/install /wheelhouse-tmp; \
    cd /tmp/install; \
    source /venv/bin/activate; \
    #
    # consolidate files
    cp -ar /pymeshlab/source/{setup.py,PYML_VERSION,LICENSE,README.md,pymeshlab} ./; \
    cp -ar /pymeshlab/install/pmeshlab* ./pymeshlab/; \
    mkdir -p ./pymeshlab/lib; cp -ar /pymeshlab/install/lib/plugins ./pymeshlab/lib/; \
    #
    # modify setup.py
    # - default tagging
    # - additional package data, set has_ext_modules=True
    sed -i 's|a, b, c = super().get_tag()|return super().get_tag()|g' "setup.py"; \
    sed -i '/packages=/ s/$/ package_data={"pymeshlab": ["setup.cfg", "keys.txt", "pmeshlab*.so", "lib\/plugins\/*"], "pymeshlab.tests": ["sample_meshes\/**\/*"]}, has_ext_modules=lambda: True,/' \
        "setup.py"; \
    #
    # build wheel
    pip wheel ./ -w /wheelhouse-tmp -v --no-deps --no-build-isolation;

# auditwheel
RUN mkdir -p /wheelhouse; \
    export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}:}/pymeshlab/install/lib"; \
    auditwheel repair /wheelhouse-tmp/*.whl -w /wheelhouse;

# copy output to /usr/local
FROM scratch

COPY --from=builder /wheelhouse /usr/local/share/just/wheels
