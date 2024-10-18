#include <pybind11/iostream.h>
#include <pybind11/pybind11.h>
#include <pybind11/stl.h>

#include "py_glog11.h"

// using namespace glog11;
namespace py = pybind11;

PYBIND11_MODULE(glog11, m) {
  m.doc() = "glog wrapper using pybind11";
#ifdef VERSION_INFO
  m.attr("__version__") = py::str(VERSION_INFO);
#else
  m.attr("__version__") = py::str("dev");
#endif

  BindGlog11(m);
  py::add_ostream_redirect(m, "ostream");
}