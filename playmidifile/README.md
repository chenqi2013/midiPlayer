# PlayMidifile

一个跨平台的Flutter MIDI文件播放器插件，支持Android、iOS、Windows、macOS平台。

## 功能特性

✅ **播放控制**
- 播放、暂停、停止MIDI文件
- 跳转到指定位置(seek)
- 实时播放进度监听

✅ **音频控制**
- 音量调节(0.0 - 1.0)
- 播放速度调节(0.5x - 2.0x)

✅ **文件支持**
- 从文件路径加载MIDI文件
- 从assets资源加载MIDI文件

✅ **跨平台支持**
- ✅ Android (使用MediaPlayer)
- ✅ iOS (使用MusicSequence API)
- ✅ Windows (使用MCI API)
- ✅ macOS (使用MusicSequence API)

✅ **状态监听**
- 播放进度实时更新（通过定时器）
- 播放完成自动检测
- 播放状态管理

## 安装

在您的`pubspec.yaml`文件中添加依赖：

```yaml
dependencies:
  playmidifile: ^0.0.1
```

然后运行：

```bash
flutter pub get
```

## 使用方法

### 1. 初始化播放器

```dart
import 'package:playmidifile/playmidifile.dart';

// 获取播放器实例
final player = PlayMidifile.instance;

// 初始化播放器
await player.initialize();
```

### 2. 加载MIDI文件

```dart
// 从文件路径加载
bool success = await player.loadFile('/path/to/your/file.mid');

// 从assets加载
bool success = await player.loadAsset('assets/demo.mid');
```

### 3. 播放控制

```dart
// 播放
await player.play();

// 暂停
await player.pause();

// 停止
await player.stop();

// 跳转到指定位置(毫秒)
await player.seekTo(30000); // 跳转到30秒
```

### 4. 音频设置

```dart
// 设置音量 (0.0 - 1.0)
await player.setVolume(0.8);

// 设置播放速度 (0.5 - 2.0)
await player.setSpeed(1.5);
```

### 5. 进度监听

由于平台限制，插件使用定时器方式获取播放进度（建议200ms间隔）：

```dart
import 'dart:async';

Timer? _progressTimer;

// 启动进度更新定时器
void _startProgressTimer() {
  _progressTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
    final info = await player.getCurrentInfo();
    if (info != null) {
      // 更新UI显示进度
      setState(() {
        _currentPosition = info.currentPositionMs;
        _duration = info.durationMs;
        _progress = info.progress;
      });
    }
  });
}

// 停止进度更新定时器
void _stopProgressTimer() {
  _progressTimer?.cancel();
  _progressTimer = null;
}
```

### 6. 获取当前信息

```dart
// 获取当前播放信息
MidiPlaybackInfo? info = await player.getCurrentInfo();
if (info != null) {
  print('当前位置: ${info.currentPositionMs}ms');
  print('总时长: ${info.durationMs}ms');
  print('播放进度: ${info.progress}');
}
```

### 7. 资源释放

```dart
// 释放播放器资源
await player.dispose();
```

## 完整示例

```dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:playmidifile/playmidifile.dart';

class MidiPlayerExample extends StatefulWidget {
  @override
  _MidiPlayerExampleState createState() => _MidiPlayerExampleState();
}

class _MidiPlayerExampleState extends State<MidiPlayerExample> {
  final PlayMidifile _player = PlayMidifile.instance;
  MidiPlaybackInfo? _playbackInfo;
  Timer? _progressTimer;
  bool _isPlaying = false;
  String _statusMessage = '未初始化';
  
  @override
  void initState() {
    super.initState();
    _initPlayer();
  }
  
  Future<void> _initPlayer() async {
    try {
      await _player.initialize();
      setState(() {
        _statusMessage = '初始化成功';
      });
      
      // 加载示例文件
      final success = await _player.loadAsset('assets/demo.mid');
      if (success) {
        final info = await _player.getCurrentInfo();
        setState(() {
          _playbackInfo = info;
          _statusMessage = '文件加载成功';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = '初始化失败: $e';
      });
    }
  }
  
  // 启动进度更新定时器（200ms间隔）
  void _startProgressTimer() {
    _progressTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (_isPlaying) {
        final info = await _player.getCurrentInfo();
        if (mounted && info != null) {
          setState(() {
            _playbackInfo = info;
          });
          
          // 检测播放完成（进度≥0.99）
          if (info.progress >= 0.99) {
            _handlePlaybackComplete();
          }
        }
      }
    });
  }
  
  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }
  
  void _handlePlaybackComplete() {
    _stopProgressTimer();
    setState(() {
      _isPlaying = false;
      _statusMessage = '播放完成';
    });
  }
  
  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _player.pause();
      _stopProgressTimer();
      setState(() {
        _isPlaying = false;
        _statusMessage = '已暂停';
      });
    } else {
      await _player.play();
      _startProgressTimer();
      setState(() {
        _isPlaying = true;
        _statusMessage = '播放中';
      });
    }
  }
  
  Future<void> _stop() async {
    await _player.stop();
    _stopProgressTimer();
    setState(() {
      _isPlaying = false;
      _statusMessage = '已停止';
      if (_playbackInfo != null) {
        _playbackInfo = MidiPlaybackInfo(
          currentPositionMs: 0,
          durationMs: _playbackInfo!.durationMs,
          progress: 0.0,
        );
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('MIDI播放器')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('状态: $_statusMessage'),
            if (_playbackInfo != null) ...[
              Row(
                children: [
                  Text(_formatDuration(_playbackInfo!.currentPositionMs)),
                  Expanded(
                    child: Slider(
                      value: _playbackInfo!.progress.clamp(0.0, 1.0),
                      onChanged: (value) async {
                        final positionMs = (value * _playbackInfo!.durationMs).round();
                        await _player.seekTo(positionMs);
                      },
                    ),
                  ),
                  Text(_formatDuration(_playbackInfo!.durationMs)),
                ],
              ),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: _togglePlayPause,
                ),
                IconButton(
                  icon: Icon(Icons.stop),
                  onPressed: _stop,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  // 格式化时间显示（分:秒）
  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
  
  @override
  void dispose() {
    _stopProgressTimer(); // 停止进度定时器
    _player.dispose(); // 释放播放器资源
    super.dispose();
  }
}
```

## API 参考

### PlayMidifile

主要的MIDI播放器类，使用单例模式。

#### 方法

- `initialize()` - 初始化播放器
- `loadFile(String filePath)` - 从文件路径加载MIDI文件
- `loadAsset(String assetPath)` - 从assets加载MIDI文件
- `play()` - 开始播放
- `pause()` - 暂停播放
- `stop()` - 停止播放
- `seekTo(int positionMs)` - 跳转到指定位置（毫秒）
- `setVolume(double volume)` - 设置音量 (0.0-1.0)
- `setSpeed(double speed)` - 设置播放速度 (0.5-2.0)
- `getCurrentInfo()` - 获取当前播放信息
- `dispose()` - 释放资源

#### 属性

- `onStateChanged` - 播放状态变化流（当前返回空流）
- `onProgressChanged` - 播放进度变化流（当前返回空流）

**注意**：由于平台限制，进度监听建议使用定时器方式，每200ms调用`getCurrentInfo()`获取最新进度。播放完成可通过检测进度值≥0.99来判断。

### MidiPlayerState

播放器状态枚举：

- `stopped` - 已停止
- `playing` - 播放中
- `paused` - 已暂停
- `error` - 错误状态

### MidiPlaybackInfo

播放信息类：

- `currentPositionMs` - 当前播放位置(毫秒)
- `durationMs` - 总时长(毫秒)
- `progress` - 播放进度(0.0-1.0)

## 平台特性

### Android
- 使用Android MediaPlayer API
- 支持所有MediaPlayer支持的MIDI格式
- 支持播放速度调节(API 23+)

### iOS
- 使用MusicSequence API
- 支持iOS标准MIDI格式
- 完整的播放控制支持

### Windows
- 使用Windows MCI (Media Control Interface) API
- 支持标准MIDI文件格式
- 音量控制通过MCI实现

### macOS
- 使用MusicSequence API (与iOS相同)
- 完整的macOS音频系统集成
- 支持所有播放控制功能

## 支持的文件格式

- `.mid` - 标准MIDI文件
- `.midi` - MIDI文件

**注意**：支持标准MIDI 0和MIDI 1格式，建议使用标准MIDI文件以确保最佳兼容性。

## 注意事项

1. **文件权限**: 确保应用有访问文件的权限
2. **Assets配置**: 使用assets文件时，确保在`pubspec.yaml`中正确配置
3. **播放速度**: Windows平台可能不支持播放速度调节
4. **内存管理**: 及时调用`dispose()`释放资源
5. **进度监听**: 建议使用定时器方式获取播放进度，频率建议200ms
6. **播放完成检测**: 通过检测进度值≥0.99来判断播放完成

## 故障排除

### 文件无法播放
1. 检查文件格式是否为标准MIDI格式
2. 确认文件路径是否正确
3. 检查文件访问权限
4. 确保文件未损坏且可正常打开

### Android权限问题
在`android/app/src/main/AndroidManifest.xml`中添加必要权限：

```xml
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
```

### iOS权限问题
在`ios/Runner/Info.plist`中添加必要权限：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to play audio files.</string>
```

### macOS权限问题
在`macos/Runner/Info.plist`中添加必要权限：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to play audio files.</string>
```

## 贡献

欢迎提交Issue和Pull Request来改进这个插件。

## 许可证

此项目使用MIT许可证。详见[LICENSE](LICENSE)文件。

## 更新日志

### 0.0.1
- 初始版本
- 支持Android、iOS、Windows、macOS平台
- 基本的播放控制功能（播放、暂停、停止、跳转）
- 音量和速度调节
- 播放状态和进度监听
- 修复了各平台的播放完成检测和时长计算问题
- 支持从文件路径和assets加载MIDI文件
