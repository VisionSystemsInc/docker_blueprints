=================
Docker Blueprints
=================

.. image:: https://circleci.com/gh/VisionSystemsInc/docker_blueprints.svg?style=svg
   :target: https://circleci.com/gh/VisionSystemsInc/docker_blueprints
   :alt: CirclCI

A docker blueprint is a (usually complex) docker image that can be included in a multi-stage build so that you don't always have to find and repeat that "perfect set of Dockerfile lines to include software XYZ", such as GDAL, PDAL, etc.


How to use
==========

Add blueprint services to your docker-compose.yml file, using project specific image names. For example:

.. code-block:: yaml

   services:

      gdal:
         build:
            context: "${VSI_COMMON_DIR}/docker/blueprints"
            dockerfile: blueprint_gdal.Dockerfile
            args:
               GDAL_VERSION: "3.3.3"
         image: &gdal_image
            example/project:gdal

      pdal:
         build:
            context: "${VSI_COMMON_DIR}/docker/blueprints"
            dockerfile: blueprint_pdal.Dockerfile
            args:
               GDAL_IMAGE: *gdal_image
               PDAL_VERSION: "2.3.0"
         image: &pdal_image
            example/project:pdal

      example:
         build:
            context: .
            dockerfile: example.Dockerfile
            args:
               GDAL_IMAGE: *gdal_image
               PDAL_IMAGE: *pdal_image
         image: example/project:example


The Dockerfile is then formulated as follows

.. code-block:: Dockerfile

   # blueprints
   ARG GDAL_IMAGE
   ARG PDAL_IMAGE
   FROM ${GDAL_IMAGE} AS gdal
   FROM ${PDAL_IMAGE} AS pdal

   # base image
   FROM python:3.8

   # copy from blueprints
   COPY --from=gdal /usr/local /usr/local
   COPY --from=pdal /usr/local /usr/local

   # Only needs to be run once for all blueprints/recipes
   RUN shopt -s nullglob; for patch in /usr/local/share/just/container_build_patch/*; do "${patch}"; done


Python Wheels
=============

Docker blueprints may also build python wheels for a given tool.
For example, GDAL python bindings are compiled against a user-specified
``PYTHON_VERSION`` and ``NUMPY_VERSION`` as follows:

.. code-block:: yaml

   services:

      gdal:
         build:
            context: "${VSI_COMMON_DIR}/docker/blueprints"
            dockerfile: blueprint_gdal.Dockerfile
            args:
               GDAL_VERSION: "3.3.3"
               PYTHON_VERSION: "3.9"
               NUMPY_VERSION: "1.22.3"
         image: example/project:gdal


Blueprints
==========


GDAL
----

========== ================== ====
Name       GDAL
Output dir ``/usr/local``
Build Args ``GDAL_VERSION``   Version of GDAL to download
..         ``PYTHON_VERSION`` Build python bindings for this python version
..         ``NUMPY_VERSION``  Build python bindings for this numpy version
========== ================== ====

Compiles GDAL v3, including OPENJPEG 2.4, GEOS 3.11.0, libtiff 4.3, libgeotiff 1.7, PROJ v8

.. code-block:: Dockerfile

   # global arguments
   ARG PYTHON_VERSION

   # blueprint input(s)
   FROM example/project:gdal AS gdal

   # base image
   FROM python:$PYTHON_VERSION

   # local args
   ARG NUMPY_VERSION

   # additional runtime dependencies
   RUN apt-get update; \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
         libgeos-c1v5; \
      rm -r /var/lib/apt/lists/*

   # add blueprint
   COPY --from=gdal /usr/local /usr/local

   # Patch all blueprints/recipes
   RUN shopt -s nullglob; for patch in /usr/local/share/just/container_build_patch/*; do "${patch}"; done

   # install numpy then GDAL python bindings
   RUN pip install numpy==${NUMPY_VERSION}; \
       pip install /usr/local/share/just/wheels/GDAL*.whl


PDAL
----

========== ======================= ====
Name       PDAL
Output dir ``/usr/local``
Build Args ``PDAL_VERSION``        Version of PDAL to download
..         ``PDAL_PYTHON_VERSION`` Version of PDAL python bindings to download
..         ``PYTHON_VERSION``      Build python bindings for this python version
..         ``NUMPY_VERSION``       Build python bindings for this numpy version
========== ======================= ====

Compiles PDAL v2. Requires GDAL blueprint.

.. code-block:: Dockerfile

   # global arguments
   ARG PYTHON_VERSION

   # blueprint input(s)
   FROM example/project:gdal AS gdal
   FROM example/project:pdal AS pdal

   # base image
   FROM python:$PYTHON_VERSION

   # local args
   ARG NUMPY_VERSION

   # additional runtime dependencies
   RUN apt-get update; \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
         libgeos-c1v5; \
      rm -r /var/lib/apt/lists/*

   # add blueprint(s)
   COPY --from=gdal /usr/local /usr/local
   COPY --from-pdal /usr/local /usr/local

   # Patch all blueprints/recipes
   RUN shopt -s nullglob; for patch in /usr/local/share/just/container_build_patch/*; do "${patch}"; done

   # install numpy then GDAL python bindings
   RUN pip install numpy==${NUMPY_VERSION}; \
       pip install /usr/local/share/just/wheels/PDAL*.whl

SWIG bindings for S2Geometry
----------------------------

.. code-block:: yaml

   services:

      glog:
         build:
            context: "${VSI_COMMON_DIR}/docker/blueprints"
            dockerfile: blueprint_s2geometry.Dockerfile
            args:
               # S2GEOMETRY_VERSION: "v0.11.1"
               # https://github.com/google/s2geometry/tags
               # PYTHON_VERSION: "3.10.15"
               # https://hub.docker.com/_/python/tags
               # BASE_IMAGE: "python:3.10.15-bookworm"
               # https://hub.docker.com/_/python/tags
               # ABSEIL_VERSION: "v1.6.2"
               # https://github.com/abseil/abseil-cpp/tags
         image: &s2_image
            example/project:s2

      example:
         build:
            context: .
            dockerfile: example.Dockerfile
            args:
               GLOG_IMAGE: *s2_image
         image: example/project:example

========== ======================= ====
Name       S2 Geometry
Output dir ``/usr/local``
Build Args ``BASE_IMAGE``          Base image to build the wheel in. Currenylt works in Debian instead of Alma
..         ``PYTHON_VERSION``      Build python bindings for this python version
..         ``ABSEIL_VERSION``      Abseil version to build from source
..         ``S2GEOMETRY_VERSION``  S2 Geometry version to build from source
========== ======================= ====

Compiles S2 Geometry wheel for use in python.

.. code-block:: Dockerfile

   # global arguments
   ARG S2_IMAGE
   FROM ${S2_IMAGE} AS s2

   FROM some_image

   ...

   COPY --from=s2 /usr/local /usr/local

   RUN pip install /usr/local/share/just/wheels/*
   # Or using pip-tools, add "--find-links /usr/local/share/just/wheels" to requirements.in

.. code-block:: example.py

    import s2Geometry as s2

    ll = s2.S2LatLng.FromDegrees(51.5001525, -0.1262355)
    print(s2.S2CellId(ll).ToToken())


pybind11 bindings for glog
--------------------------

.. code-block:: yaml

   services:

      glog:
         build:
            context: "${VSI_COMMON_DIR}/docker/blueprints"
            dockerfile: blueprint_glog.Dockerfile
            args:
               # GLOG_VERSION: "v0.7.1"
               # https://github.com/google/glog/tags
               # PYTHON_VERSION: "3.8.12"
               # https://github.com/pypa/manylinux/blob/main/docker/Dockerfile
               # BASE_IMAGE: "quay.io/pypa/manylinux_2_28_x86_64"
               # https://quay.io/repository/pypa/manylinux_2_28_x86_64?tab=tags&tag=latest
               # LIBUNWIND_VERSION: "v1.6.2"
               # https://github.com/libunwind/libunwind/tags
         image: &glog_image
            example/project:glog

      example:
         build:
            context: .
            dockerfile: example.Dockerfile
            args:
               GLOG_IMAGE: *glog_image
         image: example/project:example


========== ======================= ====
Name       Google Logging
Output dir ``/usr/local``
Build Args ``BASE_IMAGE``          Base image to build the wheel in. Default: `quay.io/pypa/manylinux_2_28_x86_64`
..         ``PYTHON_VERSION``      Build python bindings for this python version
..         ``LIBUNWIND_VERSION``   LibUnwind version to build from source
..         ``GLOG_VERSION``        Glog version to build from source
========== ======================= ====

Compiles glog wheel for use in python. This is primarily to setup [Failure Signal Handlers](https://google.github.io/glog/0.7.1/failures/).

.. code-block:: Dockerfile

   # global arguments
   ARG GLOG_IMAGE
   FROM ${GLOG_IMAGE} AS glog

   FROM some_image

   ...

   COPY --from=glog /usr/local /usr/local

   RUN pip install /usr/local/share/just/wheels/*
   # Or using pip-tools, add "--find-links /usr/local/share/just/wheels" to requirements.in

.. code-block:: example.py

    import pyglog

    pyglog.initGoogleLogging("programName")
    pyglog.installFailureSignalHandler()

---------------------
Blueprint maintenance
---------------------

To update build dependencies: `docker compose run -f maintenance.yml--rm glog-compile`
