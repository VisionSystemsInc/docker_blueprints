# global args
ARG GDAL_IMAGE="vsiri/blueprint_test:gdal"
ARG PYTHON_VERSION="3.13.15"

# blueprints
FROM ${GDAL_IMAGE} AS gdal

# base image
FROM python:"${PYTHON_VERSION}"
SHELL ["/usr/bin/env", "bash", "-euxvc"]

# local args
ARG NUMPY_VERSION

# copy wheels
COPY --from=gdal /usr/local /usr/local

# install numpy then python bindings
RUN "/usr/local/bin/python" -m venv /venv; \
    source /venv/bin/activate; \
    pip install numpy==${NUMPY_VERSION}; \
    pip install /usr/local/share/just/wheels/*.whl

# add system-wide PROJ_DATA & GDAL_DATA
COPY --from=gdal /opt/proj_data /opt/proj_data
COPY --from=gdal /opt/gdal_data /opt/gdal_data
ENV PROJ_DATA=/opt/proj_data \
    GDAL_DATA=/opt/gdal_data

# point GDAL to plugins
ENV GDAL_DRIVER_PATH=/venv/lib/python3.13/site-packages/osgeo/gdal_dir/gdalplugins
