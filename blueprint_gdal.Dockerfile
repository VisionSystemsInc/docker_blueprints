# GDAL blueprint
# - includes OPENJPEG, ECW J2K, libgeos, libtiff, PROJ, and libgeotiff
# - recipe is only compatible with GDAL 3.5+ using the cmake build system
# - includes GDAL python bindings and pyproj as installable python wheels
#
# This dockerfile follows procedures from the offical GDAL dockers
#   https://github.com/OSGeo/gdal/tree/master/gdal/docker
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

# base image
FROM ${BASE_IMAGE} AS base

# Set shell to bash
SHELL ["/usr/bin/env", "/bin/bash", "-euxvc"]

# staging & reporting directories, reused by each stage
ENV STAGING_DIR="/staging"
ENV REPORT_DIR="${STAGING_DIR}/usr/local/share/just/info"
RUN mkdir -p "${STAGING_DIR}" "${REPORT_DIR}";

# remove direct access to /opt/_internal/sqlite3
RUN rm -f /usr/local/lib/pkgconfig/sqlite3.pc

# working directory (for download, unpack, build, etc.)
WORKDIR /tmp


# -----------------------------------------------------------------------------
# SQLITE3
# -----------------------------------------------------------------------------
# copy & adjust manylinux-built sqlite3
#
# The sqlite3 project decided to remove the SONAME from libsqlite3.so by
# default, leaving SONAME details to packagers.
# https://github.com/sqlite/sqlite/blob/version-3.50.4/autosetup/sqlite-config.tcl#L339-L346
# Without an SONAME, dependent projects like libproj report an absolute file
# path for libsqlite3.so and are no longer portable. We thus add back the
# legacy SONAME and remove RUNPATH from the .so file via ``patchelf``.
FROM base AS sqlite3

RUN cp -r /opt/_internal/sqlite3/* "${STAGING_DIR}/usr/local"; \
    # adjust pkg-config
    PC="${STAGING_DIR}/usr/local/lib/pkgconfig/sqlite3.pc"; \
    sed -i 's|^prefix=.*|prefix=/usr/local|g' "${PC}"; \
    # adjust so file: remove RUNPATH and add legacy SONAME
    SO="${STAGING_DIR}/usr/local/lib/libsqlite3.so"; \
    patchelf --set-soname 'libsqlite3.so.0' --remove-rpath "${SO}";


# -----------------------------------------------------------------------------
# OPENJPEG v2
# -----------------------------------------------------------------------------
FROM base AS openjpeg

# version argument
ARG OPENJPEG_VERSION=2.5.2

# install
RUN \
    # download & unzip
    TAR_FILE="v${OPENJPEG_VERSION}.tar.gz"; \
    curl -fsSLO "https://github.com/uclouvain/openjpeg/archive/${TAR_FILE}"; \
    tar -xvf "${TAR_FILE}" --strip-components=1; \
    #
    # configure, build, & install
    cmake . \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_STATIC_LIBS=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        | tee "${REPORT_DIR}/openjpeg_configure"; \
    make -j"$(nproc)"; \
    make install DESTDIR="${STAGING_DIR}"; \
    echo "${OPENJPEG_VERSION}" > "${REPORT_DIR}/openjpeg_version"; \
    #
    # cleanup
    rm -rf /tmp/*;


# -----------------------------------------------------------------------------
# ECW v5
# -----------------------------------------------------------------------------
# ECW_VERSION.....version to install, for example, "5.5.0-Update6"
# ECW_RESOURCE....zip file in blueprint "resources" directory,
#                 for example, "ECWJP2SDKSetup_5.5.0.2421-Update6-Linux.zip"
#
# By default (empty ECW_VERSION) this plugin will not be installed.
FROM base AS ecw

# arguments (do not install by default)
ARG ECW_VERSION=
ARG ECW_RESOURCE=

# install
RUN --mount=type=bind,source=resources,target=/resources,readonly \
    #
    # check version
    if [ -z "${ECW_VERSION:-}" ]; then \
      echo "ECW decoder will not be installed" >&2; \
      exit 0; \
    fi; \
    echo "${ECW_VERSION}" > "${REPORT_DIR}/ecw_version"; \
    #
    # unzip & unpack
    unzip "/resources/${ECW_RESOURCE}"; \
    bash *.bin --accept-eula=YES --install-type=1; \
    UNPACK_DIR="$(include_dir=$(find "/root/hexagon" -name include -type d); \
                  dirname "$include_dir"})"; \
    #
    # copy necessary files
    ECW_STAGING_DIR="${STAGING_DIR}/usr/local/ecw"; \
    mkdir -p "${ECW_STAGING_DIR}"; \
    cp -r "${UNPACK_DIR}"/{*.txt,include} "${ECW_STAGING_DIR}"; \
    cp -r "${UNPACK_DIR}/redistributable/cpp11abi/x64" "${ECW_STAGING_DIR}/lib"; \
    #
    # link .so files to "/usr/local/lib" for runtime discovery
    LIB_DIR="${STAGING_DIR}/usr/local/lib"; \
    mkdir -p "${LIB_DIR}"; cd "${LIB_DIR}"; \
    ln -s ../ecw/lib/libNCSEcw.so* .; \
    #
    # cleanup
    rm -rf "${UNPACK_DIR}" /tmp/*;


# -----------------------------------------------------------------------------
# GEOS
# -----------------------------------------------------------------------------
# https://libgeos.org
FROM base AS geos

# version argument
ARG GEOS_VERSION=3.13.0

# install
RUN \
    # download & unzip
    TAR_FILE="geos-${GEOS_VERSION}.tar.bz2"; \
    curl -fsSLO "https://download.osgeo.org/geos/${TAR_FILE}"; \
    tar -xf "${TAR_FILE}" --strip-components=1; \
    #
    # configure, build, & install
    mkdir build; cd build; \
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_DOCUMENTATION=OFF \
        -DBUILD_TESTING=OFF \
        | tee "${REPORT_DIR}/geos_configure"; \
    cmake --build . -j$(nproc); \
    make install DESTDIR="${STAGING_DIR}"; \
    echo "${GEOS_VERSION}" > "${REPORT_DIR}/geos_version"; \
    #
    # cleanup
    rm -rf /tmp/*;


# -----------------------------------------------------------------------------
# LIBTIFF
# -----------------------------------------------------------------------------
# https://gitlab.com/libtiff/libtiff
FROM base AS tiff

# version argument
ARG TIFF_VERSION=4.7.0

# additional build dependencies
RUN ulimit -n 1024; \
    yum install -y \
      libjpeg-turbo-devel \
      zlib-devel; \
    yum clean all

# install
RUN \
    # download & unzip
    TAR_FILE="tiff-${TIFF_VERSION}.tar.gz"; \
    curl -fsSLO "https://download.osgeo.org/libtiff/${TAR_FILE}"; \
    tar -xf "${TAR_FILE}" --strip-components=1; \
    #
    # configure, build, & install
    ./configure \
        --disable-static \
        | tee "${REPORT_DIR}/tiff_configure"; \
    make -j"$(nproc)"; \
    make install DESTDIR="${STAGING_DIR}"; \
    echo "$TIFF_VERSION" > "${REPORT_DIR}/tiff_version"; \
    #
    # cleanup
    rm -rf /tmp/*;


# -----------------------------------------------------------------------------
# PROJ v6
# -----------------------------------------------------------------------------
# install instructions: https://proj.org/install.html
FROM base AS proj

# version argument
ARG PROJ_VERSION=9.4.1

# additional build dependencies
RUN ulimit -n 1024; \
    yum install -y \
      libcurl-devel \
      libjpeg-turbo-devel \
      zlib-devel; \
    yum clean all

# local dependencies to staging directory
COPY --from=sqlite3 ${STAGING_DIR} ${STAGING_DIR}
COPY --from=tiff ${STAGING_DIR} ${STAGING_DIR}

# install
RUN \
    # download & unzip
    TAR_FILE="proj-${PROJ_VERSION}.tar.gz"; \
    curl -fsSLO "https://download.osgeo.org/proj/${TAR_FILE}"; \
    tar -xf ${TAR_FILE} --strip-components=1; \
    #
    # configure, build, & install
    mkdir build; cd build; \
    cmake .. \
        -DCMAKE_PREFIX_PATH="${STAGING_DIR}/usr/local" \
        -DCMAKE_INSTALL_LIBDIR="lib" \
        -DBUILD_SHARED_LIBS=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_IPO=ON \
        -DBUILD_TESTING:BOOL=OFF \
        | tee "${REPORT_DIR}/proj_configure"; \
    cmake --build . -j$(nproc); \
    make install DESTDIR="${STAGING_DIR}"; \
    echo "${PROJ_VERSION}" > "${REPORT_DIR}/proj_version"; \
    #
    # cleanup
    rm -rf /tmp/*;


# -----------------------------------------------------------------------------
# GEOTIFF
# -----------------------------------------------------------------------------
# https://github.com/OSGeo/libgeotiff
FROM base AS geotiff

# version argument
ARG GEOTIFF_VERSION=1.7.3

# additional build dependencies
RUN ulimit -n 1024; \
    yum install -y \
      libcurl-devel \
      libjpeg-turbo-devel \
      zlib-devel; \
    yum clean all

# local dependencies to staging directory
COPY --from=tiff ${STAGING_DIR}/usr/local /usr/local
COPY --from=proj ${STAGING_DIR}/usr/local /usr/local

# install
RUN \
    # download & unzip
    TAR_FILE="libgeotiff-${GEOTIFF_VERSION}.tar.gz"; \
    curl -fsSLO "https://download.osgeo.org/geotiff/libgeotiff/${TAR_FILE}"; \
    tar -xf "${TAR_FILE}" --strip-components=1; \
    #
    # configure, build, & install
    ./configure \
        --with-jpeg \
        --with-proj=/usr/local \
        --with-zlib \
        | tee "${REPORT_DIR}/geotiff_configure"; \
    make -j"$(nproc)"; \
    make install DESTDIR="${STAGING_DIR}"; \
    echo "$GEOTIFF_VERSION" > "${REPORT_DIR}/geotiff_version"; \
    #
    # cleanup
    rm -rf /tmp/*;


# -----------------------------------------------------------------------------
# GDAL setup for build
# -----------------------------------------------------------------------------
FROM base AS setup

# version argument
# note cmake build system used here was introduced in 3.5.0
# https://github.com/OSGeo/gdal/releases/tag/v3.5.0
ARG GDAL_VERSION=3.9.3
ENV GDAL_VERSION=$GDAL_VERSION

# additional build dependencies
RUN ulimit -n 1024; \
    yum install -y \
      libcurl-devel \
      libjpeg-turbo-devel \
      zlib-devel; \
    yum clean all

# download & unzip
RUN TAR_FILE="gdal-${GDAL_VERSION}.tar.gz"; \
    curl -fsSLO "https://download.osgeo.org/gdal/${GDAL_VERSION}/${TAR_FILE}"; \
    tar -xf "${TAR_FILE}" --strip-components=1; \
    rm "${TAR_FILE}"


# -----------------------------------------------------------------------------
# GDAL build library
# -----------------------------------------------------------------------------
FROM setup AS library

# local dependencies to staging directory
# base manylinux image has many other dependencies already in /usr/local,
# so we isolate packages in the staging directory
COPY --from=sqlite3 ${STAGING_DIR} ${STAGING_DIR}
COPY --from=openjpeg ${STAGING_DIR} ${STAGING_DIR}
COPY --from=ecw ${STAGING_DIR} ${STAGING_DIR}
COPY --from=geos ${STAGING_DIR} ${STAGING_DIR}
COPY --from=tiff ${STAGING_DIR} ${STAGING_DIR}
COPY --from=proj ${STAGING_DIR} ${STAGING_DIR}
COPY --from=geotiff ${STAGING_DIR} ${STAGING_DIR}

# configure, build, & install
# https://raw.githubusercontent.com/OSGeo/gdal/master/gdal/configure
RUN mkdir build; cd build; \
    cmake .. \
        -D CMAKE_PREFIX_PATH="${STAGING_DIR}/usr/local;${STAGING_DIR}/usr/local/ecw" \
        -D CMAKE_BUILD_TYPE=Release \
        -D BUILD_PYTHON_BINDINGS=OFF \
        -D GDAL_USE_PCRE=OFF \
        -D GDAL_ENABLE_DRIVER_ECW_PLUGIN=ON \
        | tee "${REPORT_DIR}/gdal_configure"; \
    cmake --build . -j$(nproc); \
    make install DESTDIR="${STAGING_DIR}"; \
    echo "${GDAL_VERSION}" > "${REPORT_DIR}/gdal_version"; \
    #
    # cleanup
    rm -rf /tmp/*;


# -----------------------------------------------------------------------------
# GDAL build wheel
# -----------------------------------------------------------------------------
FROM setup AS wheel

# version argument
ARG PYTHON_VERSION=3.10.18
ARG NUMPY_VERSION=2.1.3
ARG PYPROJ_VERSION=3.7.0

# wheel directory
ENV WHEEL_DIR="${STAGING_DIR}/usr/local/share/just/wheels"

# local dependencies to /usr/local
COPY --from=library ${STAGING_DIR}/usr/local /usr/local

# build wheels
RUN mkdir -p "${WHEEL_DIR}"; \
    ldconfig; \
    #
    # python flavor
    python_major=${PYTHON_VERSION%%.*}; \
    python_minor=${PYTHON_VERSION#*.}; \
    python_minor=${python_minor%%.*}; \
    python_dir=("/opt/python/cp${python_major}${python_minor}-"cp*[0-9m]); \
    #
    # install python dependencies
    "${python_dir}/bin/pip" install \
        "cython<3" \
        numpy==${NUMPY_VERSION} \
        setuptools \
        ; \
    #
    # build gdal wheel
    "${python_dir}/bin/pip" wheel gdal==${GDAL_VERSION} --no-binary gdal \
        --no-deps --no-build-isolation -w "${WHEEL_DIR}"; \
    #
    # build pyproj wheel
    # While this project already provides manylinux wheels on pypi, building
    # pyproj here ensures the wheel uses the installed libproj & PROJ_VERSION
    "${python_dir}/bin/pip" wheel pyproj==${PYPROJ_VERSION} --no-binary pyproj \
        --no-deps --no-build-isolation -w "${WHEEL_DIR}"; \
    #
    # cleanup
    rm -rf /tmp/*; \
    ls -la "${WHEEL_DIR}";


# -----------------------------------------------------------------------------
# GDAL final
# -----------------------------------------------------------------------------
FROM base

# clear /usr/local of all other packages
RUN rm -rf /usr/local/*

# migrate staging directory to /usr/local
COPY --from=library ${STAGING_DIR}/usr/local /usr/local
COPY --from=wheel ${STAGING_DIR}/usr/local /usr/local

# Patch file for downstream image
ENV GDAL_PATCH_FILE=/usr/local/share/just/container_build_patch/30_gdal
ADD 30_gdal ${GDAL_PATCH_FILE}
RUN chmod +x ${GDAL_PATCH_FILE}
