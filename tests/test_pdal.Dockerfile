# global args
ARG GDAL_IMAGE
ARG PDAL_IMAGE
ARG PYTHON_VERSION

# blueprints
FROM ${GDAL_IMAGE} as gdal
FROM ${PDAL_IMAGE} as pdal

# base image
FROM python:${PYTHON_VERSION}
SHELL ["/usr/bin/env", "bash", "-euxvc"]

# build args
ARG NUMPY_VERSION

# additional runtime dependencies
RUN apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        libgeos-c1v5; \
    rm -r /var/lib/apt/lists/*

# copy from blueprints
COPY --from=gdal /usr/local /usr/local
COPY --from=pdal /usr/local /usr/local

# Only needs to be run once for all blueprints/recipes
RUN shopt -s nullglob; for patch in /usr/local/share/just/container_build_patch/*; do "${patch}"; done

# install numpy first, then pdal from wheel
RUN pip install numpy==${NUMPY_VERSION}; \
    pip install /usr/local/share/just/wheels/PDAL*.whl;
