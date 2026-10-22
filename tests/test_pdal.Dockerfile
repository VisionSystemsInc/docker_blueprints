# global args
ARG PDAL_IMAGE="vsiri/blueprint_test:pdal"
ARG PYTHON_VERSION="3.13.15"

# blueprints
FROM ${PDAL_IMAGE} as pdal

# base image
FROM python:"${PYTHON_VERSION}"
SHELL ["/usr/bin/env", "bash", "-euxvc"]

# build args
ARG NUMPY_VERSION

# copy wheels
COPY --from=pdal /usr/local /usr/local

# install numpy first, then pdal from wheel
RUN "/usr/local/bin/python" -m venv /venv; \
    source /venv/bin/activate; \
    pip install numpy==${NUMPY_VERSION}; \
    pip install /usr/local/share/just/wheels/pdal*.whl;

# add system-wide PROJ_DATA & GDAL_DATA
COPY --from=pdal /opt/proj_data /opt/proj_data
COPY --from=pdal /opt/gdal_data /opt/gdal_data
ENV PROJ_DATA=/opt/proj_data \
    GDAL_DATA=/opt/gdal_data
