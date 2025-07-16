#include "include/playmidifile/play_midifile_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>
#define NOMINMAX  // Prevent Windows min/max macros from conflicting with std::min/std::max
#include <windows.h>
#include <mmsystem.h>
#include <memory>
#include <string>

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

  HWND midi_window_;
  std::string current_state_;
  DWORD duration_ms_;
  DWORD current_position_ms_;
};

// static
void PlayMidifilePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "playmidifile",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<PlayMidifilePlugin>();

  // Note: EventChannel support is temporarily disabled due to API compatibility issues

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

PlayMidifilePlugin::PlayMidifilePlugin() 
    : midi_window_(nullptr), current_state_("stopped"), duration_ms_(0), current_position_ms_(0) {}

PlayMidifilePlugin::~PlayMidifilePlugin() {
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
    // Check current status first
    wchar_t mode_buffer[256];
    MCIERROR error = mciSendString(L"status midi mode", mode_buffer, sizeof(mode_buffer)/sizeof(wchar_t), midi_window_);
    if (error == 0) {
      std::wstring mode(mode_buffer);
      // If stopped (including after completion), seek to beginning first
      if (mode == L"stopped") {
        mciSendString(L"seek midi to start", nullptr, 0, midi_window_);
        current_position_ms_ = 0;
      }
    }
    
    error = mciSendString(L"play midi", nullptr, 0, midi_window_);
    if (error == 0) {
      current_state_ = "playing";
      result->Success();
    } else {
      // Get error message for debugging
      wchar_t error_buffer[256];
      mciGetErrorString(error, error_buffer, sizeof(error_buffer)/sizeof(wchar_t));
      std::string error_msg = "MCI Play Error: ";
      int size_needed = WideCharToMultiByte(CP_UTF8, 0, error_buffer, -1, NULL, 0, NULL, NULL);
      std::string error_str(size_needed, 0);
      WideCharToMultiByte(CP_UTF8, 0, error_buffer, -1, &error_str[0], size_needed, NULL, NULL);
      error_msg += error_str;
      result->Error("PLAY_ERROR", error_msg);
    }
  } else if (method == "pause") {
    MCIERROR error = mciSendString(L"pause midi", nullptr, 0, midi_window_);
    if (error == 0) {
      current_state_ = "paused";
      result->Success();
    } else {
      result->Error("PAUSE_ERROR", "Failed to pause");
    }
  } else if (method == "stop") {
    MCIERROR error = mciSendString(L"stop midi", nullptr, 0, midi_window_);
    if (error == 0) {
      // After stopping, seek to the beginning for next playback
      mciSendString(L"seek midi to start", nullptr, 0, midi_window_);
      current_position_ms_ = 0;
      current_state_ = "stopped";
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
        
        // Ensure position is within valid range
        position_ms = (position_ms < 0) ? 0 : ((position_ms > static_cast<int>(duration_ms_)) ? static_cast<int>(duration_ms_) : position_ms);
        
        std::wstring cmd = L"seek midi to " + std::to_wstring(position_ms);
        MCIERROR error = mciSendString(cmd.c_str(), nullptr, 0, midi_window_);
        if (error == 0) {
          current_position_ms_ = position_ms;
          result->Success();
        } else {
          // Get error message for debugging
          wchar_t error_buffer[256];
          mciGetErrorString(error, error_buffer, sizeof(error_buffer)/sizeof(wchar_t));
          std::string error_msg = "MCI Seek Error: ";
          int size_needed = WideCharToMultiByte(CP_UTF8, 0, error_buffer, -1, NULL, 0, NULL, NULL);
          std::string error_str(size_needed, 0);
          WideCharToMultiByte(CP_UTF8, 0, error_buffer, -1, &error_str[0], size_needed, NULL, NULL);
          error_msg += error_str;
          result->Error("SEEK_ERROR", error_msg);
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
    } else {
      // If failed to get position, keep the current stored value
    }
    
    // Check if playback is still active
    wchar_t mode_buffer[256];
    error = mciSendString(L"status midi mode", mode_buffer, sizeof(mode_buffer)/sizeof(wchar_t), midi_window_);
    if (error == 0) {
      std::wstring mode(mode_buffer);
      if (mode == L"stopped" && current_state_ == "playing") {
        // Playback has completed
        current_state_ = "stopped";
        current_position_ms_ = 0; // Reset position for next playback
      } else if (mode == L"playing") {
        current_state_ = "playing";
      } else if (mode == L"paused") {
        current_state_ = "paused";
      }
    }
    
    flutter::EncodableMap info;
    info[flutter::EncodableValue("currentPositionMs")] = flutter::EncodableValue(static_cast<int>(current_position_ms_));
    info[flutter::EncodableValue("durationMs")] = flutter::EncodableValue(static_cast<int>(duration_ms_));
    double progress = duration_ms_ > 0 ? static_cast<double>(current_position_ms_) / duration_ms_ : 0.0;
    // Ensure progress is within valid range
    progress = (progress < 0.0) ? 0.0 : ((progress > 1.0) ? 1.0 : progress);
    info[flutter::EncodableValue("progress")] = flutter::EncodableValue(progress);
    result->Success(flutter::EncodableValue(info));
  } else {
    result->NotImplemented();
  }
}



}  // namespace playmidifile

void PlayMidifilePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  playmidifile::PlayMidifilePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
} 