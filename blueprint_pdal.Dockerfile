# PDAL blueprint
# - includes manually built dependencies LASZIP, LAZPERF, Nitro
# - use must include the GDAL recipe in their dockerfile
# - includes pdal-python as installable python wheel
#
# This dockerfile follows procedures from the offical PDAL dockers
#   https://github.com/PDAL/PDAL/blob/2.3.0/scripts/docker/centos/Dockerfile
#
# This dockerfile is derived from the manylinux2014 base image, derived from
# CentOS 7 and already containing many updated build essentials.
#   https://github.com/pypa/manylinux
#
# As this base image includes build essentials already in /usr/local,
# libraries are staged in "/staging/usr/local".  The last build step clears
# /usr/local of other packages, then migrates the staging directory to
# /usr/local for consistency with other recipes.

# -----------------------------------------------------------------------------
# BASE IMAGE
# -----------------------------------------------------------------------------

# global args
ARG BASE_IMAGE="quay.io/pypa/manylinux_2_28_x86_64:2025.09.28-1"
ARG GDAL_IMAGE="vsiri/blueprint:gdal"

# blueprint dependencies
FROM ${GDAL_IMAGE} AS gdal

# base image
FROM ${BASE_IMAGE} AS base

# Set shell to bash
SHELL ["/usr/bin/env", "/bin/bash", "-euxvc"]

# general build dependencies
RUN dnf install -y \
        libcurl-devel \
        libjpeg-turbo-devel \
        libxml2-devel \
        zlib-devel \
        ; \
    rm -rf /var/cache/dnf/*

# staging & reporting directories, reused by each stage
ENV STAGING_DIR="/staging"
ENV REPORT_DIR="${STAGING_DIR}/usr/local/share/just/info"
RUN mkdir -p "${STAGING_DIR}" "${REPORT_DIR}";

# working directory (for download, unpack, build, etc.)
WORKDIR /tmp


# -----------------------------------------------------------------------------
# LASZIP
# -----------------------------------------------------------------------------
FROM base AS laszip

# version argument
ARG LASZIP_VERSION="3.5.0"

# install
RUN \
    # download & unzip
    TAR_FILE="${LASZIP_VERSION}.tar.gz"; \
    curl -fsSLO "https://github.com/LASzip/LASzip/archive/refs/tags/${TAR_FILE}"; \
    tar -xvf "${TAR_FILE}" --strip-components=1; \
    #
    # configure, build, & install
    cmake . \
        -D CMAKE_BUILD_TYPE=Release; \
    make -j"$(nproc)"; \
    make install DESTDIR="${STAGING_DIR}"; \
    echo "${LASZIP_VERSION}" > "${REPORT_DIR}/laszip_version"; \
    #
    # cleanup
    rm -rf /tmp/*;


# -----------------------------------------------------------------------------
# LAZ-PERF
# -----------------------------------------------------------------------------
FROM base AS lazperf

# version argument
ARG LAZPERF_VERSION="3.4.0"

# install
RUN \
    # download & unzip
    TAR_FILE="${LAZPERF_VERSION}.tar.gz"; \
    curl -fsSLO "https://github.com/hobu/laz-perf/archive/refs/tags/${TAR_FILE}"; \
    tar -xvf "${TAR_FILE}" --strip-components=1; \
    #
    # configure, build, & install
    cmake . \
        -D CMAKE_BUILD_TYPE=Release \
        -D WITH_TESTS=OFF; \
    make -j"$(nproc)"; \
    make install DESTDIR="${STAGING_DIR}"; \
    echo "${LAZPERF_VERSION}" > "${REPORT_DIR}/lazperf_version"; \
    #
    # cleanup
    rm -rf /tmp/*;


# -----------------------------------------------------------------------------
# NITRO NITF
# -----------------------------------------------------------------------------
FROM base AS nitro

# version argument
ARG NITRO_VERSION=2.7dev-8

# install
RUN \
    # download & unzip
    TAR_FILE="${NITRO_VERSION}.tar.gz"; \
    curl -fsSLO "https://github.com/hobu/nitro/archive/refs/tags/${TAR_FILE}"; \
    tar -xvf "${TAR_FILE}" --strip-components=1; \
    #
    # configure, build, & install
    cmake . \
        -D CMAKE_BUILD_TYPE=Release \
        # Compatibility with CMake < 3.5 has been removed from CMake
        -D CMAKE_POLICY_VERSION_MINIMUM=3.5 \
        ; \
    make -j"$(nproc)"; \
    make install DESTDIR="${STAGING_DIR}"; \
    echo "${NITRO_VERSION}" > "${REPORT_DIR}/nitro_version"; \
    #
    # cleanup
    rm -rf /tmp/*;


# -----------------------------------------------------------------------------
# CONSOLIDATED DEPENDENCIES
# -----------------------------------------------------------------------------
FROM base AS deps

COPY --from=laszip ${STAGING_DIR} ${STAGING_DIR}
COPY --from=lazperf ${STAGING_DIR} ${STAGING_DIR}
COPY --from=nitro ${STAGING_DIR} ${STAGING_DIR}


# -----------------------------------------------------------------------------
# PDAL
# -----------------------------------------------------------------------------
FROM base AS pdal

# version argument
ARG PDAL_VERSION="2.10.1"
ENV PDAL_VERSION=${PDAL_VERSION}

# local dependencies
COPY --from=deps ${STAGING_DIR}/usr/local /usr/local
COPY --from=gdal ${STAGING_DIR}/usr/local /usr/local

# install
RUN \
    # download & unzip
    TAR_FILE="PDAL-${PDAL_VERSION}-src.tar.gz"; \
    curl -fsSLO "https://github.com/PDAL/PDAL/releases/download/${PDAL_VERSION}/${TAR_FILE}"; \
    tar -xf "${TAR_FILE}" --strip-components=1; \
    #
    # configure, build, & install
    cmake . \
        -D CMAKE_PREFIX_PATH="/usr/local" \
        -D CMAKE_BUILD_TYPE=Release \
        -D WITH_LASZIP=ON \
        -D WITH_LAZPERF=ON \
        -D BUILD_PLUGIN_NITF=ON \
        -D WITH_ZLIB=ON \
        -D WITH_TESTS=OFF \
        | tee "${REPORT_DIR}/pdal_configure"; \
    make -j "$(nproc)"; \
    make install "DESTDIR=${STAGING_DIR}"; \
    echo "${PDAL_VERSION}" > "${REPORT_DIR}/pdal_version"; \
    #
    # cleanup
    rm -rf /tmp/*;


# -----------------------------------------------------------------------------
# PDAL python wheel
# -----------------------------------------------------------------------------
FROM base AS wheel

# version arguments
# note pdal-python is hosted/versioned separately from PDAL
ARG NUMPY_VERSION="2.3.5"
ARG PDAL_PYTHON_VERSION="3.5.5"
ARG PYTHON_VERSION="3.13.15"

# python selection & venv
RUN python_major=${PYTHON_VERSION%%.*}; \
    python_minor=${PYTHON_VERSION#*.}; \
    python_minor=${python_minor%%.*}; \
    python_dir=("/opt/python/cp${python_major}${python_minor}-"cp*[0-9m]); \
    #
    # python venv with build dependencies
    "${python_dir}/bin/python3" -m venv /venv; \
    source /venv/bin/activate; \
    pip install \
        ninja \
        numpy==${NUMPY_VERSION} \
        pybind11[global] \
        scikit-build-core \
        ;

# local dependencies to /usr/local
COPY --from=deps ${STAGING_DIR}/usr/local /usr/local
COPY --from=gdal ${STAGING_DIR}/usr/local /usr/local
COPY --from=pdal ${STAGING_DIR}/usr/local /usr/local

# download pdal-python
RUN mkdir -p /pdal-python; \
    TAR_FILE="${PDAL_PYTHON_VERSION}.tar.gz"; \
    curl -fsSLO "https://github.com/PDAL/python/archive/refs/tags/${TAR_FILE}"; \
    tar -xf "${TAR_FILE}" --strip-components=1 -C /pdal-python; \
    #
    # workaround - wheel succeeds for Development.Module
    # https://gitlab.kitware.com/cmake/cmake/-/issues/20425
    # https://github.com/google/or-tools/issues/2774
    sed -i '/^[ ]*find_package/s/Development /Development.Module /g' /pdal-python/CMakeLists.txt;

# include command line tools in wheel
COPY --from=pdal ${STAGING_DIR}/usr/local/bin /pdal-python/bin
RUN PYPROJECT_TOML="/pdal-python/pyproject.toml"; \
    echo '[tool.scikit-build.wheel.force-include]' >> "${PYPROJECT_TOML}"; \
    echo '"bin" = "${SKBUILD_SCRIPTS_DIR}"' >> "${PYPROJECT_TOML}";

# pip wheel
RUN source /venv/bin/activate; \
    pip wheel /pdal-python -w /wheelhouse-tmp \
        --no-binary :all: --no-deps --no-build-isolation;

# auditwheel
RUN mkdir -p /wheelhouse; \
    export LD_LIBRARY_PATH="/usr/local/lib64"; \
    auditwheel repair /wheelhouse-tmp/*.whl -w /wheelhouse --exclude libcurl.so.4;


# -----------------------------------------------------------------------------
# PDAL final
# -----------------------------------------------------------------------------
FROM scratch

# wheels
COPY --from=wheel /wheelhouse /usr/local/share/just/wheels

# configure/version reports
COPY --from=deps /staging/usr/local/share/just/info /usr/local/share/just/info
COPY --from=pdal /staging/usr/local/share/just/info /usr/local/share/just/info

# PROJ_DATA and GDAL_DATA
COPY --from=gdal /staging/usr/local/share/proj /opt/proj_data
COPY --from=gdal /staging/usr/local/share/gdal /opt/gdal_data
