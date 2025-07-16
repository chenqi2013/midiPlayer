import 'package:flutter/material.dart';
import 'dart:async';
import 'package:playmidifile/playmidifile.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MIDI播放器示例',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const MidiPlayerDemo(),
    );
  }
}

class MidiPlayerDemo extends StatefulWidget {
  const MidiPlayerDemo({super.key});

  @override
  State<MidiPlayerDemo> createState() => _MidiPlayerDemoState();
}

class _MidiPlayerDemoState extends State<MidiPlayerDemo> {
  final PlayMidifile _player = PlayMidifile.instance;

  MidiPlayerState _playerState = MidiPlayerState.stopped;
  MidiPlaybackInfo? _playbackInfo;
  String? _currentFile;
  double _volume = 1.0;
  double _speed = 1.0;

  StreamSubscription<MidiPlayerState>? _stateSubscription;
  StreamSubscription<MidiPlaybackInfo>? _progressSubscription;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _progressSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    try {
      await _player.initialize();

      // 监听播放状态变化
      _stateSubscription = _player.onStateChanged.listen((state) {
        setState(() {
          _playerState = state;
        });
      });

      // 监听播放进度变化
      _progressSubscription = _player.onProgressChanged.listen((info) {
        setState(() {
          _playbackInfo = info;
        });
      });

      setState(() {});
    } catch (e) {
      _showError('初始化失败: $e');
    }
  }

  Future<void> _loadAssetFile() async {
    try {
      // 加载assets文件夹中的demo.mid文件
      final success = await _player.loadAsset('assets/demo.mid');

      if (success) {
        setState(() {
          _currentFile = 'demo.mid (资源文件)';
        });
        _showMessage('资源文件加载成功');
      } else {
        _showError('资源文件加载失败');
      }
    } catch (e) {
      _showError('加载资源文件失败: $e');
    }
  }

  Future<void> _loadFromPath() async {
    try {
      // 示例：从特定路径加载MIDI文件
      // 在实际应用中，您可以使用file_picker或其他方式来选择文件
      const filePath = '/path/to/your/midi/file.mid';
      final success = await _player.loadFile(filePath);

      if (success) {
        setState(() {
          _currentFile = 'file.mid';
        });
        _showMessage('文件加载成功');
      } else {
        _showError('文件加载失败');
      }
    } catch (e) {
      _showError('加载文件失败: $e');
    }
  }

  Future<void> _play() async {
    try {
      await _player.play();
    } catch (e) {
      _showError('播放失败: $e');
    }
  }

  Future<void> _pause() async {
    try {
      await _player.pause();
    } catch (e) {
      _showError('暂停失败: $e');
    }
  }

  Future<void> _stop() async {
    try {
      await _player.stop();
    } catch (e) {
      _showError('停止失败: $e');
    }
  }

  Future<void> _seekTo(double value) async {
    if (_playbackInfo != null) {
      try {
        final positionMs = (value * _playbackInfo!.durationMs).round();
        await _player.seekTo(positionMs);
      } catch (e) {
        _showError('跳转失败: $e');
      }
    }
  }

  Future<void> _setVolume(double volume) async {
    try {
      await _player.setVolume(volume);
      setState(() {
        _volume = volume;
      });
    } catch (e) {
      _showError('设置音量失败: $e');
    }
  }

  Future<void> _setSpeed(double speed) async {
    try {
      await _player.setSpeed(speed);
      setState(() {
        _speed = speed;
      });
    } catch (e) {
      _showError('设置播放速度失败: $e');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(String error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.red));
  }

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MIDI播放器示例'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 文件选择区域
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '文件选择',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _loadFromPath,
                              icon: const Icon(Icons.folder_open),
                              label: const Text('加载文件路径'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _loadAssetFile,
                              icon: const Icon(Icons.library_music),
                              label: const Text('加载示例文件'),
                            ),
                          ),
                        ],
                      ),
                      if (_currentFile != null) ...[
                        const SizedBox(height: 12),
                        Text('当前文件: $_currentFile'),
                      ],
                      const SizedBox(height: 12),
                      const Text(
                        '提示：要选择文件，请添加file_picker依赖',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 播放控制区域
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '播放控制',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 播放状态
                      Row(
                        children: [
                          const Text('状态: '),
                          Text(
                            _getStateText(_playerState),
                            style: TextStyle(
                              color: _getStateColor(_playerState),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // 进度条
                      if (_playbackInfo != null) ...[
                        Row(
                          children: [
                            Text(
                              _formatDuration(_playbackInfo!.currentPositionMs),
                            ),
                            Expanded(
                              child: Slider(
                                value: _playbackInfo!.progress,
                                onChanged: _currentFile != null
                                    ? _seekTo
                                    : null,
                                min: 0.0,
                                max: 1.0,
                              ),
                            ),
                            Text(_formatDuration(_playbackInfo!.durationMs)),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],

                      // 控制按钮
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton.filled(
                            onPressed: _currentFile != null ? _play : null,
                            icon: const Icon(Icons.play_arrow),
                            tooltip: '播放',
                          ),
                          IconButton.filled(
                            onPressed: _currentFile != null ? _pause : null,
                            icon: const Icon(Icons.pause),
                            tooltip: '暂停',
                          ),
                          IconButton.filled(
                            onPressed: _currentFile != null ? _stop : null,
                            icon: const Icon(Icons.stop),
                            tooltip: '停止',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 音量和速度控制
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '音效控制',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 音量控制
                      Row(
                        children: [
                          const Icon(Icons.volume_down),
                          Expanded(
                            child: Slider(
                              value: _volume,
                              onChanged: _currentFile != null
                                  ? _setVolume
                                  : null,
                              min: 0.0,
                              max: 1.0,
                              divisions: 10,
                              label: '${(_volume * 100).round()}%',
                            ),
                          ),
                          const Icon(Icons.volume_up),
                        ],
                      ),

                      // 播放速度控制
                      Row(
                        children: [
                          const Text('0.5x'),
                          Expanded(
                            child: Slider(
                              value: _speed,
                              onChanged: _currentFile != null
                                  ? _setSpeed
                                  : null,
                              min: 0.5,
                              max: 2.0,
                              divisions: 15,
                              label: '${_speed}x',
                            ),
                          ),
                          const Text('2.0x'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // API 使用说明
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'API 使用示例',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '// 初始化播放器\n'
                        'await PlayMidifile.instance.initialize();\n\n'
                        '// 加载文件\n'
                        'await PlayMidifile.instance.loadFile(filePath);\n'
                        'await PlayMidifile.instance.loadAsset(assetPath);\n\n'
                        '// 播放控制\n'
                        'await PlayMidifile.instance.play();\n'
                        'await PlayMidifile.instance.pause();\n'
                        'await PlayMidifile.instance.stop();\n'
                        'await PlayMidifile.instance.seekTo(positionMs);\n\n'
                        '// 设置参数\n'
                        'await PlayMidifile.instance.setVolume(0.8);\n'
                        'await PlayMidifile.instance.setSpeed(1.5);',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getStateText(MidiPlayerState state) {
    switch (state) {
      case MidiPlayerState.stopped:
        return '已停止';
      case MidiPlayerState.playing:
        return '播放中';
      case MidiPlayerState.paused:
        return '已暂停';
      case MidiPlayerState.error:
        return '错误';
    }
  }

  Color _getStateColor(MidiPlayerState state) {
    switch (state) {
      case MidiPlayerState.stopped:
        return Colors.grey;
      case MidiPlayerState.playing:
        return Colors.green;
      case MidiPlayerState.paused:
        return Colors.orange;
      case MidiPlayerState.error:
        return Colors.red;
    }
  }
}
