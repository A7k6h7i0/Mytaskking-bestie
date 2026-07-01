#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter_plugin_registrar.h>

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <system_error>

namespace {

namespace fs = std::filesystem;

fs::path StorageDir() {
  char* app_data = nullptr;
  size_t app_data_len = 0;
  _dupenv_s(&app_data, &app_data_len, "APPDATA");
  fs::path base = app_data && *app_data ? fs::path(app_data) : fs::temp_directory_path();
  if (app_data) {
    free(app_data);
  }
  return base / "MyTaskKing" / "secure_storage";
}

std::string SafeKey(std::string key) {
  std::replace_if(key.begin(), key.end(), [](unsigned char ch) {
    return !(std::isalnum(ch) || ch == '.' || ch == '_' || ch == '-');
  }, '_');
  return key;
}

fs::path KeyPath(const std::string& key) {
  return StorageDir() / SafeKey(key);
}

std::optional<std::string> ReadFile(const fs::path& path) {
  std::ifstream input(path, std::ios::binary);
  if (!input) return std::nullopt;
  std::ostringstream buffer;
  buffer << input.rdbuf();
  return buffer.str();
}

void WriteFile(const fs::path& path, const std::string& value) {
  std::error_code ec;
  fs::create_directories(path.parent_path(), ec);
  std::ofstream output(path, std::ios::binary | std::ios::trunc);
  output << value;
}

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
          WriteFile(KeyPath(key), std::get<std::string>(it->second));
        }
      }
      result->Success();
      return;
    }
    if (method == "read") {
      auto key = read_key();
      auto value = key.empty() ? std::optional<std::string>() : ReadFile(KeyPath(key));
      if (!value.has_value()) {
        result->Success();
      } else {
        result->Success(flutter::EncodableValue(value.value()));
      }
      return;
    }
    if (method == "readAll") {
      flutter::EncodableMap map;
      std::error_code ec;
      const auto dir = StorageDir();
      if (fs::exists(dir, ec)) {
        for (const auto& entry : fs::directory_iterator(dir, ec)) {
          if (!entry.is_regular_file()) continue;
          auto value = ReadFile(entry.path());
          if (value.has_value()) {
            map[flutter::EncodableValue(entry.path().filename().string())] =
                flutter::EncodableValue(value.value());
          }
        }
      }
      result->Success(flutter::EncodableValue(map));
      return;
    }
    if (method == "delete") {
      std::error_code ec;
      const auto key = read_key();
      if (!key.empty()) fs::remove(KeyPath(key), ec);
      result->Success();
      return;
    }
    if (method == "deleteAll") {
      std::error_code ec;
      fs::remove_all(StorageDir(), ec);
      result->Success();
      return;
    }
    if (method == "containsKey") {
      std::error_code ec;
      const auto key = read_key();
      result->Success(flutter::EncodableValue(
          !key.empty() && fs::exists(KeyPath(key), ec)));
      return;
    }

    result->NotImplemented();
  }
};

}  // namespace

extern "C" __declspec(dllexport) void FlutterSecureStorageWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  FlutterSecureStorageWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
