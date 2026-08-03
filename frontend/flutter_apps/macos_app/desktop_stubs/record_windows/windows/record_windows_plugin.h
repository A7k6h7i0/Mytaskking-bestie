#ifndef FLUTTER_PLUGIN_RECORD_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_RECORD_WINDOWS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace record_windows {

class RecordWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  RecordWindowsPlugin();
  ~RecordWindowsPlugin() override;

  RecordWindowsPlugin(const RecordWindowsPlugin&) = delete;
  RecordWindowsPlugin& operator=(const RecordWindowsPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace record_windows

#endif  // FLUTTER_PLUGIN_RECORD_WINDOWS_PLUGIN_H_
