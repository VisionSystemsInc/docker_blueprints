ARG SAM2_IMAGE
ARG PYTHON_VERSION

# blueprints
FROM ${SAM2_IMAGE} AS sam2

# base image
FROM python:"${PYTHON_VERSION}"
SHELL ["/usr/bin/env", "bash", "-euxvc"]

# install torch & torchvision
ARG TORCH_VERSION="2.9.1+cu129"
RUN --mount=type=cache,target=/cache/pip,mode=0755 \
    torch_url="https://download.pytorch.org/whl/${TORCH_VERSION#*+}"; \
    pip install --extra-index-url ${torch_url} "torch==${TORCH_VERSION}" "torchvision"

# copy from blueprints
COPY --from=sam2 /usr/local /usr/local

# install wheel
RUN --mount=type=cache,target=/cache/pip,mode=0755 \
    pip install /usr/local/share/just/wheels/*.whl;
