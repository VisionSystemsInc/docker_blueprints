# CentOS 7 with GDAL 3+
# - includes OPENJPEG 2.4, ECW J2K 5.5, libtiff4.3, libgeotiff 1.7, PROJ v8
# - compatible with pypi GDAL bindings (recipe does not build python bindings)
# - recipe is not currently compatible with GDAL 2.
#
# This dockerfile follows procedures from the offical GDAL dockers
#   https://github.com/OSGeo/gdal/tree/master/gdal/docker
#
# This dockerfile is derived from the manylinux2014 base image, derived from
# CentOS 7 and already containing many updated build essentials.
#   https://github.com/pypa/manylinux
#
# In the future, the manylinux2014 image could enable a portable GDAL that
# includes internal copies of necessary dependencies and python bindings
# for a selected python version. This recipe currently does not build any
# python bindings.
#
# As this base image includes build essentials already in /usr/local,
# libraries are staged in "/gdal/usr/local".  The last build step clears
# /usr/local of other packages, then migrates the staging directory to
# /usr/local for consistency with other recipes.

# -----------------------------------------------------------------------------
# BASE IMAGE
# -----------------------------------------------------------------------------

# global args
ARG BASE_IMAGE="quay.io/pypa/manylinux2014_x86_64:2022-02-13-594988e"

# base image
FROM ${BASE_IMAGE} as base

# Set shell to bash
SHELL ["/usr/bin/env", "/bin/bash", "-euxvc"]

# staging & reporting directories, reused by each stage
ENV STAGING_DIR="/staging"
ENV REPORT_DIR="${STAGING_DIR}/usr/local/share/just/info"
RUN mkdir -p "${STAGING_DIR}" "${REPORT_DIR}";

# working directory (for download, unpack, build, etc.)
WORKDIR /tmp

# -----------------------------------------------------------------------------
# OPENJPEG v2
# -----------------------------------------------------------------------------
FROM base as openjpeg

# version argument
ARG OPENJPEG_VERSION=2.4.0

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
        -DCMAKE_BUILD_TYPE=Release; \
    make -j"$(nproc)"; \
    make install DESTDIR="${STAGING_DIR}"; \
    echo "${OPENJPEG_VERSION}" > "${REPORT_DIR}/openjpeg_version"; \
    #
    # cleanup
    rm -rf /tmp/*;


# -----------------------------------------------------------------------------
# ECW v5
# -----------------------------------------------------------------------------
FROM base as ecw

# version argument
ARG ECW_VERSION=5.5.0

# install
RUN \
    # local variables
    if [ "${ECW_VERSION}" == "5.4.0" ]; then \
      ZIP_FILE="erdas-ecw-sdk-5.4.0-update1-linux.zip"; \
      ZIP_URL="https://downloads.hexagongeospatial.com/software/2018/ECW/${ZIP_FILE}"; \
      UNPACK_DIR=/hexagon/ERDAS-ECW_JPEG_2000_SDK-5.4.0/Desktop_Read-Only; \
    elif [ "${ECW_VERSION}" == "5.5.0" ]; then \
      ZIP_FILE="erdas-ecw-jp2-sdk-v55-update-4-linux"; \
      ZIP_URL="https://go2.hexagongeospatial.com/${ZIP_FILE}"; \
      UNPACK_DIR=/root/hexagon/ERDAS-ECW_JPEG_2000_SDK-5.5.0/Desktop_Read-Only; \
    else \
      echo "Unrecognized ECW version ${ECW_VERSION}"; \
      exit 1; \
    fi; \
    #
    # download & unzip
    curl -fsSLO "${ZIP_URL}"; \
    unzip "${ZIP_FILE}"; \
    #
    # unpack & cleanup
    printf '1\nyes\n' | MORE=-V bash ./*.bin; \
    #
    # copy necessary files
    # this removes the "new ABI" .so files as they are note needed
    LOCAL_DIR="${STAGING_DIR}/usr/local/ecw"; \
    mkdir -p "${LOCAL_DIR}"; \
    cp -r "${UNPACK_DIR}"/{*.txt,bin,etc,include,lib,third*} "${LOCAL_DIR}"; \
    echo "${ECW_VERSION}" > "${REPORT_DIR}/ecw_version"; \
    #
    # remove the "new C++11 ABI"
    rm -rf "${LOCAL_DIR}"/{lib/cpp11abi,lib/newabi} \
           "${LOCAL_DIR}"/{lib/x64/debug,bin/x64/debug}; \
    #
    # cleanup
    rm -rf "${UNPACK_DIR}" /tmp/*;

# link .so files to "/usr/local/lib" for easier discovery
RUN mkdir -p "${STAGING_DIR}/usr/local/lib"; \
    cd "${STAGING_DIR}/usr/local/lib"; \
    ln -s ../ecw/lib/x64/release/libNCSEcw.so* .;


# -----------------------------------------------------------------------------
# LIBTIFF
# -----------------------------------------------------------------------------
# https://gitlab.com/libtiff/libtiff
FROM base as tiff

# version argument
ARG TIFF_VERSION=4.3.0

# additional build dependencies
RUN yum install -y \
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
FROM base as proj

# version argument
ARG PROJ_VERSION=8.1.1

# additional build dependencies
RUN yum install -y \
      libcurl-devel \
      libjpeg-turbo-devel \
      zlib-devel; \
    yum clean all

# local dependencies to staging directory
COPY --from=tiff ${STAGING_DIR}/usr/local /usr/local

# install
RUN \
    # download & unzip
    TAR_FILE="proj-${PROJ_VERSION}.tar.gz"; \
    curl -fsSLO "https://download.osgeo.org/proj/${TAR_FILE}"; \
    tar -xf ${TAR_FILE} --strip-components=1; \
    #
    # configure, build, & install
    ./configure \
        CFLAGS='-DPROJ_RENAME_SYMBOLS -O2' \
        CXXFLAGS='-DPROJ_RENAME_SYMBOLS -DPROJ_INTERNAL_CPP_NAMESPACE -O2' \
        --disable-static \
        | tee "${REPORT_DIR}/proj_configure"; \
    make -j"$(nproc)"; \
    make install "DESTDIR=${STAGING_DIR}"; \
    echo "${PROJ_VERSION}" > "${REPORT_DIR}/proj_version"; \
    #
    # cleanup
    rm -rf /tmp/*;


# -----------------------------------------------------------------------------
# GEOTIFF
# -----------------------------------------------------------------------------
# https://github.com/OSGeo/libgeotiff
FROM base as geotiff

# version argument
ARG GEOTIFF_VERSION=1.7.0

# additional build dependencies
RUN yum install -y \
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
FROM base as setup

# version argument
ARG GDAL_VERSION=3.3.3
ENV GDAL_VERSION=$GDAL_VERSION

# additional build dependencies
RUN yum install -y \
      geos-devel \
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
FROM setup as library

# local dependencies to staging directory
# base manylinux image has many other dependencies already in /usr/local,
# so we isolate packages in the staging directory
COPY --from=openjpeg ${STAGING_DIR} ${STAGING_DIR}
COPY --from=ecw ${STAGING_DIR} ${STAGING_DIR}
COPY --from=tiff ${STAGING_DIR} ${STAGING_DIR}
COPY --from=proj ${STAGING_DIR} ${STAGING_DIR}
COPY --from=geotiff ${STAGING_DIR} ${STAGING_DIR}

# local dependencies to /usr/local
# This is necessary only for those dependencies expected to be in a "normal"
# location. GDAL "configure" accepts direct paths for many packages, including
# ECW and PROJ.
COPY --from=openjpeg ${STAGING_DIR}/usr/local /usr/local

# add staged libraries
ENV LD_LIBRARY_PATH="${STAGING_DIR}/usr/local/lib"

# configure, build, & install
# https://raw.githubusercontent.com/OSGeo/gdal/master/gdal/configure
RUN \
    # configure
    ./configure \
        --without-libtool \
        --with-hide-internal-symbols \
        --with-jpeg=internal \
        --with-png=internal \
        --with-pcre=no \
        --with-libtiff="${STAGING_DIR}/usr/local" \
        --with-geotiff="${STAGING_DIR}/usr/local" \
        --with-openjpeg \
        --with-proj="${STAGING_DIR}/usr/local" \
        --with-ecw="${STAGING_DIR}/usr/local/ecw" \
        | tee "${REPORT_DIR}/gdal_configure"; \
    #
    # build & install
    make -j "$(nproc)"; \
    make install "DESTDIR=${STAGING_DIR}"; \
    echo "${GDAL_VERSION}" > "${REPORT_DIR}/gdal_version"; \
    #
    # cleanup
    rm -rf /tmp/*;


# -----------------------------------------------------------------------------
# GDAL build wheel
# -----------------------------------------------------------------------------
FROM setup as wheel

# version argument
ARG PYTHON_VERSION=3.9
ARG NUMPY_VERSION=1.22.3

# wheel directory
ENV WHEEL_DIR="${STAGING_DIR}/usr/local/share/just/wheels"

# local dependencies to /usr/local
COPY --from=library ${STAGING_DIR}/usr/local /usr/local

# build wheels
RUN mkdir -p "${WHEEL_DIR}"; \
    # SWIG directory
    SWIG_DIR="$(find . -type d -name 'swig' | head -n 1)"; \
    #
    # test for "use_2to3" in setup.py which requires older setuptools
    # https://github.com/OSGeo/gdal/issues/4467#issuecomment-916676916
    if grep -q 'use_2to3' "${SWIG_DIR}/python/setup.py"; then \
        SETUPTOOLS_DEP="setuptools<58"; \
    fi; \
    #
    # python flavor
    if [[ "${PYTHON_VERSION}" == 3.7* ]]; then \
      PYNAME='cp37-cp37m'; \
    elif [[ "${PYTHON_VERSION}" == 3.8* ]]; then \
      PYNAME='cp38-cp38'; \
    elif [[ "${PYTHON_VERSION}" == 3.9* ]]; then \
      PYNAME='cp39-cp39'; \
    elif [[ "${PYTHON_VERSION}" == 3.10* ]]; then \
      PYNAME='cp310-cp310'; \
    else \
      echo "Unrecognized PYTHON_VERSION=${PYTHON_VERSION}" >&2; \
      exit 1; \
    fi; \
    PYBIN="/opt/python/${PYNAME}/bin"; \
    #
    # install python dependencies
    "${PYBIN}/pip" install \
        ${SETUPTOOLS_DEP:-} \
        numpy==${NUMPY_VERSION}; \
    # build wheel
    "${PYBIN}/pip" wheel "${SWIG_DIR}/python" \
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
