#include "mytaskking_desktop_plugin.h"

#include <gdk/gdk.h>
#include <gtk/gtk.h>

#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>
#include <thread>
#include <vector>

#ifdef GDK_WINDOWING_X11
#include <X11/Xlib.h>
#include <X11/extensions/scrnsaver.h>
#endif

namespace {

constexpr int kPromptWidth = 430;
constexpr int kPromptHeight = 270;

struct PromptResult {
  bool done = false;
  bool needs_note = false;
  int remaining = 30;
  std::string note = "working";
  GtkWidget* window = nullptr;
  GtkWidget* message = nullptr;
  GtkWidget* entry = nullptr;
  GtkWidget* working_button = nullptr;
  GtkWidget* submit_button = nullptr;
  guint timer_id = 0;
};

int GetIntArg(FlValue* args, const char* key, int fallback) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr) return fallback;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    return static_cast<int>(fl_value_get_int(value));
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    return static_cast<int>(fl_value_get_float(value));
  }
  return fallback;
}

void FinishPrompt(PromptResult* state, const std::string& note) {
  if (state == nullptr || state->done) return;
  state->note = note.empty() ? "working" : note;
  state->done = true;
  if (state->timer_id != 0) {
    g_source_remove(state->timer_id);
    state->timer_id = 0;
  }
  if (state->window != nullptr) {
    gtk_widget_destroy(state->window);
    state->window = nullptr;
  }
}

gboolean PromptTimerTick(gpointer user_data) {
  auto* state = static_cast<PromptResult*>(user_data);
  if (state == nullptr || state->done) return G_SOURCE_REMOVE;
  if (state->needs_note) return G_SOURCE_CONTINUE;
  state->remaining -= 1;
  if (state->remaining <= 0) {
    state->needs_note = true;
    gtk_label_set_text(GTK_LABEL(state->message),
                       "Please type a short update before continuing work.");
    gtk_widget_show(state->entry);
    gtk_widget_hide(state->working_button);
    gtk_widget_show(state->submit_button);
    gtk_widget_grab_focus(state->entry);
    return G_SOURCE_CONTINUE;
  }
  char buffer[256];
  snprintf(buffer, sizeof(buffer),
           "Click \"I am working\" or wait %d seconds for the note box.",
           state->remaining);
  gtk_label_set_text(GTK_LABEL(state->message), buffer);
  return G_SOURCE_CONTINUE;
}

void OnWorkingClicked(GtkWidget*, gpointer user_data) {
  FinishPrompt(static_cast<PromptResult*>(user_data), "working");
}

void OnSubmitClicked(GtkWidget*, gpointer user_data) {
  auto* state = static_cast<PromptResult*>(user_data);
  if (state == nullptr) return;
  const char* text = gtk_entry_get_text(GTK_ENTRY(state->entry));
  FinishPrompt(state, text == nullptr ? "working" : text);
}

gboolean OnPromptDelete(GtkWidget*, GdkEvent*, gpointer user_data) {
  // Keep visible until the user responds.
  (void)user_data;
  return TRUE;
}

std::string ShowWorkActivityPrompt(int seconds) {
  PromptResult state;
  state.remaining = seconds <= 0 ? 30 : seconds;

  state.window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(GTK_WINDOW(state.window), "MyTaskKing Work Check");
  gtk_window_set_default_size(GTK_WINDOW(state.window), kPromptWidth,
                              kPromptHeight);
  gtk_window_set_position(GTK_WINDOW(state.window), GTK_WIN_POS_CENTER);
  gtk_window_set_keep_above(GTK_WINDOW(state.window), TRUE);
  gtk_window_set_modal(GTK_WINDOW(state.window), TRUE);
  g_signal_connect(state.window, "delete-event", G_CALLBACK(OnPromptDelete),
                   &state);

  GtkWidget* box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  gtk_container_set_border_width(GTK_CONTAINER(box), 16);
  gtk_container_add(GTK_CONTAINER(state.window), box);

  GtkWidget* title = gtk_label_new("Are you working?");
  gtk_widget_set_halign(title, GTK_ALIGN_START);
  gtk_box_pack_start(GTK_BOX(box), title, FALSE, FALSE, 0);

  state.message = gtk_label_new(
      "Click \"I am working\" or wait for the note box.");
  gtk_label_set_line_wrap(GTK_LABEL(state.message), TRUE);
  gtk_widget_set_halign(state.message, GTK_ALIGN_START);
  gtk_box_pack_start(GTK_BOX(box), state.message, FALSE, FALSE, 0);

  state.entry = gtk_entry_new();
  gtk_entry_set_placeholder_text(GTK_ENTRY(state.entry),
                                 "What are you working on?");
  gtk_widget_hide(state.entry);
  gtk_box_pack_start(GTK_BOX(box), state.entry, FALSE, FALSE, 0);

  GtkWidget* buttons = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
  gtk_widget_set_halign(buttons, GTK_ALIGN_END);
  gtk_box_pack_end(GTK_BOX(box), buttons, FALSE, FALSE, 0);

  state.working_button = gtk_button_new_with_label("I am working");
  state.submit_button = gtk_button_new_with_label("Submit update");
  gtk_widget_hide(state.submit_button);
  g_signal_connect(state.working_button, "clicked", G_CALLBACK(OnWorkingClicked),
                   &state);
  g_signal_connect(state.submit_button, "clicked", G_CALLBACK(OnSubmitClicked),
                   &state);
  gtk_box_pack_start(GTK_BOX(buttons), state.working_button, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(buttons), state.submit_button, FALSE, FALSE, 0);

  state.timer_id = g_timeout_add_seconds(1, PromptTimerTick, &state);
  gtk_widget_show_all(state.window);
  gtk_window_present(GTK_WINDOW(state.window));

  while (!state.done) {
    while (gtk_events_pending()) {
      gtk_main_iteration();
    }
    g_usleep(10000);
  }

  return state.note;
}

guint32 GetSystemIdleSeconds() {
#ifdef GDK_WINDOWING_X11
  Display* display = XOpenDisplay(nullptr);
  if (display == nullptr) return 0;
  int event_base = 0;
  int error_base = 0;
  if (!XScreenSaverQueryExtension(display, &event_base, &error_base)) {
    XCloseDisplay(display);
    return 0;
  }
  XScreenSaverInfo* info = XScreenSaverAllocInfo();
  if (info == nullptr) {
    XCloseDisplay(display);
    return 0;
  }
  Window root = DefaultRootWindow(display);
  if (!XScreenSaverQueryInfo(display, root, info)) {
    XFree(info);
    XCloseDisplay(display);
    return 0;
  }
  const guint32 idle_ms = info->idle;
  XFree(info);
  XCloseDisplay(display);
  return idle_ms / 1000;
#else
  return 0;
#endif
}

bool SaveRootWindowPng(const std::string& path, int max_width) {
  GdkWindow* root = gdk_get_default_root_window();
  if (root == nullptr) return false;

  gint width = 0;
  gint height = 0;
  gdk_window_get_geometry(root, nullptr, nullptr, &width, &height);
  if (width <= 0 || height <= 0) return false;

  g_autoptr(GdkPixbuf) pixbuf =
      gdk_pixbuf_get_from_window(root, 0, 0, width, height);
  if (pixbuf == nullptr) return false;

  if (max_width > 0 && gdk_pixbuf_get_width(pixbuf) > max_width) {
    const double scale =
        static_cast<double>(max_width) / gdk_pixbuf_get_width(pixbuf);
    const int target_h =
        static_cast<int>(gdk_pixbuf_get_height(pixbuf) * scale);
    g_autoptr(GdkPixbuf) scaled = gdk_pixbuf_scale_simple(
        pixbuf, max_width, target_h, GDK_INTERP_BILINEAR);
    if (scaled == nullptr) return false;
    return gdk_pixbuf_save(scaled, path.c_str(), "png", nullptr, nullptr);
  }

  return gdk_pixbuf_save(pixbuf, path.c_str(), "png", nullptr, nullptr);
}

std::vector<std::string> CaptureFrames(int frame_count,
                                       int delay_ms,
                                       int max_width) {
  frame_count = frame_count <= 0 ? 1 : std::min(frame_count, 12);
  delay_ms = std::max(0, delay_ms);
  max_width = max_width <= 0 ? 1280 : max_width;

  char temp_dir[] = "/tmp/mytaskking-capture-XXXXXX";
  if (mkdtemp(temp_dir) == nullptr) return {};

  std::vector<std::string> paths;
  for (int i = 0; i < frame_count; ++i) {
    char frame_path[512];
    snprintf(frame_path, sizeof(frame_path), "%s/frame-%02d.png", temp_dir, i);
    if (SaveRootWindowPng(frame_path, max_width)) {
      paths.emplace_back(frame_path);
    }
    if (i < frame_count - 1 && delay_ms > 0) {
      std::this_thread::sleep_for(std::chrono::milliseconds(delay_ms));
    }
  }
  return paths;
}

void HandleMethodCall(FlMethodCall* method_call, gpointer user_data) {
  (void)user_data;
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (strcmp(method, "showWorkActivityPrompt") == 0) {
    const int seconds = GetIntArg(args, "seconds", 30);
    const std::string response = ShowWorkActivityPrompt(seconds);
    g_autoptr(FlValue) result = fl_value_new_string(response.c_str());
    fl_method_call_respond_success(method_call, result, nullptr);
    return;
  }

  if (strcmp(method, "captureFrames") == 0) {
    const int frame_count = GetIntArg(args, "frameCount", 1);
    const int delay_ms = GetIntArg(args, "delayMs", 0);
    const int max_width = GetIntArg(args, "maxWidth", 1280);
    const auto paths = CaptureFrames(frame_count, delay_ms, max_width);
    g_autoptr(FlValue) list = fl_value_new_list();
    for (const auto& path : paths) {
      fl_value_append_take(list, fl_value_new_string(path.c_str()));
    }
    fl_method_call_respond_success(method_call, list, nullptr);
    return;
  }

  if (strcmp(method, "getIdleSeconds") == 0) {
    g_autoptr(FlValue) result =
        fl_value_new_int(static_cast<int64_t>(GetSystemIdleSeconds()));
    fl_method_call_respond_success(method_call, result, nullptr);
    return;
  }

  fl_method_call_respond_not_implemented(method_call, nullptr);
}

}  // namespace

void RegisterMytaskkingDesktopPlugin(FlView* view) {
  FlEngine* engine = fl_view_get_engine(view);
  if (engine == nullptr) return;

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), "mytaskking/desktop",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, HandleMethodCall, nullptr,
                                          nullptr);
}
