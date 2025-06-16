#pragma once

#include <pybind11/pybind11.h>

#include <ng-log/logging.h>

// using namespace nglog
using namespace pybind11::literals;
namespace py = pybind11;

struct Logging {
  enum class LogSeverity {
    INFO = nglog::INFO,
    WARNING = nglog::WARNING,
    ERROR = nglog::ERROR,
    FATAL = nglog::FATAL,
  };
};  // dummy class

std::pair<std::string, int> GetPythonCallFrame() {
  const auto frame = py::module_::import("sys").attr("_getframe")(0);
  const std::string file = py::str(frame.attr("f_code").attr("co_filename"));
  const std::string function = py::str(frame.attr("f_code").attr("co_name"));
  const int line = py::int_(frame.attr("f_lineno"));
  return std::make_pair(file + ":" + function, line);
}

void BindNglog11(py::module& m) {
  py::class_<Logging> PyLogging(m, "logging", py::module_local());

  py::enum_<Logging::LogSeverity>(PyLogging, "Level")
      .value("INFO", Logging::LogSeverity::INFO)
      .value("WARNING", Logging::LogSeverity::WARNING)
      .value("ERROR", Logging::LogSeverity::ERROR)
      .value("FATAL", Logging::LogSeverity::FATAL)
      .export_values();

  PyLogging.def_readwrite_static("minloglevel", &FLAGS_minloglevel)
      .def_readwrite_static("stderrthreshold", &FLAGS_stderrthreshold)
      .def_readwrite_static("log_dir", &FLAGS_log_dir)
      .def_readwrite_static("logtostderr", &FLAGS_logtostderr)
      .def_readwrite_static("alsologtostderr", &FLAGS_alsologtostderr)
      .def_readwrite_static("verbose_level", &FLAGS_v)
      .def_static(
          "set_log_destination",
          [](const Logging::LogSeverity severity, const std::string& path) {
            nglog::SetLogDestination(
                static_cast<nglog::LogSeverity>(severity), path.c_str());
          },
          "level"_a,
          "path"_a)
      .def_static(
          "verbose",
          [](const int level, const std::string& msg) {
            if (VLOG_IS_ON(level)) {
              const auto frame = GetPythonCallFrame();
              nglog::LogMessage(frame.first.c_str(), frame.second).stream()
                  << msg;
            }
          },
          "level"_a,
          "message"_a)
      .def_static(
          "info",
          [](const std::string& msg) {
            const auto frame = GetPythonCallFrame();
            nglog::LogMessage(frame.first.c_str(), frame.second).stream()
                << msg;
          },
          "message"_a)
      .def_static(
          "warning",
          [](const std::string& msg) {
            const auto frame = GetPythonCallFrame();
            nglog::LogMessage(
                frame.first.c_str(), frame.second, nglog::WARNING)
                    .stream()
                << msg;
          },
          "message"_a)
      .def_static(
          "error",
          [](const std::string& msg) {
            const auto frame = GetPythonCallFrame();
            nglog::LogMessage(
                frame.first.c_str(), frame.second, nglog::ERROR)
                    .stream()
                << msg;
          },
          "message"_a)
      .def_static(
          "fatal",
          [](const std::string& msg) {
            const auto frame = GetPythonCallFrame();
            nglog::LogMessageFatal(frame.first.c_str(), frame.second).stream()
                << msg;
          },
          "message"_a);

    m.def("initializeLogging",
          [](const std::string& name) {
            // Requires verion 0.6 or newer
            if (!nglog::IsLoggingInitialized())
            {
              nglog::InitializeLogging(name.c_str());
            }
          },
          py::arg("name") = std::string(""))
      .def("installFailureSignalHandler", &nglog::InstallFailureSignalHandler);

  FLAGS_alsologtostderr = true;
}
