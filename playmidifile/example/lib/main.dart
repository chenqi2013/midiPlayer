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

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    try {
      await _player.initialize();
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

  Future<void> _loadAssetFile() async {
    try {
      setState(() {
        _statusMessage = '正在加载资源文件...';
      });

      final success = await _player.loadAsset('assets/demo.mid');

      if (success) {
        setState(() {
          _currentFile = 'demo.mid (资源文件)';
          _statusMessage = '资源文件加载成功';
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
      setState(() {
        _statusMessage = '开始播放';
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
      setState(() {
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
      setState(() {
        _statusMessage = '已停止';
      });
    } catch (e) {
      setState(() {
        _statusMessage = '停止失败: $e';
      });
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
}
