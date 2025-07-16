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
- ✅ iOS (使用AVAudioPlayer)
- ✅ Windows (使用MCI API)
- ✅ macOS (使用AVAudioPlayer)

✅ **状态监听**
- 播放状态变化监听
- 播放进度实时更新

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

### 5. 状态监听

```dart
// 监听播放状态变化
player.onStateChanged.listen((MidiPlayerState state) {
  switch (state) {
    case MidiPlayerState.stopped:
      print('播放器已停止');
      break;
    case MidiPlayerState.playing:
      print('正在播放');
      break;
    case MidiPlayerState.paused:
      print('播放器已暂停');
      break;
    case MidiPlayerState.error:
      print('播放出错');
      break;
  }
});

// 监听播放进度
player.onProgressChanged.listen((MidiPlaybackInfo info) {
  print('当前位置: ${info.currentPositionMs}ms');
  print('总时长: ${info.durationMs}ms');
  print('播放进度: ${(info.progress * 100).toStringAsFixed(1)}%');
});
```

### 6. 获取当前信息

```dart
// 获取当前播放状态
MidiPlayerState state = await player.getCurrentState();

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
import 'package:playmidifile/playmidifile.dart';

class MidiPlayerExample extends StatefulWidget {
  @override
  _MidiPlayerExampleState createState() => _MidiPlayerExampleState();
}

class _MidiPlayerExampleState extends State<MidiPlayerExample> {
  final PlayMidifile _player = PlayMidifile.instance;
  MidiPlayerState _state = MidiPlayerState.stopped;
  MidiPlaybackInfo? _info;
  
  @override
  void initState() {
    super.initState();
    _initPlayer();
  }
  
  Future<void> _initPlayer() async {
    await _player.initialize();
    
    // 监听状态变化
    _player.onStateChanged.listen((state) {
      setState(() => _state = state);
    });
    
    // 监听进度变化
    _player.onProgressChanged.listen((info) {
      setState(() => _info = info);
    });
    
    // 加载示例文件
    await _player.loadAsset('assets/demo.mid');
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('MIDI播放器')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('状态: ${_state.toString()}'),
            if (_info != null) ...[
              Text('进度: ${_info!.currentPositionMs}/${_info!.durationMs}ms'),
              Slider(
                value: _info!.progress,
                onChanged: (value) async {
                  final pos = (value * _info!.durationMs).round();
                  await _player.seekTo(pos);
                },
              ),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.play_arrow),
                  onPressed: () => _player.play(),
                ),
                IconButton(
                  icon: Icon(Icons.pause),
                  onPressed: () => _player.pause(),
                ),
                IconButton(
                  icon: Icon(Icons.stop),
                  onPressed: () => _player.stop(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _player.dispose();
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
- `seekTo(int positionMs)` - 跳转到指定位置
- `setVolume(double volume)` - 设置音量 (0.0-1.0)
- `setSpeed(double speed)` - 设置播放速度 (0.5-2.0)
- `getCurrentState()` - 获取当前播放状态
- `getCurrentInfo()` - 获取当前播放信息
- `dispose()` - 释放资源

#### 属性

- `onStateChanged` - 播放状态变化流
- `onProgressChanged` - 播放进度变化流

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
- 使用AVAudioPlayer
- 支持iOS标准音频格式
- 完整的播放控制支持

### Windows
- 使用Windows MCI (Media Control Interface) API
- 支持标准MIDI文件格式
- 音量控制通过MCI实现

### macOS
- 使用AVAudioPlayer (与iOS相同)
- 完整的macOS音频系统集成
- 支持所有播放控制功能

## 支持的文件格式

- `.mid` - 标准MIDI文件
- `.midi` - MIDI文件

## 注意事项

1. **文件权限**: 确保应用有访问文件的权限
2. **Assets配置**: 使用assets文件时，确保在`pubspec.yaml`中正确配置
3. **播放速度**: Windows平台可能不支持播放速度调节
4. **内存管理**: 及时调用`dispose()`释放资源

## 故障排除

### 文件无法播放
1. 检查文件格式是否为标准MIDI格式
2. 确认文件路径是否正确
3. 检查文件访问权限

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

## 贡献

欢迎提交Issue和Pull Request来改进这个插件。

## 许可证

此项目使用MIT许可证。详见[LICENSE](LICENSE)文件。

## 更新日志

### 0.0.1
- 初始版本
- 支持Android、iOS、Windows、macOS平台
- 基本的播放控制功能
- 音量和速度调节
- 播放状态和进度监听
