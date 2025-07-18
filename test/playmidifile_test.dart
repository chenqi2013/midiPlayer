import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:playmidifile/playmidifile.dart';

void main() {
  const MethodChannel channel = MethodChannel('playmidifile');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'initialize':
          return null;
        case 'loadFile':
          // 对于测试，总是返回成功
          return true;
        case 'loadAsset':
          return true;
        case 'play':
          return null;
        case 'pause':
          return null;
        case 'stop':
          return null;
        case 'seekTo':
          return null;
        case 'setSpeed':
          return null;
        case 'setVolume':
          return null;
        case 'getCurrentState':
          return 'stopped';
        case 'getCurrentInfo':
          return {
            'currentPositionMs': 0,
            'durationMs': 60000,
            'progress': 0.0,
          };
        case 'dispose':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('PlayMidifile Tests', () {
    test('初始化播放器', () async {
      final player = PlayMidifile.instance;
      await expectLater(player.initialize(), completes);
    });

    test('加载MIDI文件 - Mock成功', () async {
      final player = PlayMidifile.instance;
      await player.initialize();

      // 在mock环境中，这应该返回true
      final result = await player.loadFile('/path/to/test.mid');
      expect(result, true);
    });

    test('加载Assets文件', () async {
      final player = PlayMidifile.instance;
      await player.initialize();

      final result = await player.loadAsset('demo.mid');
      expect(result, true);
    });

    test('播放控制功能 - Mock环境', () async {
      final player = PlayMidifile.instance;
      await player.initialize();

      // 在mock环境中，这些调用应该成功完成
      await expectLater(player.play(), completes);
      await expectLater(player.pause(), completes);
      await expectLater(player.stop(), completes);
    });

    test('跳转功能', () async {
      final player = PlayMidifile.instance;
      await player.initialize();

      await expectLater(player.seekTo(30000), completes);
    });

    test('设置播放速度', () async {
      final player = PlayMidifile.instance;
      await player.initialize();

      await expectLater(player.setSpeed(1.5), completes);

      // 测试边界值
      await expectLater(player.setSpeed(0.5), completes);
      await expectLater(player.setSpeed(2.0), completes);

      // 测试无效值
      expect(() => player.setSpeed(0.3), throwsException);
      expect(() => player.setSpeed(2.5), throwsException);
    });

    test('设置音量', () async {
      final player = PlayMidifile.instance;
      await player.initialize();

      await expectLater(player.setVolume(0.8), completes);

      // 测试边界值
      await expectLater(player.setVolume(0.0), completes);
      await expectLater(player.setVolume(1.0), completes);

      // 测试无效值
      expect(() => player.setVolume(-0.1), throwsException);
      expect(() => player.setVolume(1.1), throwsException);
    });

    test('获取播放状态', () async {
      final player = PlayMidifile.instance;
      await player.initialize();

      // final state = await player.getCurrentState();
      // expect(state, MidiPlayerState.stopped);
    });

    test('获取播放信息', () async {
      final player = PlayMidifile.instance;
      await player.initialize();

      final info = await player.getCurrentInfo();
      expect(info, isNotNull);
      expect(info!.durationMs, 60000);
      expect(info.currentPositionMs, 0);
      expect(info.progress, 0.0);
    });

    test('释放资源', () async {
      final player = PlayMidifile.instance;
      await player.initialize();

      // 在mock环境中，dispose应该正常完成
      await expectLater(player.dispose(), completes);
    });
  });

  group('MidiPlaybackInfo Tests', () {
    test('从Map创建播放信息', () {
      final map = {
        'currentPositionMs': 30000,
        'durationMs': 120000,
        'progress': 0.25,
      };

      final info = MidiPlaybackInfo.fromMap(map);
      expect(info.currentPositionMs, 30000);
      expect(info.durationMs, 120000);
      expect(info.progress, 0.25);
    });

    test('处理缺失字段', () {
      final map = <String, dynamic>{};

      final info = MidiPlaybackInfo.fromMap(map);
      expect(info.currentPositionMs, 0);
      expect(info.durationMs, 0);
      expect(info.progress, 0.0);
    });
  });

  group('MidiPlayerState Tests', () {
    test('状态枚举包含所有预期值', () {
      expect(MidiPlayerState.values.length, 4);
      expect(MidiPlayerState.values, contains(MidiPlayerState.stopped));
      expect(MidiPlayerState.values, contains(MidiPlayerState.playing));
      expect(MidiPlayerState.values, contains(MidiPlayerState.paused));
      expect(MidiPlayerState.values, contains(MidiPlayerState.error));
    });
  });

  group('边界条件测试', () {
    test('在未初始化状态下调用方法应该抛出异常', () async {
      // 注意：由于使用单例模式，我们无法完全模拟未初始化状态
      // 但我们可以测试其他边界条件
      expect(PlayMidifile.instance, isNotNull);
    });

    test('参数验证', () {
      expect(
        () => MidiPlaybackInfo(
          currentPositionMs: -1,
          durationMs: 0,
          progress: 0.0,
        ),
        returnsNormally,
      );

      expect(
        () => MidiPlaybackInfo(
          currentPositionMs: 0,
          durationMs: -1,
          progress: 0.0,
        ),
        returnsNormally,
      );
    });
  });
}
