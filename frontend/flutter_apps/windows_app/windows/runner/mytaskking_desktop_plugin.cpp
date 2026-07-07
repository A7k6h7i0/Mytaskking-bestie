#include "mytaskking_desktop_plugin.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>

// GDI+ SDK headers still use min/max in a few inline helpers. The runner
// globally defines NOMINMAX, so provide the legacy macros only while including
// GDI+ and remove them immediately after.
#ifndef min
#define min(a, b) (((a) < (b)) ? (a) : (b))
#endif
#ifndef max
#define max(a, b) (((a) > (b)) ? (a) : (b))
#endif
#pragma warning(push)
#pragma warning(disable : 4458)
#include <gdiplus.h>
#pragma warning(pop)
#undef min
#undef max

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr int kPromptWidth = 430;
constexpr int kPromptHeight = 270;
constexpr int kTimerId = 1001;
constexpr int kWorkingButtonId = 2001;
constexpr int kSubmitButtonId = 2002;

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;

std::wstring Utf16FromUtf8(const std::string& value) {
  if (value.empty()) return L"";
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                       static_cast<int>(value.size()), nullptr,
                                       0);
  std::wstring output(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), output.data(), size);
  return output;
}

std::string Utf8FromUtf16(const std::wstring& value) {
  if (value.empty()) return "";
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                       static_cast<int>(value.size()), nullptr,
                                       0, nullptr, nullptr);
  std::string output(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), output.data(), size,
                      nullptr, nullptr);
  return output;
}

int GetIntArg(const flutter::EncodableMap* args,
              const std::string& key,
              int fallback) {
  if (!args) return fallback;
  const auto found = args->find(flutter::EncodableValue(key));
  if (found == args->end()) return fallback;
  if (const auto value = std::get_if<int32_t>(&found->second)) return *value;
  if (const auto value = std::get_if<int64_t>(&found->second)) {
    return static_cast<int>(*value);
  }
  if (const auto value = std::get_if<double>(&found->second)) {
    return static_cast<int>(*value);
  }
  return fallback;
}

struct PromptState {
  int remaining = 30;
  bool needs_note = false;
  bool done = false;
  std::wstring result;
  HWND hwnd = nullptr;
  HWND title = nullptr;
  HWND message = nullptr;
  HWND edit = nullptr;
  HWND working_button = nullptr;
  HWND submit_button = nullptr;
};

void SetControlFont(HWND control, HFONT font) {
  SendMessage(control, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
}

void UpdatePromptMessage(PromptState* state) {
  if (!state) return;
  if (state->needs_note) {
    SetWindowTextW(state->title, L"What are you working on?");
    SetWindowTextW(state->message,
                   L"Please type a short update before continuing work.");
    ShowWindow(state->edit, SW_SHOW);
    ShowWindow(state->working_button, SW_HIDE);
    ShowWindow(state->submit_button, SW_SHOW);
    SetFocus(state->edit);
    return;
  }
  std::wstringstream text;
  text << L"Click anywhere in this window or press I am working.\r\n"
       << L"Message box opens in " << state->remaining << L" seconds.";
  SetWindowTextW(state->message, text.str().c_str());
}

void FinishPrompt(PromptState* state, const std::wstring& note) {
  if (!state || state->done) return;
  state->result = note.empty() ? L"working" : note;
  state->done = true;
  KillTimer(state->hwnd, kTimerId);
  DestroyWindow(state->hwnd);
}

std::wstring ReadEditText(HWND edit) {
  const int length = GetWindowTextLengthW(edit);
  std::wstring text(length, L'\0');
  if (length > 0) {
    GetWindowTextW(edit, text.data(), length + 1);
  }
  return text;
}

LRESULT CALLBACK PromptWndProc(HWND hwnd,
                               UINT message,
                               WPARAM wparam,
                               LPARAM lparam) {
  auto* state = reinterpret_cast<PromptState*>(
      GetWindowLongPtr(hwnd, GWLP_USERDATA));
  switch (message) {
    case WM_NCCREATE: {
      auto* create = reinterpret_cast<CREATESTRUCT*>(lparam);
      state = reinterpret_cast<PromptState*>(create->lpCreateParams);
      state->hwnd = hwnd;
      SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
      return TRUE;
    }
    case WM_TIMER:
      if (state && !state->needs_note && state->remaining > 0) {
        state->remaining -= 1;
        if (state->remaining <= 0) {
          state->needs_note = true;
        }
        UpdatePromptMessage(state);
      }
      return 0;
    case WM_LBUTTONDOWN:
      if (state && !state->needs_note) {
        FinishPrompt(state, L"working");
      }
      return 0;
    case WM_COMMAND:
      if (state && LOWORD(wparam) == kWorkingButtonId) {
        FinishPrompt(state, L"working");
        return 0;
      }
      if (state && LOWORD(wparam) == kSubmitButtonId) {
        FinishPrompt(state, ReadEditText(state->edit));
        return 0;
      }
      break;
    case WM_CLOSE:
      // Keep the prompt visible until the user confirms or submits an update.
      return 0;
    case WM_DESTROY:
      if (state) state->done = true;
      return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

DWORD GetSystemIdleSeconds() {
  LASTINPUTINFO info = {};
  info.cbSize = sizeof(LASTINPUTINFO);
  if (!GetLastInputInfo(&info)) {
    return 0;
  }
  const DWORD now = GetTickCount();
  return (now - info.dwTime) / 1000;
}

std::optional<std::string> ShowWorkActivityPrompt(int seconds) {
  const wchar_t* class_name = L"MyTaskKingActivityPromptWindow";
  static bool registered = false;
  if (!registered) {
    WNDCLASSW wc = {};
    wc.lpfnWndProc = PromptWndProc;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.lpszClassName = class_name;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = CreateSolidBrush(RGB(248, 250, 255));
    RegisterClassW(&wc);
    registered = true;
  }

  PromptState state;
  state.remaining = seconds <= 0 ? 30 : seconds;

  const int screen_w = GetSystemMetrics(SM_CXSCREEN);
  const int screen_h = GetSystemMetrics(SM_CYSCREEN);
  const int x = (screen_w - kPromptWidth) / 2;
  const int y = (screen_h - kPromptHeight) / 2;

  HWND hwnd = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW, class_name,
      L"MyTaskKing Work Check", WS_POPUP | WS_CAPTION | WS_SYSMENU, x, y,
      kPromptWidth, kPromptHeight, nullptr, nullptr, GetModuleHandle(nullptr),
      &state);
  if (!hwnd) return std::nullopt;

  HFONT font = reinterpret_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
  state.title = CreateWindowW(L"STATIC", L"Are you working?",
                              WS_CHILD | WS_VISIBLE, 24, 24, 360, 28, hwnd,
                              nullptr, nullptr, nullptr);
  state.message = CreateWindowW(L"STATIC", L"", WS_CHILD | WS_VISIBLE, 24, 64,
                                370, 60, hwnd, nullptr, nullptr, nullptr);
  state.edit = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
                               WS_CHILD | ES_MULTILINE | ES_AUTOVSCROLL |
                                   WS_VSCROLL,
                               24, 126, 370, 64, hwnd, nullptr, nullptr,
                               nullptr);
  state.working_button =
      CreateWindowW(L"BUTTON", L"I am working", WS_CHILD | WS_VISIBLE, 238,
                    190, 156, 36, hwnd,
                    reinterpret_cast<HMENU>(static_cast<intptr_t>(
                        kWorkingButtonId)),
                    nullptr,
                    nullptr);
  state.submit_button =
      CreateWindowW(L"BUTTON", L"Submit update", WS_CHILD, 238, 190, 156, 36,
                    hwnd,
                    reinterpret_cast<HMENU>(static_cast<intptr_t>(
                        kSubmitButtonId)),
                    nullptr,
                    nullptr);

  SetControlFont(state.title, font);
  SetControlFont(state.message, font);
  SetControlFont(state.edit, font);
  SetControlFont(state.working_button, font);
  SetControlFont(state.submit_button, font);
  UpdatePromptMessage(&state);

  SetTimer(hwnd, kTimerId, 1000, nullptr);
  ShowWindow(hwnd, SW_SHOWNORMAL);
  SetWindowPos(hwnd, HWND_TOPMOST, x, y, kPromptWidth, kPromptHeight,
               SWP_SHOWWINDOW);
  SetForegroundWindow(hwnd);

  MSG msg;
  while (!state.done && GetMessage(&msg, nullptr, 0, 0) > 0) {
    if (!IsDialogMessage(hwnd, &msg)) {
      TranslateMessage(&msg);
      DispatchMessage(&msg);
    }
  }
  return Utf8FromUtf16(state.result.empty() ? L"working" : state.result);
}

int GetEncoderClsid(const WCHAR* format, CLSID* clsid) {
  UINT count = 0;
  UINT size = 0;
  Gdiplus::GetImageEncodersSize(&count, &size);
  if (size == 0) return -1;

  std::vector<BYTE> buffer(size);
  auto* info = reinterpret_cast<Gdiplus::ImageCodecInfo*>(buffer.data());
  Gdiplus::GetImageEncoders(count, size, info);
  for (UINT i = 0; i < count; ++i) {
    if (wcscmp(info[i].MimeType, format) == 0) {
      *clsid = info[i].Clsid;
      return static_cast<int>(i);
    }
  }
  return -1;
}

bool SaveScreenPng(const std::wstring& path, int max_width) {
  const int x = GetSystemMetrics(SM_XVIRTUALSCREEN);
  const int y = GetSystemMetrics(SM_YVIRTUALSCREEN);
  const int width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  const int height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
  if (width <= 0 || height <= 0) return false;

  HDC screen_dc = GetDC(nullptr);
  HDC mem_dc = CreateCompatibleDC(screen_dc);
  HBITMAP bitmap = CreateCompatibleBitmap(screen_dc, width, height);
  HGDIOBJ old = SelectObject(mem_dc, bitmap);
  const BOOL copied =
      BitBlt(mem_dc, 0, 0, width, height, screen_dc, x, y, SRCCOPY | CAPTUREBLT);
  SelectObject(mem_dc, old);
  DeleteDC(mem_dc);
  ReleaseDC(nullptr, screen_dc);
  if (!copied) {
    DeleteObject(bitmap);
    return false;
  }

  Gdiplus::Bitmap source(bitmap, nullptr);
  CLSID png_clsid;
  if (GetEncoderClsid(L"image/png", &png_clsid) < 0) {
    DeleteObject(bitmap);
    return false;
  }

  Gdiplus::Status status = Gdiplus::Ok;
  if (max_width > 0 && width > max_width) {
    const double scale = static_cast<double>(max_width) / width;
    const int target_h = static_cast<int>(height * scale);
    Gdiplus::Bitmap scaled(max_width, target_h, PixelFormat32bppARGB);
    Gdiplus::Graphics graphics(&scaled);
    graphics.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
    graphics.DrawImage(&source, 0, 0, max_width, target_h);
    status = scaled.Save(path.c_str(), &png_clsid, nullptr);
  } else {
    status = source.Save(path.c_str(), &png_clsid, nullptr);
  }
  DeleteObject(bitmap);
  return status == Gdiplus::Ok;
}

std::vector<std::string> CaptureFrames(int frame_count,
                                       int delay_ms,
                                       int max_width) {
  frame_count = frame_count <= 0 ? 1 : std::min(frame_count, 12);
  delay_ms = std::max(0, delay_ms);
  max_width = max_width <= 0 ? 1280 : max_width;

  wchar_t temp_path[MAX_PATH];
  GetTempPathW(MAX_PATH, temp_path);
  std::wstring dir = std::wstring(temp_path) + L"MyTaskKingCapture-" +
                     std::to_wstring(GetTickCount64());
  CreateDirectoryW(dir.c_str(), nullptr);

  Gdiplus::GdiplusStartupInput startup_input;
  ULONG_PTR gdiplus_token = 0;
  Gdiplus::GdiplusStartup(&gdiplus_token, &startup_input, nullptr);

  std::vector<std::string> paths;
  for (int i = 0; i < frame_count; ++i) {
    wchar_t frame_path[MAX_PATH];
    swprintf_s(frame_path, L"%s\\frame-%02d.png", dir.c_str(), i);
    if (SaveScreenPng(frame_path, max_width)) {
      paths.push_back(Utf8FromUtf16(frame_path));
    }
    if (i < frame_count - 1 && delay_ms > 0) {
      std::this_thread::sleep_for(std::chrono::milliseconds(delay_ms));
    }
  }

  Gdiplus::GdiplusShutdown(gdiplus_token);
  return paths;
}

}  // namespace

void RegisterMytaskkingDesktopPlugin(flutter::FlutterEngine* engine) {
  g_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine->messenger(), "mytaskking/desktop",
      &flutter::StandardMethodCodec::GetInstance());

  g_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (call.method_name() == "showWorkActivityPrompt") {
          const int seconds = GetIntArg(args, "seconds", 30);
          const auto response = ShowWorkActivityPrompt(seconds);
          if (!response.has_value()) {
            result->Success();
            return;
          }
          result->Success(flutter::EncodableValue(response.value()));
          return;
        }
        if (call.method_name() == "captureFrames") {
          const int frame_count = GetIntArg(args, "frameCount", 1);
          const int delay_ms = GetIntArg(args, "delayMs", 0);
          const int max_width = GetIntArg(args, "maxWidth", 1280);
          const auto paths = CaptureFrames(frame_count, delay_ms, max_width);
          flutter::EncodableList list;
          for (const auto& path : paths) {
            list.emplace_back(path);
          }
          result->Success(flutter::EncodableValue(list));
          return;
        }
        if (call.method_name() == "getIdleSeconds") {
          result->Success(
              flutter::EncodableValue(static_cast<int32_t>(GetSystemIdleSeconds())));
          return;
        }
        result->NotImplemented();
      });
}
