ARG BASE_IMAGE=quay.io/pypa/manylinux_2_28_x86_64
FROM "${BASE_IMAGE}" AS builder

SHELL ["/usr/bin/env", "/bin/bash", "-euxvc"]

RUN dnf install -y \
          openssl-devel \
          https://dl.fedoraproject.org/pub/epel/8/Modular/x86_64/Packages/s/swig-4.0.2-9.module_el8+12710+46f2eec2.x86_64.rpm; \
    rm -rf /var/cache/yum/*

ARG ABSEIL_VERSION=20240722.0

RUN git clone https://github.com/abseil/abseil-cpp.git /absl; \
    cd /absl; \
    git checkout "${ABSEIL_VERSION}"; \
    cmake -B /absl/build \
      -DCMAKE_PREFIX_PATH=/usr/local \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DABSL_ENABLE_INSTALL=ON \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DBUILD_TESTING=OFF \
      -DCMAKE_CXX_STANDARD=20 \
      -DABSL_BUILD_TESTING=OFF; \
    cmake --build /absl/build --target install; \
    cd /; \
    rm -r /absl

ARG S2GEOMETRY_VERSION=v0.11.1
ARG PYTHON_VERSION=3.10.15

RUN python_major=${PYTHON_VERSION%%.*}; \
    python_minor=${PYTHON_VERSION#*.}; \
    python_minor=${python_minor%%.*}; \
    python_dir=("/opt/python/cp${python_major}${python_minor}-"cp*[0-9m]); \
    git clone https://github.com/google/s2geometry.git /s2geometry; \
    cd /s2geometry; \
    git checkout "${S2GEOMETRY_VERSION}"; \
    # Temp patch for: https://github.com/google/s2geometry/pull/394/
    sed -Ei 's|(find_package\(Python3.*Development)\)|\1.Module)|' CMakeLists.txt; \
    # https://github.com/diegoferigo/cmake-build-extension/blob/4bd5dab5c2e3eeaf5ed1b40d7aa159b83a1fb7c9/README.md?plain=1#L124
    "${python_dir}/bin/pip" install build; \
    "${python_dir}/bin/python" -m build --wheel \
      "-C--global-option=build_ext" \
      "-C--global-option=-DPython3_EXECUTABLE=${python_dir}/bin/python;Python3_INCLUDE_DIR=${python_dir}/include/python${python_major}.${python_minor};BUILD_TESTS=OFF;CMAKE_CXX_STANDARD=20"; \
    auditwheel repair dist/s2geometry*.whl -w /usr/local/share/just/wheels; \
    cd /; \
    rm -r s2geometry

FROM scratch

COPY --from=builder /usr/local/share/just/wheels /usr/local/share/just/wheels
