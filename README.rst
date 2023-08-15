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
   FROM ${GDAL_IMAGE} as gdal
   FROM ${PDAL_IMAGE} as pdal

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
   FROM example/project:gdal as gdal

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
   FROM example/project:gdal as gdal
   FROM example/project:pdal as pdal

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
