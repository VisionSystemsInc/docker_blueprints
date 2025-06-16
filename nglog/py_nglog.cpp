#include <pybind11/iostream.h>
#include <pybind11/pybind11.h>
#include <pybind11/stl.h>

#include "py_nglog.h"

// using namespace nglog;
namespace py = pybind11;

PYBIND11_MODULE(nglog, m) {
  m.doc() = "ng-log wrapper using pybind11";
#ifdef VERSION_INFO
  m.attr("__version__") = py::str(VERSION_INFO);
#else
  m.attr("__version__") = py::str("dev");
#endif

  BindNglog11(m);
  py::add_ostream_redirect(m, "ostream");
}