import Flutter
import UIKit
import AVFoundation
import MediaPlayer

public class PlayMidifilePlugin: NSObject, FlutterPlugin {
    private var methodChannel: FlutterMethodChannel?
    private var progressEventChannel: FlutterEventChannel?
    private var stateEventChannel: FlutterEventChannel?
    private var progressEventSink: FlutterEventSink?
    private var stateEventSink: FlutterEventSink?
    
    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?
    private var currentState = "stopped"
    private var duration: TimeInterval = 0
    private var currentPosition: TimeInterval = 0
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "playmidifile", binaryMessenger: registrar.messenger())
        let progressChannel = FlutterEventChannel(name: "playmidifile/progress", binaryMessenger: registrar.messenger())
        let stateChannel = FlutterEventChannel(name: "playmidifile/state", binaryMessenger: registrar.messenger())
        
        let instance = PlayMidifilePlugin()
        instance.methodChannel = channel
        instance.progressEventChannel = progressChannel
        instance.stateEventChannel = stateChannel
        
        registrar.addMethodCallDelegate(instance, channel: channel)
        progressChannel.setStreamHandler(instance)
        stateChannel.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            initialize(result: result)
        case "loadFile":
            guard let args = call.arguments as? [String: Any],
                  let filePath = args["filePath"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "文件路径不能为空", details: nil))
                return
            }
            loadFile(filePath: filePath, result: result)
        case "loadAsset":
            guard let args = call.arguments as? [String: Any],
                  let assetPath = args["assetPath"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "资源路径不能为空", details: nil))
                return
            }
            loadAsset(assetPath: assetPath, result: result)
        case "play":
            play(result: result)
        case "pause":
            pause(result: result)
        case "stop":
            stop(result: result)
        case "seekTo":
            guard let args = call.arguments as? [String: Any],
                  let positionMs = args["positionMs"] as? Int else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "位置参数不能为空", details: nil))
                return
            }
            seekTo(positionMs: positionMs, result: result)
        case "setSpeed":
            guard let args = call.arguments as? [String: Any],
                  let speed = args["speed"] as? Double else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "速度参数不能为空", details: nil))
                return
            }
            setSpeed(speed: Float(speed), result: result)
        case "setVolume":
            guard let args = call.arguments as? [String: Any],
                  let volume = args["volume"] as? Double else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "音量参数不能为空", details: nil))
                return
            }
            setVolume(volume: Float(volume), result: result)
        case "getCurrentState":
            result(currentState)
        case "getCurrentInfo":
            getCurrentInfo(result: result)
        case "dispose":
            dispose(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func initialize(result: @escaping FlutterResult) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            result(nil)
        } catch {
            result(FlutterError(code: "INIT_ERROR", message: "初始化失败: \(error.localizedDescription)", details: nil))
        }
    }
    
    private func loadFile(filePath: String, result: @escaping FlutterResult) {
        do {
            releaseAudioPlayer()
            
            let url = URL(fileURLWithPath: filePath)
            guard FileManager.default.fileExists(atPath: filePath) else {
                result(FlutterError(code: "FILE_NOT_FOUND", message: "文件不存在: \(filePath)", details: nil))
                return
            }
            
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            
            duration = audioPlayer?.duration ?? 0
            updateState("stopped")
            result(true)
        } catch {
            result(FlutterError(code: "LOAD_ERROR", message: "加载文件失败: \(error.localizedDescription)", details: nil))
        }
    }
    
    private func loadAsset(assetPath: String, result: @escaping FlutterResult) {
        do {
            releaseAudioPlayer()
            
            guard let path = Bundle.main.path(forResource: assetPath, ofType: nil) else {
                result(FlutterError(code: "FILE_NOT_FOUND", message: "资源文件不存在: \(assetPath)", details: nil))
                return
            }
            
            let url = URL(fileURLWithPath: path)
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            
            duration = audioPlayer?.duration ?? 0
            updateState("stopped")
            result(true)
        } catch {
            result(FlutterError(code: "LOAD_ERROR", message: "加载资源失败: \(error.localizedDescription)", details: nil))
        }
    }
    
    private func play(result: @escaping FlutterResult) {
        guard let player = audioPlayer else {
            result(FlutterError(code: "NO_FILE", message: "请先加载文件", details: nil))
            return
        }
        
        player.play()
        updateState("playing")
        startProgressTimer()
        result(nil)
    }
    
    private func pause(result: @escaping FlutterResult) {
        guard let player = audioPlayer else {
            result(FlutterError(code: "NO_FILE", message: "请先加载文件", details: nil))
            return
        }
        
        if player.isPlaying {
            player.pause()
            updateState("paused")
            stopProgressTimer()
        }
        result(nil)
    }
    
    private func stop(result: @escaping FlutterResult) {
        guard let player = audioPlayer else {
            result(FlutterError(code: "NO_FILE", message: "请先加载文件", details: nil))
            return
        }
        
        player.stop()
        player.currentTime = 0
        updateState("stopped")
        stopProgressTimer()
        result(nil)
    }
    
    private func seekTo(positionMs: Int, result: @escaping FlutterResult) {
        guard let player = audioPlayer else {
            result(FlutterError(code: "NO_FILE", message: "请先加载文件", details: nil))
            return
        }
        
        let timeInSeconds = Double(positionMs) / 1000.0
        player.currentTime = timeInSeconds
        currentPosition = timeInSeconds
        updateProgress()
        result(nil)
    }
    
    private func setSpeed(speed: Float, result: @escaping FlutterResult) {
        guard let player = audioPlayer else {
            result(FlutterError(code: "NO_FILE", message: "请先加载文件", details: nil))
            return
        }
        
        if #available(iOS 10.0, *) {
            player.rate = speed
        }
        result(nil)
    }
    
    private func setVolume(volume: Float, result: @escaping FlutterResult) {
        guard let player = audioPlayer else {
            result(FlutterError(code: "NO_FILE", message: "请先加载文件", details: nil))
            return
        }
        
        player.volume = volume
        result(nil)
    }
    
    private func getCurrentInfo(result: @escaping FlutterResult) {
        guard let player = audioPlayer else {
            result(nil)
            return
        }
        
        currentPosition = player.currentTime
        let progress = duration > 0 ? currentPosition / duration : 0.0
        
        let info: [String: Any] = [
            "currentPositionMs": Int(currentPosition * 1000),
            "durationMs": Int(duration * 1000),
            "progress": progress
        ]
        result(info)
    }
    
    private func dispose(result: @escaping FlutterResult) {
        releaseAudioPlayer()
        stopProgressTimer()
        result(nil)
    }
    
    private func releaseAudioPlayer() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
    
    private func updateState(_ newState: String) {
        currentState = newState
        DispatchQueue.main.async {
            self.stateEventSink?(newState)
        }
    }
    
    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.updateProgress()
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    private func updateProgress() {
        guard let player = audioPlayer, currentState == "playing" else { return }
        
        currentPosition = player.currentTime
        let progress = duration > 0 ? currentPosition / duration : 0.0
        
        let info: [String: Any] = [
            "currentPositionMs": Int(currentPosition * 1000),
            "durationMs": Int(duration * 1000),
            "progress": progress
        ]
        
        DispatchQueue.main.async {
            self.progressEventSink?(info)
        }
    }
}

// MARK: - AVAudioPlayerDelegate
extension PlayMidifilePlugin: AVAudioPlayerDelegate {
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        updateState("stopped")
        stopProgressTimer()
    }
    
    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        updateState("error")
        stopProgressTimer()
    }
}

// MARK: - FlutterStreamHandler
extension PlayMidifilePlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        if let channelName = arguments as? String {
            if channelName == "progress" {
                progressEventSink = events
            } else if channelName == "state" {
                stateEventSink = events
            }
        } else {
            // 通过方法channel判断
            if progressEventSink == nil {
                progressEventSink = events
            } else {
                stateEventSink = events
            }
        }
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        progressEventSink = nil
        stateEventSink = nil
        return nil
    }
} 