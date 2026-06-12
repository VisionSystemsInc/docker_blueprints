ARG KTX_IMAGE=vsiri/blueprint_test:ktx
ARG PYTHON_VERSION=3.13.12

FROM ${KTX_IMAGE} AS ktx

FROM python:"${PYTHON_VERSION}"

SHELL ["/usr/bin/env", "bash", "-euxvc"]

COPY --from=ktx /usr/local /usr/local

RUN "/usr/local/bin/python" -m venv /venv; \
    /venv/bin/pip install /usr/local/share/just/wheels/*
