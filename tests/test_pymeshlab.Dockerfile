ARG PYMESHLAB_IMAGE=vsiri/blueprint_test:pymeshlab
ARG PYTHON_VERSION=3.13.12
FROM ${PYMESHLAB_IMAGE} AS pymeshlab

FROM python:"${PYTHON_VERSION}"

SHELL ["/usr/bin/env", "bash", "-euxvc"]

RUN apt update; apt install -y libgl1

COPY --from=pymeshlab /usr/local /usr/local

RUN /usr/local/bin/python -m venv /venv; \
    /venv/bin/pip install pytest /usr/local/share/just/wheels/*
