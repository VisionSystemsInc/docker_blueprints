# CentOS 7 with PDAL
# - includes manually built dependencies LASZIP, LAZPERF, Nitro
# - compatible with pypi PDAL bindings (recipe does not build python bindings)
# - use must include the GDAL recipe in their dockerfile
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
ARG BASE_IMAGE="quay.io/pypa/manylinux2014_x86_64:2024-07-02-9ac04ee"
ARG GDAL_IMAGE="vsiri/blueprint:gdal"

# blueprint dependencies
FROM ${GDAL_IMAGE} AS gdal

# base image
FROM ${BASE_IMAGE} AS base

# Set shell to bash
SHELL ["/usr/bin/env", "/bin/bash", "-euxvc"]

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
ARG LASZIP_VERSION=3.4.3

# install
RUN \
    # download & unzip
    TAR_FILE="laszip-src-${LASZIP_VERSION}.tar.gz"; \
    curl -fsSLO "https://github.com/LASzip/LASzip/releases/download/${LASZIP_VERSION}/${TAR_FILE}"; \
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
ARG LAZPERF_VERSION=2.1.0

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
ARG NITRO_VERSION=2.7dev-6

# install
RUN \
    # download & unzip
    TAR_FILE="${NITRO_VERSION}.tar.gz"; \
    curl -fsSLO "https://github.com/hobu/nitro/archive/refs/tags/${TAR_FILE}"; \
    tar -xvf "${TAR_FILE}" --strip-components=1; \
    #
    # configure, build, & install
    cmake . \
        -D CMAKE_BUILD_TYPE=Release; \
    make -j"$(nproc)"; \
    make install DESTDIR="${STAGING_DIR}"; \
    echo "${NITRO_VERSION}" > "${REPORT_DIR}/nitro_version"; \
    #
    # cleanup
    rm -rf /tmp/*;


# -----------------------------------------------------------------------------
# PDAL setup for build
# -----------------------------------------------------------------------------
FROM base AS setup

# version argument
ARG PDAL_VERSION=2.3.0
ENV PDAL_VERSION=${PDAL_VERSION}

# additional build dependencies
RUN ulimit -n 1024; \
    yum install -y \
      libcurl-devel \
      libjpeg-turbo-devel \
      libxml2-devel \
      zlib-devel; \
    yum clean all


# -----------------------------------------------------------------------------
# PDAL build library
# -----------------------------------------------------------------------------
FROM setup AS library

# local dependencies to staging directory
# the base has many other dependencies already in /usr/local,
# so we isolate packages in a staging directory
COPY --from=laszip ${STAGING_DIR} ${STAGING_DIR}
COPY --from=lazperf ${STAGING_DIR} ${STAGING_DIR}
COPY --from=nitro ${STAGING_DIR} ${STAGING_DIR}

# copy GDAL to /usr/local - GDAL will be copied into downstream dockers
# independently, and should not be added to staging
COPY --from=gdal /usr/local /usr/local

# install
RUN \
    # download & unzip
    TAR_FILE="PDAL-${PDAL_VERSION}-src.tar.gz"; \
    curl -fsSLO "https://github.com/PDAL/PDAL/releases/download/${PDAL_VERSION}/${TAR_FILE}"; \
    tar -xf "${TAR_FILE}" --strip-components=1; \
    #
    # configure, build, & install
    cmake . \
        -D CMAKE_PREFIX_PATH="${STAGING_DIR}/usr/local" \
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
# PDAL build wheel
# -----------------------------------------------------------------------------
FROM setup AS wheel

# version arguments
# note pdal-python is hosted/versioned separately from PDAL
ARG PDAL_PYTHON_VERSION=3.0.2
ARG PYTHON_VERSION=3.9
ARG NUMPY_VERSION=1.22.3

# wheel directory
ENV WHEEL_DIR="${STAGING_DIR}/usr/local/share/just/wheels"

# local dependencies to /usr/local
COPY --from=gdal /usr/local /usr/local
COPY --from=library ${STAGING_DIR}/usr/local /usr/local

# build wheels
RUN mkdir -p "${WHEEL_DIR}"; \
    #
    # download pdal-python
    TAR_FILE="${PDAL_PYTHON_VERSION}.tar.gz"; \
    curl -fsSLO "https://github.com/PDAL/python/archive/refs/tags/${TAR_FILE}"; \
    tar -xf "${TAR_FILE}" --strip-components=1; \
    #
    # workaround - wheel succeeds for Development.Module
    # https://gitlab.kitware.com/cmake/cmake/-/issues/20425
    # https://github.com/google/or-tools/issues/2774
    sed -i '/^[ ]*find_package/s/Development /Development.Module /g' ./CMakeLists.txt; \
    #
    # python flavor
    PYBIN=$(ver=$(echo ${PYTHON_VERSION} | sed -E 's|(.)\.([^.]*).*|\1\2|'); \
            echo /opt/python/cp${ver}-*/bin); \
    #
    # install python dependencies
    "${PYBIN}/pip" install \
        ninja \
        numpy==${NUMPY_VERSION} \
        pybind11[global] \
        scikit-build \
        scikit-build-core \
        ; \
    #
    # build wheel
    # Note $PYBIN is added to the path to allow cmake (used during the build
    # process) to identify the correct python version
    PATH="${PYBIN}:$PATH"; \
    "${PYBIN}/pip" wheel . \
        --no-deps --no-build-isolation -w "${WHEEL_DIR}"; \
    #
    # cleanup
    rm -rf /tmp/*; \
    ls -la "${WHEEL_DIR}";


# -----------------------------------------------------------------------------
# PDAL final
# -----------------------------------------------------------------------------
FROM base

# clear /usr/local
RUN rm -rf /usr/local/*

# migrate staging directory to /usr/local
COPY --from=library ${STAGING_DIR}/usr/local /usr/local
COPY --from=wheel ${STAGING_DIR}/usr/local /usr/local

# Patch file for downstream image
ENV PDAL_PATCH_FILE=/usr/local/share/just/container_build_patch/30_pdal
ADD 30_pdal ${PDAL_PATCH_FILE}
RUN chmod +x ${PDAL_PATCH_FILE}
