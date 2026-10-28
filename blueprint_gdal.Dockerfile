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
ARG GDAL_VERSION="3.13.3"

# base image
FROM ${BASE_IMAGE} AS base

# Set shell to bash
SHELL ["/usr/bin/env", "/bin/bash", "-euxvc"]

# general build dependencies
RUN dnf install -y \
        libcurl-devel \
        libjpeg-turbo-devel \
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
# OPENJPEG v2
# -----------------------------------------------------------------------------
FROM base AS openjpeg

# version argument
ARG OPENJPEG_VERSION="2.5.4"

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
ARG GEOS_VERSION="3.14.1"

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
ARG TIFF_VERSION="4.7.2"

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
# PROJ
# -----------------------------------------------------------------------------
# https://proj.org/install.html
FROM base AS proj

# version argument
ARG PROJ_VERSION="9.8.1"

# local dependencies
COPY --from=tiff ${STAGING_DIR}/usr/local /usr/local

# install
RUN \
    # download & unzip
    TAR_FILE="proj-${PROJ_VERSION}.tar.gz"; \
    curl -fsSLO "https://download.osgeo.org/proj/${TAR_FILE}"; \
    tar -xf ${TAR_FILE} --strip-components=1; \
    #
    # configure, build, & install
    mkdir build; cd build; \
    export CMAKE_PREFIX_PATH="/opt/_internal/sqlite3"; \
    cmake .. \
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
ARG GEOTIFF_VERSION="1.7.4"

# local dependencies
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
# CONSOLIDATED DEPENDENCIES
# -----------------------------------------------------------------------------
FROM base AS deps

COPY --from=openjpeg ${STAGING_DIR} ${STAGING_DIR}
COPY --from=ecw ${STAGING_DIR} ${STAGING_DIR}
COPY --from=geos ${STAGING_DIR} ${STAGING_DIR}
COPY --from=tiff ${STAGING_DIR} ${STAGING_DIR}
COPY --from=proj ${STAGING_DIR} ${STAGING_DIR}
COPY --from=geotiff ${STAGING_DIR} ${STAGING_DIR}


# -----------------------------------------------------------------------------
# GDAL
# -----------------------------------------------------------------------------
FROM base AS gdal

# package versions
ARG GDAL_VERSION

# local dependencies
COPY --from=deps ${STAGING_DIR}/usr/local /usr/local

# download & unzip
RUN TAR_FILE="gdal-${GDAL_VERSION}.tar.gz"; \
    curl -fsSLO "https://download.osgeo.org/gdal/${GDAL_VERSION}/${TAR_FILE}"; \
    tar -xf "${TAR_FILE}" --strip-components=1; \
    rm "${TAR_FILE}"

# configure, build, & install
# https://raw.githubusercontent.com/OSGeo/gdal/master/gdal/configure
RUN mkdir build; cd build; \
    export CMAKE_PREFIX_PATH="/usr/local;/usr/local/ecw"; \
    cmake .. \
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
# BASE WHEELHOUSE
# -----------------------------------------------------------------------------
from base as wheel

# rsync for wheel updates
RUN dnf install -y rsync; \
    rm -rf /var/cache/dnf/*

# update auditwheel & patchelf
# (installed patchelf would corrupt gdalinfo)
RUN pipx upgrade auditwheel patchelf

# python selection & venv
ARG PYTHON_VERSION="3.13.15"
RUN python_major=${PYTHON_VERSION%%.*}; \
    python_minor=${PYTHON_VERSION#*.}; \
    python_minor=${python_minor%%.*}; \
    python_dir=("/opt/python/cp${python_major}${python_minor}-"cp*[0-9m]); \
    #
    # python venv with build dependencies
    "${python_dir}/bin/python3" -m venv /venv; \
    source /venv/bin/activate; \
    pip install pybind11[global] setuptools wheel;

# function to rsync source directory to wheel
# this lets us add command line utilities, proj-data, etc.
COPY <<'EOF' "/opt/wheelrsync.bsh"
#!/usr/bin/env bash
function wheelrsync()
{
    # variables
    local wheel_exe="/venv/bin/wheel"
    local source_dir="${1}"
    local wheel_file="${2}"
    local temp_dir="$(mktemp -d)"

    # unpack & append via rsync
    "${wheel_exe}" unpack "${wheel_file}" -d "${temp_dir}"
    mv "${temp_dir}"/* "${temp_dir}/unpacked"

    # append via rsync
    rsync -av --ignore-existing "${source_dir}/" "${temp_dir}/unpacked/"

    # repack & replace source
    "${wheel_exe}" pack "${temp_dir}/unpacked" -d "${temp_dir}"
    mv "${temp_dir}"/*.whl "${wheel_file}"

    # cleanup
    rm -rf "${temp_dir}"
}
EOF


# -----------------------------------------------------------------------------
# GDAL python wheel
# -----------------------------------------------------------------------------
FROM wheel AS gdal-wheel

# version argument
ARG GDAL_VERSION
ARG NUMPY_VERSION="2.3.5"

# local dependencies
COPY --from=deps ${STAGING_DIR}/usr/local /usr/local
COPY --from=gdal ${STAGING_DIR}/usr/local /usr/local

# python dependencies
RUN source /venv/bin/activate; \
    pip install "numpy==${NUMPY_VERSION}"

# pip wheel
RUN source /venv/bin/activate; \
    pip wheel "gdal==${GDAL_VERSION}" -w /wheelhouse-tmp \
        --no-binary :all: --no-deps --no-build-isolation;

# add to wheel: command line tools, plugins, GDAL_DATA
COPY --from=geotiff ${STAGING_DIR}/usr/local/bin /tmp/deps/gdal-${GDAL_VERSION}.data/scripts
COPY --from=gdal ${STAGING_DIR}/usr/local/bin /tmp/deps/gdal-${GDAL_VERSION}.data/scripts
COPY --from=gdal ${STAGING_DIR}/usr/local/lib64/gdalplugins /tmp/deps/osgeo/gdal_dir/gdalplugins
COPY --from=gdal ${STAGING_DIR}/usr/local/share/gdal /tmp/deps/osgeo/gdal_dir/gdaldata
RUN source /opt/wheelrsync.bsh; \
    wheelrsync /tmp/deps /wheelhouse-tmp/*.whl

# auditwheel
RUN mkdir -p /wheelhouse; \
    export LD_LIBRARY_PATH="/usr/local/lib64"; \
    auditwheel repair /wheelhouse-tmp/*.whl -w /wheelhouse --exclude libcurl.so.4;


# -----------------------------------------------------------------------------
# PYPROJ python wheel
# -----------------------------------------------------------------------------
# While pyproj project already provides manylinux wheels on pypi, building
# here ensures the wheel uses the same library versions
FROM wheel AS pyproj-wheel

# version argument
ARG PYPROJ_VERSION="3.7.2"

# local dependencies
COPY --from=deps ${STAGING_DIR}/usr/local /usr/local
RUN ldconfig

# python dependencies
RUN \
    # pyproj<3.6.1 is incompatible with cython 3+
    # https://github.com/pyproj4/pyproj/issues/1321
    function version_le() { test "$(echo -e "$1\n$2" | sort -V | head -n 1)" == "$1"; }; \
    if version_le "3.6.1" "${PYPROJ_VERSION}"; then \
        CYTHON_DEP="cython"; \
    else \
        CYTHON_DEP="cython<3"; \
    fi; \
    #
    # install python dependencies
    source /venv/bin/activate; \
    pip install "${CYTHON_DEP}";

# pip wheel
RUN source /venv/bin/activate; \
    pip wheel "pyproj==${PYPROJ_VERSION}" -w /wheelhouse-tmp \
        --no-binary :all: --no-deps --no-build-isolation;

# add to wheel: command line tools, PROJ_DATA
COPY --from=proj ${STAGING_DIR}/usr/local/bin /tmp/deps/pyproj-${PYPROJ_VERSION}.data/scripts
COPY --from=proj ${STAGING_DIR}/usr/local/share/proj /tmp/deps/pyproj/proj_dir/share/proj
RUN source /opt/wheelrsync.bsh; \
    wheelrsync /tmp/deps /wheelhouse-tmp/*.whl

# auditwheel
RUN mkdir -p /wheelhouse; \
    auditwheel repair /wheelhouse-tmp/*.whl -w /wheelhouse --exclude libcurl.so.4;


# -----------------------------------------------------------------------------
# GDAL final
# -----------------------------------------------------------------------------
FROM scratch

# wheels
COPY --from=gdal-wheel /wheelhouse /usr/local/share/just/wheels
COPY --from=pyproj-wheel /wheelhouse /usr/local/share/just/wheels

# configure/version reports
COPY --from=deps /staging/usr/local/share/just/info /usr/local/share/just/info
COPY --from=gdal /staging/usr/local/share/just/info /usr/local/share/just/info

# PROJ_DATA and GDAL_DATA
COPY --from=proj /staging/usr/local/share/proj /opt/proj_data
COPY --from=gdal /staging/usr/local/share/gdal /opt/gdal_data

# staged dependencies for downstream docker build like PDAL
COPY --from=deps /staging /staging
COPY --from=gdal /staging /staging
