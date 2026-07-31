#include "include/flutter_secure_storage_windows/flutter_secure_storage_windows_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_secure_storage_windows_plugin.h"

void FlutterSecureStorageWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  FlutterSecureStorageWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
