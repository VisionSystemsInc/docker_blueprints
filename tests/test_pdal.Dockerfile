# global args
ARG GDAL_IMAGE="vsiri/blueprint_test:gdal"
ARG PDAL_IMAGE="vsiri/blueprint_test:pdal"
ARG PYTHON_VERSION="3.13.15"

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

# access to lib64 packages
ENV LD_LIBRARY_PATH="/usr/local/lib64"

# Only needs to be run once for all blueprints/recipes
RUN shopt -s nullglob; for patch in /usr/local/share/just/container_build_patch/*; do "${patch}"; done

# install numpy first, then pdal from wheel
RUN "/usr/local/bin/python" -m venv /venv; \
    source /venv/bin/activate; \
    pip install numpy==${NUMPY_VERSION}; \
    pip install /usr/local/share/just/wheels/pdal*.whl;
