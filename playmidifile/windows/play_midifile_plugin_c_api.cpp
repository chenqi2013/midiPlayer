#include "include/playmidifile/play_midifile_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>
#include <windows.h>
#include <mmsystem.h>
#include <thread>
#include <chrono>
#include <map>
#include <string>

#pragma comment(lib, "winmm.lib")

namespace playmidifile {

class PlayMidifilePluginCApi {
private:
    flutter::PluginRegistrarWindows* registrar_;
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
    std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> progress_channel_;
    std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> state_channel_;
    
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> progress_event_sink_;
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> state_event_sink_;
    
    HWND midi_window_;
    UINT device_id_;
    std::string current_state_;
    DWORD duration_ms_;
    DWORD current_position_ms_;
    std::thread progress_thread_;
    bool is_progress_thread_running_;
    
public:
    static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
        auto plugin = std::make_unique<PlayMidifilePluginCApi>(registrar);
        
        registrar->AddPlugin(std::move(plugin));
    }
    
    PlayMidifilePluginCApi(flutter::PluginRegistrarWindows* registrar)
        : registrar_(registrar), midi_window_(nullptr), device_id_(0),
          current_state_("stopped"), duration_ms_(0), current_position_ms_(0),
          is_progress_thread_running_(false) {
        
        method_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "playmidifile",
            &flutter::StandardMethodCodec::GetInstance());
            
        progress_channel_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
            registrar->messenger(), "playmidifile/progress",
            &flutter::StandardMethodCodec::GetInstance());
            
        state_channel_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
            registrar->messenger(), "playmidifile/state",
            &flutter::StandardMethodCodec::GetInstance());
            
        method_channel_->SetMethodCallHandler([this](const flutter::MethodCall<flutter::EncodableValue>& call,
                                                   std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
            HandleMethodCall(call, std::move(result));
        });
        
        progress_channel_->SetStreamHandler(
            std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
                [this](const flutter::EncodableValue* arguments,
                       std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
                       -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
                    progress_event_sink_ = std::move(events);
                    return nullptr;
                },
                [this](const flutter::EncodableValue* arguments)
                       -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
                    progress_event_sink_.reset();
                    return nullptr;
                }));
                
        state_channel_->SetStreamHandler(
            std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
                [this](const flutter::EncodableValue* arguments,
                       std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
                       -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
                    state_event_sink_ = std::move(events);
                    return nullptr;
                },
                [this](const flutter::EncodableValue* arguments)
                       -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
                    state_event_sink_.reset();
                    return nullptr;
                }));
    }
    
    ~PlayMidifilePluginCApi() {
        Dispose();
    }
    
private:
    void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& method_call,
                         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        
        const std::string& method_name = method_call.method_name();
        
        if (method_name == "initialize") {
            Initialize(std::move(result));
        } else if (method_name == "loadFile") {
            const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
            if (arguments) {
                auto file_path_it = arguments->find(flutter::EncodableValue("filePath"));
                if (file_path_it != arguments->end()) {
                    const std::string file_path = std::get<std::string>(file_path_it->second);
                    LoadFile(file_path, std::move(result));
                } else {
                    result->Error("INVALID_ARGUMENT", "文件路径不能为空");
                }
            } else {
                result->Error("INVALID_ARGUMENT", "参数格式错误");
            }
        } else if (method_name == "loadAsset") {
            const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
            if (arguments) {
                auto asset_path_it = arguments->find(flutter::EncodableValue("assetPath"));
                if (asset_path_it != arguments->end()) {
                    const std::string asset_path = std::get<std::string>(asset_path_it->second);
                    LoadAsset(asset_path, std::move(result));
                } else {
                    result->Error("INVALID_ARGUMENT", "资源路径不能为空");
                }
            } else {
                result->Error("INVALID_ARGUMENT", "参数格式错误");
            }
        } else if (method_name == "play") {
            Play(std::move(result));
        } else if (method_name == "pause") {
            Pause(std::move(result));
        } else if (method_name == "stop") {
            Stop(std::move(result));
        } else if (method_name == "seekTo") {
            const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
            if (arguments) {
                auto position_it = arguments->find(flutter::EncodableValue("positionMs"));
                if (position_it != arguments->end()) {
                    const int position_ms = std::get<int>(position_it->second);
                    SeekTo(position_ms, std::move(result));
                } else {
                    result->Error("INVALID_ARGUMENT", "位置参数不能为空");
                }
            } else {
                result->Error("INVALID_ARGUMENT", "参数格式错误");
            }
        } else if (method_name == "setSpeed") {
            // Windows MIDI API不直接支持变速播放
            result->Success();
        } else if (method_name == "setVolume") {
            const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
            if (arguments) {
                auto volume_it = arguments->find(flutter::EncodableValue("volume"));
                if (volume_it != arguments->end()) {
                    const double volume = std::get<double>(volume_it->second);
                    SetVolume(volume, std::move(result));
                } else {
                    result->Error("INVALID_ARGUMENT", "音量参数不能为空");
                }
            } else {
                result->Error("INVALID_ARGUMENT", "参数格式错误");
            }
        } else if (method_name == "getCurrentState") {
            result->Success(flutter::EncodableValue(current_state_));
        } else if (method_name == "getCurrentInfo") {
            GetCurrentInfo(std::move(result));
        } else if (method_name == "dispose") {
            Dispose();
            result->Success();
        } else {
            result->NotImplemented();
        }
    }
    
    void Initialize(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        // 创建隐藏窗口用于接收MIDI消息
        WNDCLASS wc = {};
        wc.lpfnWndProc = DefWindowProc;
        wc.hInstance = GetModuleHandle(nullptr);
        wc.lpszClassName = L"MidiPlayerWindow";
        RegisterClass(&wc);
        
        midi_window_ = CreateWindow(L"MidiPlayerWindow", L"MIDI Player",
                                   0, 0, 0, 0, 0, HWND_MESSAGE, nullptr,
                                   GetModuleHandle(nullptr), nullptr);
        
        if (midi_window_) {
            result->Success();
        } else {
            result->Error("INIT_ERROR", "初始化失败");
        }
    }
    
    void LoadFile(const std::string& file_path, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        std::wstring wide_path(file_path.begin(), file_path.end());
        
        // 检查文件是否存在
        DWORD attributes = GetFileAttributes(wide_path.c_str());
        if (attributes == INVALID_FILE_ATTRIBUTES) {
            result->Error("FILE_NOT_FOUND", "文件不存在: " + file_path);
            return;
        }
        
        // 使用mciSendString打开MIDI文件
        std::wstring command = L"open \"" + wide_path + L"\" type sequencer alias midi";
        MCIERROR error = mciSendString(command.c_str(), nullptr, 0, midi_window_);
        
        if (error == 0) {
            // 获取文件时长
            wchar_t buffer[256];
            error = mciSendString(L"status midi length", buffer, sizeof(buffer)/sizeof(wchar_t), midi_window_);
            if (error == 0) {
                duration_ms_ = _wtoi(buffer);
            }
            
            UpdateState("stopped");
            result->Success(flutter::EncodableValue(true));
        } else {
            result->Error("LOAD_ERROR", "加载文件失败");
        }
    }
    
    void LoadAsset(const std::string& asset_path, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        // 对于Windows，我们假设资源文件在应用程序目录下
        char exe_path[MAX_PATH];
        GetModuleFileNameA(nullptr, exe_path, MAX_PATH);
        std::string exe_dir = exe_path;
        size_t last_slash = exe_dir.find_last_of("\\/");
        if (last_slash != std::string::npos) {
            exe_dir = exe_dir.substr(0, last_slash);
        }
        
        std::string full_path = exe_dir + "\\" + asset_path;
        LoadFile(full_path, std::move(result));
    }
    
    void Play(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        MCIERROR error = mciSendString(L"play midi", nullptr, 0, midi_window_);
        if (error == 0) {
            UpdateState("playing");
            StartProgressTimer();
            result->Success();
        } else {
            result->Error("PLAY_ERROR", "播放失败");
        }
    }
    
    void Pause(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        MCIERROR error = mciSendString(L"pause midi", nullptr, 0, midi_window_);
        if (error == 0) {
            UpdateState("paused");
            StopProgressTimer();
            result->Success();
        } else {
            result->Error("PAUSE_ERROR", "暂停失败");
        }
    }
    
    void Stop(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        MCIERROR error = mciSendString(L"stop midi", nullptr, 0, midi_window_);
        if (error == 0) {
            mciSendString(L"seek midi to start", nullptr, 0, midi_window_);
            UpdateState("stopped");
            StopProgressTimer();
            current_position_ms_ = 0;
            result->Success();
        } else {
            result->Error("STOP_ERROR", "停止失败");
        }
    }
    
    void SeekTo(int position_ms, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        std::wstring command = L"seek midi to " + std::to_wstring(position_ms);
        MCIERROR error = mciSendString(command.c_str(), nullptr, 0, midi_window_);
        if (error == 0) {
            current_position_ms_ = position_ms;
            UpdateProgress();
            result->Success();
        } else {
            result->Error("SEEK_ERROR", "跳转失败");
        }
    }
    
    void SetVolume(double volume, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        // Windows MIDI API的音量控制
        int vol = static_cast<int>(volume * 1000);
        std::wstring command = L"setaudio midi volume to " + std::to_wstring(vol);
        mciSendString(command.c_str(), nullptr, 0, midi_window_);
        result->Success();
    }
    
    void GetCurrentInfo(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        // 获取当前位置
        wchar_t buffer[256];
        MCIERROR error = mciSendString(L"status midi position", buffer, sizeof(buffer)/sizeof(wchar_t), midi_window_);
        if (error == 0) {
            current_position_ms_ = _wtoi(buffer);
        }
        
        double progress = duration_ms_ > 0 ? static_cast<double>(current_position_ms_) / duration_ms_ : 0.0;
        
        flutter::EncodableMap info;
        info[flutter::EncodableValue("currentPositionMs")] = flutter::EncodableValue(static_cast<int>(current_position_ms_));
        info[flutter::EncodableValue("durationMs")] = flutter::EncodableValue(static_cast<int>(duration_ms_));
        info[flutter::EncodableValue("progress")] = flutter::EncodableValue(progress);
        
        result->Success(flutter::EncodableValue(info));
    }
    
    void Dispose() {
        StopProgressTimer();
        mciSendString(L"close midi", nullptr, 0, midi_window_);
        if (midi_window_) {
            DestroyWindow(midi_window_);
            midi_window_ = nullptr;
        }
    }
    
    void UpdateState(const std::string& new_state) {
        current_state_ = new_state;
        if (state_event_sink_) {
            state_event_sink_->Success(flutter::EncodableValue(new_state));
        }
    }
    
    void StartProgressTimer() {
        StopProgressTimer();
        is_progress_thread_running_ = true;
        progress_thread_ = std::thread([this]() {
            while (is_progress_thread_running_) {
                UpdateProgress();
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
            }
        });
    }
    
    void StopProgressTimer() {
        is_progress_thread_running_ = false;
        if (progress_thread_.joinable()) {
            progress_thread_.join();
        }
    }
    
    void UpdateProgress() {
        if (current_state_ == "playing") {
            wchar_t buffer[256];
            MCIERROR error = mciSendString(L"status midi position", buffer, sizeof(buffer)/sizeof(wchar_t), midi_window_);
            if (error == 0) {
                current_position_ms_ = _wtoi(buffer);
                
                double progress = duration_ms_ > 0 ? static_cast<double>(current_position_ms_) / duration_ms_ : 0.0;
                
                flutter::EncodableMap info;
                info[flutter::EncodableValue("currentPositionMs")] = flutter::EncodableValue(static_cast<int>(current_position_ms_));
                info[flutter::EncodableValue("durationMs")] = flutter::EncodableValue(static_cast<int>(duration_ms_));
                info[flutter::EncodableValue("progress")] = flutter::EncodableValue(progress);
                
                if (progress_event_sink_) {
                    progress_event_sink_->Success(flutter::EncodableValue(info));
                }
                
                // 检查是否播放完成
                if (current_position_ms_ >= duration_ms_ && duration_ms_ > 0) {
                    UpdateState("stopped");
                    StopProgressTimer();
                }
            }
        }
    }
};

}  // namespace playmidifile

void PlayMidifilePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  playmidifile::PlayMidifilePluginCApi::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
} 