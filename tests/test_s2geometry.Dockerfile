ARG S2GEOMETRY_IMAGE=vsiri/blueprint_test:s2geometry
ARG PYTHON_VERSION=3.10
FROM ${S2GEOMETRY_IMAGE} AS s2geometry

FROM python:"${PYTHON_VERSION}"

SHELL ["/usr/bin/env", "bash", "-euxvc"]

COPY --from=s2geometry /usr/local /usr/local

RUN "/usr/local/bin/python" -m venv /venv; \
    /venv/bin/pip install /usr/local/share/just/wheels/*
