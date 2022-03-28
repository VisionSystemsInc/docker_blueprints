=================
Docker Blueprints
=================

.. image:: https://circleci.com/gh/VisionSystemsInc/docker_blueprints.svg?style=svg
   :target: https://circleci.com/gh/VisionSystemsInc/docker_blueprints
   :alt: CirclCI

A docker blueprint is a (usually complex) docker image that can be included in a multi-stage build so that you don't always have to find and repeat that "perfect set of Dockerfile lines to include software XYZ", such as GDAL, PDAL, etc. , tini, etc.


Blueprints
==========

GDAL
----

============ ============
Name         GDAL
Build Args   ``GDAL_VERSION`` - Version of GDAL to download
Output dir   ``/usr/local``
============ ============

Compiles GDAL v3, including OPENJPEG 2.4, ECW J2K 5.5, libtiff4.3, libgeotiff 1.7, PROJ v8

.. rubric:: Example

.. code-block:: Dockerfile

   FROM vsiri/blueprints:gdal as gdal
   FROM python:3.8
   COPY --from=gdal /usr/local /usr/local

   # numpy must be installed before GDAL python bindings
   RUN pip install numpy;

   # install GDAL with specific compiler flags
   # GDAL is built in in a manylinux container using the old C++ ABI.
   # Ensure the gdal wheel is built from source using the same ABI.
   RUN GDAL_VERSION=$(cat /usr/local/share/just/info/gdal_version); \
       CFLAGS="-D_GLIBCXX_USE_CXX11_ABI=0" pip install GDAL==${GDAL_VERSION};

   # Only needs to be run once for all blueprints/recipes
   RUN for patch in /usr/local/share/just/container_build_patch/*; do "${patch}"; done

PDAL
----

============ ============
Name         GDAL
Build Args   ``PDAL_VERSION`` - Version of PDAL to download
Output dir   ``/usr/local``
============ ============

Compiles PDAL v2. Requires GDAL blueprint.

.. rubric:: Example

.. code-block:: Dockerfile

   FROM vsiri/blueprints:gdal as gdal
   FROM vsiri/blueprints:pdal as gdal
   FROM python:3.8
   COPY --from=gdal /usr/local /usr/local
   COPY --from=pdal /usr/local /usr/local

   # install pdal python bindings
   # note PDAL python bindings are versioned separately from PDAL
   # PDAL is built in in a manylinux container using the old C++ ABI.
   # Ensure the pdal python wheel is built from source using the same ABI.
   RUN CXXFLAGS="-D_GLIBCXX_USE_CXX11_ABI=0" pip install PDAL

   # Only needs to be run once for all recipes
   RUN for patch in /usr/local/share/just/container_build_patch/*; do "${patch}"; done

