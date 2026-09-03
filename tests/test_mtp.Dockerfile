ARG MTP_IMAGE
ARG PYTHON_VERSION

# blueprints
FROM ${MTP_IMAGE} AS mtp

# base image
FROM python:"${PYTHON_VERSION}"
SHELL ["/usr/bin/env", "bash", "-euxvc"]

# install torch
ARG TORCH_VERSION="2.9.1+cu129"
RUN --mount=type=cache,target=/cache/pip,mode=0755 \
    torch_url="https://download.pytorch.org/whl/${TORCH_VERSION#*+}"; \
    pip install --extra-index-url ${torch_url} "torch==${TORCH_VERSION}"

# copy from blueprints
COPY --from=mtp /usr/local /usr/local

# install DCNv3 from MTP
RUN --mount=type=cache,target=/cache/pip,mode=0755 \
    pip install /usr/local/share/just/wheels/*.whl;
