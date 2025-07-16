#include "include/playmidifile/play_midifile_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>
#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>
#include <windows.h>
#include <mmsystem.h>
#include <memory>
#include <string>
#include <thread>
#include <chrono>

#pragma comment(lib, "winmm.lib")

namespace playmidifile {

class PlayMidifilePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  PlayMidifilePlugin();

  virtual ~PlayMidifilePlugin();

  // Disallow copy and assign.
  PlayMidifilePlugin(const PlayMidifilePlugin&) = delete;
  PlayMidifilePlugin& operator=(const PlayMidifilePlugin&) = delete;

 private:
  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Event channel handlers
  void StartProgressUpdates();
  void StopProgressUpdates();
  void UpdateProgress();
  void UpdateState(const std::string& new_state);

  HWND midi_window_;
  std::string current_state_;
  DWORD duration_ms_;
  DWORD current_position_ms_;
  
  // Event channels
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> progress_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> state_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> progress_sink_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> state_sink_;
  
  // Progress timer
  std::thread progress_thread_;
  bool progress_running_;
};

// static
void PlayMidifilePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "playmidifile",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<PlayMidifilePlugin>();

  // Register event channels
  plugin->progress_channel_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      registrar->messenger(), "playmidifile/progress",
      &flutter::StandardMethodCodec::GetInstance());
  plugin->state_channel_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      registrar->messenger(), "playmidifile/state",
      &flutter::StandardMethodCodec::GetInstance());

  // Set event channel handlers
  auto progress_handler = std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [plugin_pointer = plugin.get()](const flutter::EncodableValue* arguments,
                                      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
          -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        plugin_pointer->progress_sink_ = std::move(events);
        return nullptr;
      },
      [plugin_pointer = plugin.get()](const flutter::EncodableValue* arguments)
          -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        plugin_pointer->progress_sink_ = nullptr;
        return nullptr;
      });

  auto state_handler = std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [plugin_pointer = plugin.get()](const flutter::EncodableValue* arguments,
                                      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
          -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        plugin_pointer->state_sink_ = std::move(events);
        return nullptr;
      },
      [plugin_pointer = plugin.get()](const flutter::EncodableValue* arguments)
          -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        plugin_pointer->state_sink_ = nullptr;
        return nullptr;
      });

  plugin->progress_channel_->SetStreamHandler(std::move(progress_handler));
  plugin->state_channel_->SetStreamHandler(std::move(state_handler));

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

PlayMidifilePlugin::PlayMidifilePlugin() 
    : midi_window_(nullptr), current_state_("stopped"), duration_ms_(0), current_position_ms_(0), progress_running_(false) {}

PlayMidifilePlugin::~PlayMidifilePlugin() {
  StopProgressUpdates();
  if (midi_window_) {
    mciSendString(L"close midi", nullptr, 0, midi_window_);
    DestroyWindow(midi_window_);
  }
}

void PlayMidifilePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();

  if (method == "initialize") {
    // Create hidden window for MIDI operations
    WNDCLASS wc = {};
    wc.lpfnWndProc = DefWindowProc;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.lpszClassName = L"MidiPlayerWindow";
    RegisterClass(&wc);
    
    midi_window_ = CreateWindow(L"MidiPlayerWindow", L"MIDI Player", 0, 0, 0, 0, 0, 
                               HWND_MESSAGE, nullptr, GetModuleHandle(nullptr), nullptr);
    
    if (midi_window_) {
      result->Success();
    } else {
      result->Error("INIT_ERROR", "Failed to initialize");
    }
  } else if (method == "loadFile") {
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args) {
      auto it = args->find(flutter::EncodableValue("filePath"));
      if (it != args->end()) {
        std::string file_path = std::get<std::string>(it->second);
        std::wstring wide_path(file_path.begin(), file_path.end());
        
        // Check if file exists
        DWORD attr = GetFileAttributes(wide_path.c_str());
        if (attr == INVALID_FILE_ATTRIBUTES) {
          result->Error("FILE_NOT_FOUND", "File not found");
          return;
        }
        
                 // Open MIDI file
         std::wstring cmd = L"open \"" + wide_path + L"\" type sequencer alias midi";
         MCIERROR error = mciSendString(cmd.c_str(), nullptr, 0, midi_window_);
         
         if (error == 0) {
           // Get duration
           wchar_t buffer[256];
           error = mciSendString(L"status midi length", buffer, sizeof(buffer)/sizeof(wchar_t), midi_window_);
           if (error == 0) {
             duration_ms_ = _wtoi(buffer);
           }
           current_state_ = "stopped";
           UpdateState(current_state_);
           result->Success(flutter::EncodableValue(true));
         } else {
           // Get error message
           wchar_t error_buffer[256];
           mciGetErrorString(error, error_buffer, sizeof(error_buffer)/sizeof(wchar_t));
           std::string error_msg = "MCI Error: ";
           int size_needed = WideCharToMultiByte(CP_UTF8, 0, error_buffer, -1, NULL, 0, NULL, NULL);
           std::string error_str(size_needed, 0);
           WideCharToMultiByte(CP_UTF8, 0, error_buffer, -1, &error_str[0], size_needed, NULL, NULL);
           error_msg += error_str + " Path: " + file_path;
           result->Error("LOAD_ERROR", error_msg);
         }
      } else {
        result->Error("INVALID_ARGUMENT", "File path required");
      }
    } else {
      result->Error("INVALID_ARGUMENT", "Arguments required");
    }
     } else if (method == "loadAsset") {
     const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
     if (args) {
       auto it = args->find(flutter::EncodableValue("assetPath"));
       if (it != args->end()) {
         std::string asset_path = std::get<std::string>(it->second);
         
         // Get executable directory
         char exe_path[MAX_PATH];
         GetModuleFileNameA(nullptr, exe_path, MAX_PATH);
         std::string exe_dir = exe_path;
         size_t pos = exe_dir.find_last_of("\\/");
         if (pos != std::string::npos) {
           exe_dir = exe_dir.substr(0, pos);
         }
         
         // Flutter Windows assets are in data/flutter_assets/ directory
         std::string full_path = exe_dir + "\\data\\flutter_assets\\" + asset_path;
         std::wstring wide_path(full_path.begin(), full_path.end());
        
        // Check if file exists
        DWORD attr = GetFileAttributes(wide_path.c_str());
        if (attr == INVALID_FILE_ATTRIBUTES) {
          result->Error("FILE_NOT_FOUND", "Asset file not found");
          return;
        }
        
                 // Open MIDI file
         std::wstring cmd = L"open \"" + wide_path + L"\" type sequencer alias midi";
         MCIERROR error = mciSendString(cmd.c_str(), nullptr, 0, midi_window_);
         
         if (error == 0) {
           // Get duration
           wchar_t buffer[256];
           error = mciSendString(L"status midi length", buffer, sizeof(buffer)/sizeof(wchar_t), midi_window_);
           if (error == 0) {
             duration_ms_ = _wtoi(buffer);
           }
           current_state_ = "stopped";
           UpdateState(current_state_);
           result->Success(flutter::EncodableValue(true));
         } else {
           // Get error message
           wchar_t error_buffer[256];
           mciGetErrorString(error, error_buffer, sizeof(error_buffer)/sizeof(wchar_t));
           std::string error_msg = "MCI Error: ";
           int size_needed = WideCharToMultiByte(CP_UTF8, 0, error_buffer, -1, NULL, 0, NULL, NULL);
           std::string error_str(size_needed, 0);
           WideCharToMultiByte(CP_UTF8, 0, error_buffer, -1, &error_str[0], size_needed, NULL, NULL);
           error_msg += error_str + " Path: " + full_path;
           result->Error("LOAD_ERROR", error_msg);
         }
      } else {
        result->Error("INVALID_ARGUMENT", "Asset path required");
      }
    } else {
      result->Error("INVALID_ARGUMENT", "Arguments required");
    }
  } else if (method == "play") {
    MCIERROR error = mciSendString(L"play midi", nullptr, 0, midi_window_);
    if (error == 0) {
      current_state_ = "playing";
      UpdateState(current_state_);
      StartProgressUpdates();
      result->Success();
    } else {
      result->Error("PLAY_ERROR", "Failed to play");
    }
  } else if (method == "pause") {
    MCIERROR error = mciSendString(L"pause midi", nullptr, 0, midi_window_);
    if (error == 0) {
      current_state_ = "paused";
      UpdateState(current_state_);
      StopProgressUpdates();
      result->Success();
    } else {
      result->Error("PAUSE_ERROR", "Failed to pause");
    }
  } else if (method == "stop") {
    MCIERROR error = mciSendString(L"stop midi", nullptr, 0, midi_window_);
    if (error == 0) {
      current_position_ms_ = 0;
      current_state_ = "stopped";
      UpdateState(current_state_);
      StopProgressUpdates();
      result->Success();
    } else {
      result->Error("STOP_ERROR", "Failed to stop");
    }
  } else if (method == "seekTo") {
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args) {
      auto it = args->find(flutter::EncodableValue("positionMs"));
      if (it != args->end()) {
        int position_ms = std::get<int>(it->second);
        std::wstring cmd = L"seek midi to " + std::to_wstring(position_ms);
        MCIERROR error = mciSendString(cmd.c_str(), nullptr, 0, midi_window_);
        if (error == 0) {
          current_position_ms_ = position_ms;
          result->Success();
        } else {
          result->Error("SEEK_ERROR", "Failed to seek");
        }
      } else {
        result->Error("INVALID_ARGUMENT", "Position required");
      }
    } else {
      result->Error("INVALID_ARGUMENT", "Arguments required");
    }
  } else if (method == "setVolume") {
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args) {
      auto it = args->find(flutter::EncodableValue("volume"));
      if (it != args->end()) {
        double volume = std::get<double>(it->second);
        int vol = static_cast<int>(volume * 1000);
        std::wstring cmd = L"setaudio midi volume to " + std::to_wstring(vol);
        mciSendString(cmd.c_str(), nullptr, 0, midi_window_);
        result->Success();
      } else {
        result->Error("INVALID_ARGUMENT", "Volume required");
      }
    } else {
      result->Error("INVALID_ARGUMENT", "Arguments required");
    }
  } else if (method == "setSpeed") {
    // Windows MIDI API does not support speed control
    result->Success();
  } else if (method == "getCurrentInfo") {
    // Get current position
    wchar_t buffer[256];
    MCIERROR error = mciSendString(L"status midi position", buffer, sizeof(buffer)/sizeof(wchar_t), midi_window_);
    if (error == 0) {
      current_position_ms_ = _wtoi(buffer);
    }
    
    flutter::EncodableMap info;
    info[flutter::EncodableValue("currentPositionMs")] = flutter::EncodableValue(static_cast<int>(current_position_ms_));
    info[flutter::EncodableValue("durationMs")] = flutter::EncodableValue(static_cast<int>(duration_ms_));
    double progress = duration_ms_ > 0 ? static_cast<double>(current_position_ms_) / duration_ms_ : 0.0;
    info[flutter::EncodableValue("progress")] = flutter::EncodableValue(progress);
    result->Success(flutter::EncodableValue(info));
  } else {
    result->NotImplemented();
  }
}

void PlayMidifilePlugin::StartProgressUpdates() {
  StopProgressUpdates(); // 确保没有重复的线程
  progress_running_ = true;
  progress_thread_ = std::thread([this]() {
    while (progress_running_) {
      UpdateProgress();
      std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }
  });
}

void PlayMidifilePlugin::StopProgressUpdates() {
  progress_running_ = false;
  if (progress_thread_.joinable()) {
    progress_thread_.join();
  }
}

void PlayMidifilePlugin::UpdateProgress() {
  if (current_state_ != "playing") return;
  
  // Get current position
  wchar_t buffer[256];
  MCIERROR error = mciSendString(L"status midi position", buffer, sizeof(buffer)/sizeof(wchar_t), midi_window_);
  if (error == 0) {
    current_position_ms_ = _wtoi(buffer);
  }
  
  double progress = duration_ms_ > 0 ? static_cast<double>(current_position_ms_) / duration_ms_ : 0.0;
  
  // 发送进度信息
  if (progress_sink_) {
    flutter::EncodableMap info;
    info[flutter::EncodableValue("currentPositionMs")] = flutter::EncodableValue(static_cast<int>(current_position_ms_));
    info[flutter::EncodableValue("durationMs")] = flutter::EncodableValue(static_cast<int>(duration_ms_));
    info[flutter::EncodableValue("progress")] = flutter::EncodableValue(progress);
    progress_sink_->Success(flutter::EncodableValue(info));
  }
  
  // 检查播放是否完成
  if (current_state_ == "playing" && current_position_ms_ >= duration_ms_ && duration_ms_ > 0 && progress >= 0.99) {
    // 播放完成，重置状态和位置
    mciSendString(L"stop midi", nullptr, 0, midi_window_);
    current_position_ms_ = 0;
    current_state_ = "stopped";
    UpdateState(current_state_);
    StopProgressUpdates();
  }
}

void PlayMidifilePlugin::UpdateState(const std::string& new_state) {
  if (state_sink_) {
    state_sink_->Success(flutter::EncodableValue(new_state));
  }
}

}  // namespace playmidifile

void PlayMidifilePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  playmidifile::PlayMidifilePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
} 