#include "C:/Users/Sarif/Downloads/Documents/ADD PHONE BOOK/Mytaskking-bestie/frontend/flutter_apps/windows_app/desktop_stubs/flutter_secure_storage_windows/windows/include/flutter_secure_storage_windows/flutter_secure_storage_windows_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <unordered_map>

namespace {

class FlutterSecureStorageWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    auto channel = std::make_unique<
        flutter::MethodChannel<flutter::EncodableValue>>(
        registrar->messenger(), "plugins.it_nomads.com/flutter_secure_storage",
        &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<FlutterSecureStorageWindowsPlugin>();
    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto& call, auto result) {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
  }

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    const auto args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    const auto method = method_call.method_name();

    auto read_key = [&]() -> std::string {
      if (!args) return {};
      auto it = args->find(flutter::EncodableValue("key"));
      if (it == args->end()) return {};
      return std::get<std::string>(it->second);
    };

    if (method == "write") {
      if (args) {
        auto key = read_key();
        auto it = args->find(flutter::EncodableValue("value"));
        if (!key.empty() && it != args->end()) {
          store_[key] = std::get<std::string>(it->second);
        }
      }
      result->Success();
      return;
    }
    if (method == "read") {
      auto key = read_key();
      auto it = store_.find(key);
      if (it == store_.end()) {
        result->Success();
      } else {
        result->Success(flutter::EncodableValue(it->second));
      }
      return;
    }
    if (method == "readAll") {
      flutter::EncodableMap map;
      for (const auto& pair : store_) {
        map[flutter::EncodableValue(pair.first)] = flutter::EncodableValue(pair.second);
      }
      result->Success(flutter::EncodableValue(map));
      return;
    }
    if (method == "delete") {
      store_.erase(read_key());
      result->Success();
      return;
    }
    if (method == "deleteAll") {
      store_.clear();
      result->Success();
      return;
    }
    if (method == "containsKey") {
      result->Success(flutter::EncodableValue(store_.count(read_key()) > 0));
      return;
    }

    result->NotImplemented();
  }

  std::unordered_map<std::string, std::string> store_;
};

}  // namespace

void FlutterSecureStorageWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  FlutterSecureStorageWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
