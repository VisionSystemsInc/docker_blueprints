ARG GLOG_IMAGE=vsiri/blueprint_test:glog
ARG PYTHON_VERSION=3.9
FROM ${GLOG_IMAGE} AS glog

FROM python:"${PYTHON_VERSION}"

SHELL ["/usr/bin/env", "bash", "-euxvc"]

COPY --from=glog /usr/local /usr/local

RUN "/usr/local/bin/python" -m venv /venv; \
    /venv/bin/pip install /usr/local/share/just/wheels/*
