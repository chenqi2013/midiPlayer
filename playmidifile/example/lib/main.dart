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

  String? _currentFile;
  String _statusMessage = '未初始化';
  bool _isInitialized = false;

  // 添加播放进度相关状态
  MidiPlaybackInfo? _playbackInfo;
  StreamSubscription<MidiPlaybackInfo>? _progressSubscription;
  Timer? _progressTimer; // 添加定时器用于定期更新进度
  bool _isPlaying = false; // 添加播放状态跟踪
  StreamSubscription<MidiPlayerState>? _stateSubscription; // 添加状态监听器

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void dispose() {
    // 取消流订阅
    _progressSubscription?.cancel();
    _stateSubscription?.cancel(); // 取消状态监听器
    // 取消定时器
    _progressTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    try {
      await _player.initialize();

      // 监听播放进度变化
      _progressSubscription = _player.onProgressChanged.listen((info) {
        setState(() {
          _playbackInfo = info;
        });
      });

      // 监听播放状态变化（主要用于错误处理）
      _stateSubscription = _player.onStateChanged.listen((state) {
        // 只处理错误状态
        if (state == MidiPlayerState.error) {
          setState(() {
            _isPlaying = false;
            _statusMessage = '播放错误';
          });
        }
      });

      setState(() {
        _isInitialized = true;
        _statusMessage = '初始化成功';
      });
    } catch (e) {
      setState(() {
        _statusMessage = '初始化失败: $e';
      });
    }
  }

  // 启动进度更新定时器
  void _startProgressTimer() {
    _progressTimer?.cancel(); // 先取消现有的定时器
    _progressTimer = Timer.periodic(const Duration(milliseconds: 200), (
      timer,
    ) async {
      if (_currentFile != null) {
        try {
          final info = await _player.getCurrentInfo();
          if (mounted && info != null) {
            // 确保进度值在有效范围内
            final validProgress = info.progress.clamp(0.0, 1.0);
            final validInfo = MidiPlaybackInfo(
              currentPositionMs: info.currentPositionMs.clamp(
                0,
                info.durationMs,
              ),
              durationMs: info.durationMs,
              progress: validProgress,
            );

            setState(() {
              _playbackInfo = validInfo;
            });

            // 检测播放完成（进度达到100%或接近100%）
            if (_isPlaying && validProgress >= 0.99) {
              _handlePlaybackComplete();
            }
          }
        } catch (e) {
          // 忽略获取进度信息时的错误
        }
      }
    });
  }

  // 处理播放完成
  void _handlePlaybackComplete() {
    _stopProgressTimer();
    setState(() {
      _isPlaying = false;
      _statusMessage = '播放完成';
      // 重置进度条到0位置
      if (_playbackInfo != null) {
        _playbackInfo = MidiPlaybackInfo(
          currentPositionMs: 0,
          durationMs: _playbackInfo!.durationMs,
          progress: 0.0,
        );
      }
    });
  }

  // 停止进度更新定时器
  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  Future<void> _loadAssetFile() async {
    try {
      setState(() {
        _statusMessage = '正在加载资源文件...';
      });

      final success = await _player.loadAsset('assets/demo.mid');

      if (success) {
        // 加载成功后获取播放信息，这样就能显示进度条
        final info = await _player.getCurrentInfo();
        setState(() {
          _currentFile = 'demo.mid (资源文件)';
          _statusMessage = '资源文件加载成功';
          _playbackInfo = info; // 设置播放信息，让进度条显示
        });
      } else {
        setState(() {
          _statusMessage = '资源文件加载失败';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = '加载资源文件失败: $e';
      });
    }
  }

  Future<void> _play() async {
    if (_currentFile == null) {
      _showMessage('请先加载文件');
      return;
    }

    try {
      await _player.play();
      _startProgressTimer(); // 开始播放时启动进度定时器
      // 手动设置状态，确保按钮立即更新
      setState(() {
        _isPlaying = true;
        _statusMessage = '播放中';
      });
    } catch (e) {
      setState(() {
        _statusMessage = '播放失败: $e';
      });
    }
  }

  Future<void> _pause() async {
    try {
      await _player.pause();
      _stopProgressTimer(); // 暂停时停止进度定时器
      // 手动设置状态，确保按钮立即更新
      setState(() {
        _isPlaying = false;
        _statusMessage = '已暂停';
      });
    } catch (e) {
      setState(() {
        _statusMessage = '暂停失败: $e';
      });
    }
  }

  Future<void> _stop() async {
    try {
      await _player.stop();
      _stopProgressTimer(); // 停止时停止进度定时器

      // 手动设置状态和重置进度条，确保立即更新
      setState(() {
        _isPlaying = false;
        _statusMessage = '已停止';
        // 重置进度条到0位置
        if (_playbackInfo != null) {
          _playbackInfo = MidiPlaybackInfo(
            currentPositionMs: 0,
            durationMs: _playbackInfo!.durationMs,
            progress: 0.0,
          );
        }
      });
    } catch (e) {
      setState(() {
        _statusMessage = '停止失败: $e';
      });
    }
  }

  // 切换播放/暂停状态
  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _pause();
    } else {
      await _play();
    }
  }

  Future<void> _getCurrentInfo() async {
    try {
      final info = await _player.getCurrentInfo();
      if (info != null) {
        setState(() {
          _statusMessage =
              '当前位置: ${info.currentPositionMs}ms / ${info.durationMs}ms (${(info.progress * 100).toStringAsFixed(1)}%)';
        });
      } else {
        setState(() {
          _statusMessage = '无法获取播放信息';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = '获取播放信息失败: $e';
      });
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
              // 状态显示区域
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '状态信息',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('初始化状态: ${_isInitialized ? "已初始化" : "未初始化"}'),
                      const SizedBox(height: 8),
                      Text('当前文件: ${_currentFile ?? "无"}'),
                      const SizedBox(height: 8),
                      Text('状态: $_statusMessage'),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

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
                      ElevatedButton.icon(
                        onPressed: _isInitialized ? _loadAssetFile : null,
                        icon: const Icon(Icons.library_music),
                        label: const Text('加载示例文件 (demo.mid)'),
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

                      // 播放进度条
                      if (_currentFile != null) ...[
                        Row(
                          children: [
                            // 当前时间
                            Text(
                              _playbackInfo != null
                                  ? _formatDuration(
                                      _playbackInfo!.currentPositionMs,
                                    )
                                  : '0:00',
                              style: const TextStyle(fontSize: 12),
                            ),
                            // 进度条
                            Expanded(
                              child: Slider(
                                value: (_playbackInfo?.progress ?? 0.0).clamp(
                                  0.0,
                                  1.0,
                                ),
                                onChanged:
                                    _currentFile != null &&
                                        _playbackInfo != null
                                    ? (value) async {
                                        try {
                                          final positionMs =
                                              (value *
                                                      _playbackInfo!.durationMs)
                                                  .round();
                                          await _player.seekTo(positionMs);
                                        } catch (e) {
                                          setState(() {
                                            _statusMessage = '跳转失败: $e';
                                          });
                                        }
                                      }
                                    : null,
                                min: 0.0,
                                max: 1.0,
                              ),
                            ),
                            // 总时间
                            Text(
                              _playbackInfo != null
                                  ? _formatDuration(_playbackInfo!.durationMs)
                                  : '0:00',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 控制按钮
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // 播放/暂停切换按钮
                          IconButton.filled(
                            onPressed: _currentFile != null
                                ? _togglePlayPause
                                : null,
                            icon: Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                            ),
                            tooltip: _isPlaying ? '暂停' : '播放',
                          ),
                          IconButton.filled(
                            onPressed: _currentFile != null ? _stop : null,
                            icon: const Icon(Icons.stop),
                            tooltip: '停止',
                          ),
                          IconButton.filled(
                            onPressed: _currentFile != null
                                ? _getCurrentInfo
                                : null,
                            icon: const Icon(Icons.info),
                            tooltip: '获取信息',
                          ),
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
                        'await PlayMidifile.instance.stop();\n\n'
                        '// 获取播放信息\n'
                        'final info = await PlayMidifile.instance.getCurrentInfo();',
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

  // 格式化时间显示
  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
