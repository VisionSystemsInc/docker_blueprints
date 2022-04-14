# global args
ARG GDAL_IMAGE
ARG PDAL_IMAGE

# blueprints
FROM ${GDAL_IMAGE} as gdal
FROM ${PDAL_IMAGE} as pdal

# base image
FROM python:3.8
SHELL ["/usr/bin/env", "bash", "-euxvc"]

# additional runtime dependencies
RUN apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        libgeos-c1v5; \
    rm -r /var/lib/apt/lists/*

# copy from blueprints
COPY --from=gdal /usr/local /usr/local
COPY --from=pdal /usr/local /usr/local

# install pdal python bindings
# PDAL is built in in a manylinux container using the old C++ ABI.
# Ensure the pdal python wheel is built from source using the same ABI.
# note PDAL python bindings are versioned separately from PDAL
RUN CXXFLAGS="-D_GLIBCXX_USE_CXX11_ABI=0" pip install PDAL

# Only needs to be run once for all blueprints/recipes
RUN for patch in /usr/local/share/just/container_build_patch/*; do "${patch}"; done
