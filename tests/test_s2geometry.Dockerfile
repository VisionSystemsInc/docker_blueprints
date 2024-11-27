ARG S2_IMAGE=vsiri/blueprint_test:s2
ARG PYTHON_VERSION=3.10
FROM ${S2_IMAGE} AS s2

FROM python:"${PYTHON_VERSION}"

SHELL ["/usr/bin/env", "bash", "-euxvc"]

COPY --from=s2 /usr/local /usr/local

RUN "/usr/local/bin/python" -m venv /venv; \
    /venv/bin/pip install /usr/local/share/just/wheels/*
