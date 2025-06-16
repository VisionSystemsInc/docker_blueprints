ARG NGLOG_IMAGE=vsiri/blueprint_test:nglog
ARG PYTHON_VERSION=3.9
FROM ${NGLOG_IMAGE} AS nglog

FROM python:"${PYTHON_VERSION}"

SHELL ["/usr/bin/env", "bash", "-euxvc"]

COPY --from=nglog /usr/local /usr/local

RUN /usr/local/bin/python -m venv /venv; \
    /venv/bin/pip install /usr/local/share/just/wheels/*
