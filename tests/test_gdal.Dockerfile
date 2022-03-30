# global args
ARG GDAL_IMAGE

# blueprints
FROM ${GDAL_IMAGE} as gdal

# base image
FROM python:3.8
SHELL ["/usr/bin/env", "bash", "-euxvc"]

# copy from blueprints
COPY --from=gdal /usr/local /usr/local

# numpy must be installed before GDAL python bindings
RUN pip install numpy;

# install GDAL with specific compiler flags
# GDAL is built in in a manylinux container using the old C++ ABI.
# Ensure the gdal wheel is built from source using the same ABI.
RUN GDAL_VERSION=$(cat /usr/local/share/just/info/gdal_version); \
    CFLAGS="-D_GLIBCXX_USE_CXX11_ABI=0" pip install GDAL==${GDAL_VERSION};

# Only needs to be run once for all blueprints/recipes
RUN for patch in /usr/local/share/just/container_build_patch/*; do "${patch}"; done
