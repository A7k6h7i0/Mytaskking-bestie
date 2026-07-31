#include "record_windows_plugin.h"

#include <flutter/standard_method_codec.h>

#include <memory>

namespace record_windows {

void RecordWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "com.llfbandit.record/messages",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<RecordWindowsPlugin>();
  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

RecordWindowsPlugin::RecordWindowsPlugin() {}

RecordWindowsPlugin::~RecordWindowsPlugin() {}

void RecordWindowsPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& name = method_call.method_name();
  if (name == "create" ||
      name == "pause" ||
      name == "resume" ||
      name == "start" ||
      name == "startStream" ||
      name == "cancel" ||
      name == "dispose") {
    result->Success(flutter::EncodableValue());
    return;
  }

  if (name == "hasPermission") {
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (name == "isPaused" || name == "isRecording" || name == "isEncoderSupported") {
    result->Success(flutter::EncodableValue(false));
    return;
  }

  if (name == "stop") {
    result->Success(flutter::EncodableValue());
    return;
  }

  if (name == "getAmplitude") {
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("current"), flutter::EncodableValue(0.0)},
        {flutter::EncodableValue("max"), flutter::EncodableValue(0.0)},
    }));
    return;
  }

  if (name == "listInputDevices") {
    result->Success(flutter::EncodableValue(flutter::EncodableList{}));
    return;
  }

  result->NotImplemented();
}

}  // namespace record_windows
