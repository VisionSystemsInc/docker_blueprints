ARG OPENVDB_IMAGE=vsiri/blueprint_test:openvdb
ARG PYTHON_VERSION=3.13.12

FROM ${OPENVDB_IMAGE} AS openvdb

FROM python:"${PYTHON_VERSION}"

SHELL ["/usr/bin/env", "bash", "-euxvc"]

COPY --from=openvdb /usr/local /usr/local

RUN "/usr/local/bin/python" -m venv /venv; \
    /venv/bin/pip install /usr/local/share/just/wheels/*
