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

# copy from blueprints
COPY --from=gdal /usr/local /usr/local
COPY --from=pdal /usr/local /usr/local

# Only needs to be run once for all blueprints/recipes
ENV LD_LIBRARY_PATH="/usr/local/lib64"
RUN shopt -s nullglob; for patch in /usr/local/share/just/container_build_patch/*; do "${patch}"; done

# install numpy first, then pdal from wheel
RUN pip install numpy==${NUMPY_VERSION}; \
    pip install /usr/local/share/just/wheels/PDAL*.whl;
