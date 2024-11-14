# ARG BASE_IMAGE="quay.io/pypa/manylinux2014_x86_64:2024-07-02-9ac04ee"
ARG BASE_IMAGE=quay.io/pypa/manylinux_2_28_x86_64
FROM "${BASE_IMAGE}" AS builder

SHELL ["/usr/bin/env", "/bin/bash", "-euxvc"]

ARG LIBUNWIND_VERSION=v1.6.2

RUN git clone https://github.com/libunwind/libunwind.git /libunwind; \
    cd /libunwind; \
    git checkout "${LIBUNWIND_VERSION}"; \
    autoreconf -i; \
    ./configure prefix=/usr/local libdir=/usr/local/lib64; \
    make; \
    make install; \
    cd /

ARG GLOG_VERSION=v0.7.1

RUN git clone https://github.com/google/glog.git /glog; \
    cd /glog; \
    git checkout "${GLOG_VERSION}"; \
    mkdir build; \
    cd build; \
    cmake .. -D CMAKE_BUILD_TYPE=Release; \
    make; \
    make install; \
    cd /; \
    rm -r glog

COPY pyglog /pyglog

ARG PYTHON_VERSION=3.8.12

RUN curl -L https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64 -o /usr/local/bin/yq; \
    chmod 755 /usr/local/bin/yq; \
    python_major=${PYTHON_VERSION%%.*}; \
    python_minor=${PYTHON_VERSION#*.}; \
    python_minor=${python_minor%%.*}; \
    python_dir=("/opt/python/cp${python_major}${python_minor}-"cp*[0-9m]); \
    echo /usr/local/lib64 > /etc/ld.so.conf.d/10-local.conf; \
    ldconfig; \
    # Dynamically set version
    sed -i 's/^version = .*/version = "'"${GLOG_VERSION}"'"/' /pyglog/pyproject.toml; \
    # TODO: Add --no-deps --no-build-isolation, requirements.in, .txt, pip-tools, etc...
    "${python_dir}/bin/python" -m venv /tmp/venv; \
    /tmp/venv/bin/pip install -r /pyglog/requirements${python_major}${python_minor}.txt; \
    /tmp/venv/bin/pip wheel --no-deps --no-build-isolation /pyglog; \
    auditwheel repair pyglog*cp"${python_major}${python_minor}"*.whl -w /usr/local/share/just/wheels; \
    rm -r pyglog*cp"${python_major}${python_minor}"*.whl /tmp/venv

FROM scratch

COPY --from=builder /usr/local/share/just/wheels /usr/local/share/just/wheels
