import Flutter
import UIKit
import AVFoundation
import AudioToolbox
import MediaPlayer

public class PlayMidifilePlugin: NSObject, FlutterPlugin {
    private var methodChannel: FlutterMethodChannel?
    private var progressEventChannel: FlutterEventChannel?
    private var stateEventChannel: FlutterEventChannel?
    private var progressEventSink: FlutterEventSink?
    private var stateEventSink: FlutterEventSink?
    
    private var musicPlayer: MusicPlayer?
    private var musicSequence: MusicSequence?
    private var progressTimer: Timer?
    private var currentState = "stopped"
    private var duration: TimeInterval = 0
    private var currentPosition: TimeInterval = 0
    private var isInitialized = false
    
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
            
            // 创建MusicPlayer
            var player: MusicPlayer?
            let status = NewMusicPlayer(&player)
            if status != noErr {
                result(FlutterError(code: "INIT_ERROR", message: "创建MusicPlayer失败: \(status)", details: nil))
                return
            }
            musicPlayer = player
            isInitialized = true
            result(nil)
        } catch {
            result(FlutterError(code: "INIT_ERROR", message: "初始化失败: \(error.localizedDescription)", details: nil))
        }
    }
    
    private func loadFile(filePath: String, result: @escaping FlutterResult) {
        guard isInitialized, let player = musicPlayer else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "播放器未初始化", details: nil))
            return
        }
        
        releaseMusicSequence()
        
        guard FileManager.default.fileExists(atPath: filePath) else {
            result(FlutterError(code: "FILE_NOT_FOUND", message: "文件不存在: \(filePath)", details: nil))
            return
        }
        
        let url = URL(fileURLWithPath: filePath)
        
        // 创建MusicSequence
        var sequence: MusicSequence?
        var status = NewMusicSequence(&sequence)
        if status != noErr {
            result(FlutterError(code: "LOAD_ERROR", message: "创建MusicSequence失败: \(status)", details: nil))
            return
        }
        
        // 从文件加载MIDI序列
        status = MusicSequenceFileLoad(sequence!, url as CFURL, .midiType, MusicSequenceLoadFlags())
        if status != noErr {
            DisposeMusicSequence(sequence!)
            result(FlutterError(code: "LOAD_ERROR", message: "加载MIDI文件失败: \(status)", details: nil))
            return
        }
        
        // 设置播放器的序列
        status = MusicPlayerSetSequence(player, sequence)
        if status != noErr {
            DisposeMusicSequence(sequence!)
            result(FlutterError(code: "LOAD_ERROR", message: "设置播放序列失败: \(status)", details: nil))
            return
        }
        
        // 预加载
        status = MusicPlayerPreroll(player)
        if status != noErr {
            DisposeMusicSequence(sequence!)
            result(FlutterError(code: "LOAD_ERROR", message: "预加载失败: \(status)", details: nil))
            return
        }
        
        musicSequence = sequence
        calculateDuration()
        updateState("stopped")
        result(true)
    }
    
    private func loadAsset(assetPath: String, result: @escaping FlutterResult) {
        guard isInitialized, let player = musicPlayer else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "播放器未初始化", details: nil))
            return
        }
        
        releaseMusicSequence()
        
        var resourcePath: String?
        
        // 尝试多种方式查找assets文件
        // 方法1: 使用Flutter的lookupKey
        let key = FlutterDartProject.lookupKey(forAsset: assetPath)
        resourcePath = Bundle.main.path(forResource: key, ofType: nil)
        
        // 方法2: 尝试直接使用asset路径
        if resourcePath == nil {
            resourcePath = Bundle.main.path(forResource: assetPath, ofType: nil)
        }
        
        // 方法3: 移除assets/前缀后尝试
        if resourcePath == nil {
            let fileName = assetPath.hasPrefix("assets/") ? String(assetPath.dropFirst(7)) : assetPath
            resourcePath = Bundle.main.path(forResource: fileName, ofType: nil)
        }
        
        // 方法4: 分离文件名和扩展名
        if resourcePath == nil {
            let fileName = assetPath.hasPrefix("assets/") ? String(assetPath.dropFirst(7)) : assetPath
            let url = URL(fileURLWithPath: fileName)
            let nameWithoutExtension = url.deletingPathExtension().lastPathComponent
            let fileExtension = url.pathExtension.isEmpty ? nil : url.pathExtension
            resourcePath = Bundle.main.path(forResource: nameWithoutExtension, ofType: fileExtension)
        }
        
        guard let path = resourcePath else {
            result(FlutterError(code: "FILE_NOT_FOUND", message: "资源文件不存在: \(assetPath)", details: nil))
            return
        }
        
        let url = URL(fileURLWithPath: path)
        
        // 创建MusicSequence
        var sequence: MusicSequence?
        var status = NewMusicSequence(&sequence)
        if status != noErr {
            result(FlutterError(code: "LOAD_ERROR", message: "创建MusicSequence失败: \(status)", details: nil))
            return
        }
        
        // 从文件加载MIDI序列
        status = MusicSequenceFileLoad(sequence!, url as CFURL, .midiType, MusicSequenceLoadFlags())
        if status != noErr {
            DisposeMusicSequence(sequence!)
            result(FlutterError(code: "LOAD_ERROR", message: "加载MIDI资源失败: \(status)", details: nil))
            return
        }
        
        // 设置播放器的序列
        status = MusicPlayerSetSequence(player, sequence)
        if status != noErr {
            DisposeMusicSequence(sequence!)
            result(FlutterError(code: "LOAD_ERROR", message: "设置播放序列失败: \(status)", details: nil))
            return
        }
        
        // 预加载
        status = MusicPlayerPreroll(player)
        if status != noErr {
            DisposeMusicSequence(sequence!)
            result(FlutterError(code: "LOAD_ERROR", message: "预加载失败: \(status)", details: nil))
            return
        }
        
        musicSequence = sequence
        calculateDuration()
        updateState("stopped")
        result(true)
    }
    
    private func play(result: @escaping FlutterResult) {
        guard let player = musicPlayer, musicSequence != nil else {
            result(FlutterError(code: "NO_FILE", message: "请先加载文件", details: nil))
            return
        }
        
        let status = MusicPlayerStart(player)
        if status == noErr {
            updateState("playing")
            startProgressTimer()
            result(nil)
        } else {
            result(FlutterError(code: "PLAY_ERROR", message: "播放失败: \(status)", details: nil))
        }
    }
    
    private func pause(result: @escaping FlutterResult) {
        guard let player = musicPlayer, musicSequence != nil else {
            result(FlutterError(code: "NO_FILE", message: "请先加载文件", details: nil))
            return
        }
        
        let status = MusicPlayerStop(player)
        if status == noErr {
            updateState("paused")
            stopProgressTimer()
            result(nil)
        } else {
            result(FlutterError(code: "PAUSE_ERROR", message: "暂停失败: \(status)", details: nil))
        }
    }
    
    private func stop(result: @escaping FlutterResult) {
        guard let player = musicPlayer, musicSequence != nil else {
            result(FlutterError(code: "NO_FILE", message: "请先加载文件", details: nil))
            return
        }
        
        var status = MusicPlayerStop(player)
        if status == noErr {
            status = MusicPlayerSetTime(player, 0)
            if status == noErr {
                currentPosition = 0
                updateState("stopped")
                stopProgressTimer()
                result(nil)
            } else {
                result(FlutterError(code: "STOP_ERROR", message: "重置播放位置失败: \(status)", details: nil))
            }
        } else {
            result(FlutterError(code: "STOP_ERROR", message: "停止失败: \(status)", details: nil))
        }
    }
    
    private func seekTo(positionMs: Int, result: @escaping FlutterResult) {
        guard let player = musicPlayer, let sequence = musicSequence else {
            result(FlutterError(code: "NO_FILE", message: "请先加载文件", details: nil))
            return
        }
        
        let timeInSeconds = Double(positionMs) / 1000.0
        
        // 将秒转换为MusicTimeStamp（beats）
        var timeInBeats: MusicTimeStamp = 0
        let conversionStatus = MusicSequenceGetBeatsForSeconds(sequence, timeInSeconds, &timeInBeats)
        if conversionStatus == noErr {
            let status = MusicPlayerSetTime(player, timeInBeats)
            if status == noErr {
                currentPosition = timeInSeconds
                result(nil)
            } else {
                result(FlutterError(code: "SEEK_ERROR", message: "跳转失败: \(status)", details: nil))
            }
        } else {
            // 如果转换失败，使用默认的每分钟120拍计算
            let timeInBeats = timeInSeconds / 0.5  // 假设120 BPM
            let status = MusicPlayerSetTime(player, timeInBeats)
            if status == noErr {
                currentPosition = timeInSeconds
                result(nil)
            } else {
                result(FlutterError(code: "SEEK_ERROR", message: "跳转失败: \(status)", details: nil))
            }
        }
    }
    
    private func setSpeed(speed: Float, result: @escaping FlutterResult) {
        guard let player = musicPlayer, musicSequence != nil else {
            result(FlutterError(code: "NO_FILE", message: "请先加载文件", details: nil))
            return
        }
        
        let status = MusicPlayerSetPlayRateScalar(player, Float64(speed))
        if status == noErr {
            result(nil)
        } else {
            result(FlutterError(code: "SPEED_ERROR", message: "设置速度失败: \(status)", details: nil))
        }
    }
    
    private func setVolume(volume: Float, result: @escaping FlutterResult) {
        // MusicPlayer不直接支持音量控制，在iOS中音量通常由系统控制
        // 暂时返回成功，后续可以实现更复杂的音量控制
        result(nil)
    }
    
    private func getCurrentInfo(result: @escaping FlutterResult) {
        guard let player = musicPlayer, let sequence = musicSequence else {
            result(nil)
            return
        }
        
        var time: MusicTimeStamp = 0
        let status = MusicPlayerGetTime(player, &time)
        if status == noErr {
            // 将MusicTimeStamp（beats）转换为秒
            var timeInSeconds: Float64 = 0
            let conversionStatus = MusicSequenceGetSecondsForBeats(sequence, time, &timeInSeconds)
            if conversionStatus == noErr {
                currentPosition = TimeInterval(timeInSeconds)
            } else {
                // 如果转换失败，使用默认的每分钟120拍计算
                currentPosition = TimeInterval(time * 0.5)
            }
        }
        
        let progress = duration > 0 ? currentPosition / duration : 0.0
        
        let info: [String: Any] = [
            "currentPositionMs": Int(currentPosition * 1000),
            "durationMs": Int(duration * 1000),
            "progress": progress
        ]
        result(info)
    }
    
    private func dispose(result: @escaping FlutterResult) {
        releaseMusicPlayer()
        stopProgressTimer()
        result(nil)
    }
    
    private func releaseMusicPlayer() {
        if let player = musicPlayer {
            MusicPlayerStop(player)
            DisposeMusicPlayer(player)
            musicPlayer = nil
        }
        releaseMusicSequence()
        isInitialized = false
    }
    
    private func releaseMusicSequence() {
        if let sequence = musicSequence {
            DisposeMusicSequence(sequence)
            musicSequence = nil
        }
    }
    
    private func calculateDuration() {
        guard let sequence = musicSequence else {
            duration = 0
            return
        }
        
        var tracks: UInt32 = 0
        let status = MusicSequenceGetTrackCount(sequence, &tracks)
        if status != noErr {
            duration = 0
            return
        }
        
        var maxLength: MusicTimeStamp = 0
        for i in 0..<tracks {
            var track: MusicTrack?
            if MusicSequenceGetIndTrack(sequence, i, &track) == noErr, let track = track {
                var trackLength: MusicTimeStamp = 0
                var propSize: UInt32 = UInt32(MemoryLayout<MusicTimeStamp>.size)
                if MusicTrackGetProperty(track, kSequenceTrackProperty_TrackLength, &trackLength, &propSize) == noErr {
                    maxLength = max(maxLength, trackLength)
                }
            }
        }
        
        // 将MusicTimeStamp（beats）转换为秒
        var durationInSeconds: Float64 = 0
        let conversionStatus = MusicSequenceGetSecondsForBeats(sequence, maxLength, &durationInSeconds)
        if conversionStatus == noErr {
            duration = TimeInterval(durationInSeconds)
        } else {
            // 如果转换失败，使用默认的每分钟120拍计算
            // 1 beat = 1/120 * 60 = 0.5 秒
            duration = TimeInterval(maxLength * 0.5)
        }
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
        guard let player = musicPlayer, let sequence = musicSequence, currentState == "playing" else { return }
        
        var time: MusicTimeStamp = 0
        let status = MusicPlayerGetTime(player, &time)
        if status == noErr {
            // 将MusicTimeStamp（beats）转换为秒
            var timeInSeconds: Float64 = 0
            let conversionStatus = MusicSequenceGetSecondsForBeats(sequence, time, &timeInSeconds)
            if conversionStatus == noErr {
                currentPosition = TimeInterval(timeInSeconds)
            } else {
                // 如果转换失败，使用默认的每分钟120拍计算
                currentPosition = TimeInterval(time * 0.5)
            }
        }
        
        let progress = duration > 0 ? currentPosition / duration : 0.0
        
        let info: [String: Any] = [
            "currentPositionMs": Int(currentPosition * 1000),
            "durationMs": Int(duration * 1000),
            "progress": progress
        ]
        
        DispatchQueue.main.async {
            self.progressEventSink?(info)
        }
        
        // 检查是否播放完成（使用更严格的条件）
        if currentState == "playing" && currentPosition >= duration && duration > 0 && progress >= 0.99 {
            DispatchQueue.main.async {
                // 播放完成后立即停止播放器并重置位置和状态
                if let player = self.musicPlayer {
                    MusicPlayerStop(player)        // 明确停止播放器
                    MusicPlayerSetTime(player, 0)  // 重置位置
                }
                self.currentPosition = 0
                self.updateState("stopped")
                self.stopProgressTimer()
            }
        }
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