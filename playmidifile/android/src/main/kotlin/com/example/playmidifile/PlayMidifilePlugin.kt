package com.example.playmidifile

import android.content.Context
import android.media.MediaPlayer
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.util.*

/** PlayMidifilePlugin */
class PlayMidifilePlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private lateinit var progressChannel: EventChannel
  private lateinit var stateChannel: EventChannel
  private var context: Context? = null
  
  private var mediaPlayer: MediaPlayer? = null
  private var progressEventSink: EventChannel.EventSink? = null
  private var stateEventSink: EventChannel.EventSink? = null
  private val handler = Handler(Looper.getMainLooper())
  private var progressTimer: Timer? = null
  
  private var currentState = "stopped"
  private var duration = 0
  private var currentPosition = 0

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    context = flutterPluginBinding.applicationContext
    
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "playmidifile")
    channel.setMethodCallHandler(this)
    
    progressChannel = EventChannel(flutterPluginBinding.binaryMessenger, "playmidifile/progress")
    progressChannel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        progressEventSink = events
      }
      
      override fun onCancel(arguments: Any?) {
        progressEventSink = null
      }
    })
    
    stateChannel = EventChannel(flutterPluginBinding.binaryMessenger, "playmidifile/state")
    stateChannel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        stateEventSink = events
      }
      
      override fun onCancel(arguments: Any?) {
        stateEventSink = null
      }
    })
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "initialize" -> {
        initialize(result)
      }
      "loadFile" -> {
        val filePath = call.argument<String>("filePath")
        if (filePath != null) {
          loadFile(filePath, result)
        } else {
          result.error("INVALID_ARGUMENT", "文件路径不能为空", null)
        }
      }
      "loadAsset" -> {
        val assetPath = call.argument<String>("assetPath")
        if (assetPath != null) {
          loadAsset(assetPath, result)
        } else {
          result.error("INVALID_ARGUMENT", "资源路径不能为空", null)
        }
      }
      "play" -> {
        play(result)
      }
      "pause" -> {
        pause(result)
      }
      "stop" -> {
        stop(result)
      }
      "seekTo" -> {
        val positionMs = call.argument<Int>("positionMs")
        if (positionMs != null) {
          seekTo(positionMs, result)
        } else {
          result.error("INVALID_ARGUMENT", "位置参数不能为空", null)
        }
      }
      "setSpeed" -> {
        val speed = call.argument<Double>("speed")
        if (speed != null) {
          setSpeed(speed.toFloat(), result)
        } else {
          result.error("INVALID_ARGUMENT", "速度参数不能为空", null)
        }
      }
      "setVolume" -> {
        val volume = call.argument<Double>("volume")
        if (volume != null) {
          setVolume(volume.toFloat(), result)
        } else {
          result.error("INVALID_ARGUMENT", "音量参数不能为空", null)
        }
      }
      "getCurrentState" -> {
        result.success(currentState)
      }
      "getCurrentInfo" -> {
        getCurrentInfo(result)
      }
      "dispose" -> {
        dispose(result)
      }
      else -> {
        result.notImplemented()
      }
    }
  }
  
  private fun initialize(result: Result) {
    try {
      result.success(null)
    } catch (e: Exception) {
      result.error("INIT_ERROR", "初始化失败: ${e.message}", null)
    }
  }
  
  private fun loadFile(filePath: String, result: Result) {
    try {
      releaseMediaPlayer()
      
      val file = File(filePath)
      if (!file.exists()) {
        result.error("FILE_NOT_FOUND", "文件不存在: $filePath", null)
        return
      }
      
      mediaPlayer = MediaPlayer().apply {
        setDataSource(filePath)
        prepareAsync()
        setOnPreparedListener { mp ->
          this@PlayMidifilePlugin.duration = mp.duration
          updateState("stopped")
          result.success(true)
        }
        setOnErrorListener { _, what, extra ->
          updateState("error")
          result.error("LOAD_ERROR", "加载文件失败: what=$what, extra=$extra", null)
          true
        }
        setOnCompletionListener {
          updateState("stopped")
          stopProgressTimer()
        }
      }
    } catch (e: Exception) {
      result.error("LOAD_ERROR", "加载文件失败: ${e.message}", null)
    }
  }
  
  private fun loadAsset(assetPath: String, result: Result) {
    try {
      releaseMediaPlayer()
      
      val flutterLoader = io.flutter.FlutterInjector.instance().flutterLoader()
      val assetKey = flutterLoader.getLookupKeyForAsset(assetPath)
      
      val assetManager = context?.assets
      if (assetManager == null) {
        result.error("CONTEXT_ERROR", "无法获取应用上下文", null)
        return
      }
      
      mediaPlayer = MediaPlayer().apply {
        try {
          val afd = assetManager.openFd(assetKey)
          setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
          afd.close()
        } catch (e: Exception) {
          // 如果通过Flutter asset路径失败，尝试直接使用传入的路径
          val afd = assetManager.openFd(assetPath)
          setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
          afd.close()
        }
        
        prepareAsync()
        setOnPreparedListener { mp ->
          this@PlayMidifilePlugin.duration = mp.duration
          updateState("stopped")
          result.success(true)
        }
        setOnErrorListener { _, what, extra ->
          updateState("error")
          result.error("LOAD_ERROR", "加载资源失败: $assetPath, what=$what, extra=$extra", null)
          true
        }
        setOnCompletionListener {
          updateState("stopped")
          stopProgressTimer()
        }
      }
    } catch (e: Exception) {
      result.error("LOAD_ERROR", "加载资源失败: ${e.message}", null)
    }
  }
  
  private fun play(result: Result) {
    try {
      val mp = mediaPlayer
      if (mp == null) {
        result.error("NO_FILE", "请先加载文件", null)
        return
      }
      
      mp.start()
      updateState("playing")
      startProgressTimer()
      result.success(null)
    } catch (e: Exception) {
      result.error("PLAY_ERROR", "播放失败: ${e.message}", null)
    }
  }
  
  private fun pause(result: Result) {
    try {
      val mp = mediaPlayer
      if (mp == null) {
        result.error("NO_FILE", "请先加载文件", null)
        return
      }
      
      if (mp.isPlaying) {
        mp.pause()
        updateState("paused")
        stopProgressTimer()
      }
      result.success(null)
    } catch (e: Exception) {
      result.error("PAUSE_ERROR", "暂停失败: ${e.message}", null)
    }
  }
  
  private fun stop(result: Result) {
    try {
      val mp = mediaPlayer
      if (mp != null) {
        if (mp.isPlaying) {
          mp.stop()
        }
        mp.prepareAsync()
        updateState("stopped")
        stopProgressTimer()
      }
      result.success(null)
    } catch (e: Exception) {
      result.error("STOP_ERROR", "停止失败: ${e.message}", null)
    }
  }
  
  private fun seekTo(positionMs: Int, result: Result) {
    try {
      val mp = mediaPlayer
      if (mp == null) {
        result.error("NO_FILE", "请先加载文件", null)
        return
      }
      
      mp.seekTo(positionMs)
      currentPosition = positionMs
      updateProgress()
      result.success(null)
    } catch (e: Exception) {
      result.error("SEEK_ERROR", "跳转失败: ${e.message}", null)
    }
  }
  
  private fun setSpeed(speed: Float, result: Result) {
    try {
      val mp = mediaPlayer
      if (mp == null) {
        result.error("NO_FILE", "请先加载文件", null)
        return
      }
      
      if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
        val params = mp.playbackParams
        params.speed = speed
        mp.playbackParams = params
      }
      result.success(null)
    } catch (e: Exception) {
      result.error("SPEED_ERROR", "设置播放速度失败: ${e.message}", null)
    }
  }
  
  private fun setVolume(volume: Float, result: Result) {
    try {
      val mp = mediaPlayer
      if (mp == null) {
        result.error("NO_FILE", "请先加载文件", null)
        return
      }
      
      mp.setVolume(volume, volume)
      result.success(null)
    } catch (e: Exception) {
      result.error("VOLUME_ERROR", "设置音量失败: ${e.message}", null)
    }
  }
  
  private fun getCurrentInfo(result: Result) {
    try {
      val mp = mediaPlayer
      if (mp != null) {
        currentPosition = mp.currentPosition
        val progress = if (duration > 0) currentPosition.toDouble() / duration.toDouble() else 0.0
        
        val info = mapOf(
          "currentPositionMs" to currentPosition,
          "durationMs" to duration,
          "progress" to progress
        )
        result.success(info)
      } else {
        result.success(null)
      }
    } catch (e: Exception) {
      result.error("INFO_ERROR", "获取播放信息失败: ${e.message}", null)
    }
  }
  
  private fun dispose(result: Result) {
    try {
      releaseMediaPlayer()
      stopProgressTimer()
      result.success(null)
    } catch (e: Exception) {
      result.error("DISPOSE_ERROR", "释放资源失败: ${e.message}", null)
    }
  }
  
  private fun releaseMediaPlayer() {
    mediaPlayer?.let { mp ->
      try {
        if (mp.isPlaying) {
          mp.stop()
        }
        mp.release()
      } catch (e: Exception) {
        // 忽略释放时的错误
      }
    }
    mediaPlayer = null
  }
  
  private fun updateState(newState: String) {
    currentState = newState
    handler.post {
      stateEventSink?.success(newState)
    }
  }
  
  private fun startProgressTimer() {
    stopProgressTimer()
    progressTimer = Timer()
    progressTimer?.scheduleAtFixedRate(object : TimerTask() {
      override fun run() {
        updateProgress()
      }
    }, 0, 100) // 每100ms更新一次
  }
  
  private fun stopProgressTimer() {
    progressTimer?.cancel()
    progressTimer = null
  }
  
  private fun updateProgress() {
    try {
      val mp = mediaPlayer
      if (mp != null && currentState == "playing") {
        currentPosition = mp.currentPosition
        val progress = if (duration > 0) currentPosition.toDouble() / duration.toDouble() else 0.0
        
        val info = mapOf(
          "currentPositionMs" to currentPosition,
          "durationMs" to duration,
          "progress" to progress
        )
        
        handler.post {
          progressEventSink?.success(info)
        }
      }
    } catch (e: Exception) {
      // 忽略更新进度时的错误
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    releaseMediaPlayer()
    stopProgressTimer()
  }
} 