// lib/services/lsl_service.dart
import 'dart:async';
import 'package:liblsl/lsl.dart';
import 'package:rise_together/src/services/log_service.dart';
import '../models/game_state.dart';

class LSLService with AppLogging {
  // Stream types
  static const String kPlayerInputStreamType = 'PlayerInput';
  static const String kTeamStateStreamType = 'TeamState';

  // Local participant info
  final String participantId;
  final String teamId;

  // LSL outlets - data we send
  late LSLStreamInfo _playerInputStreamInfo;
  late LSLOutlet _playerInputOutlet;

  late LSLStreamInfo _teamStateStreamInfo;
  late LSLOutlet _teamStateOutlet;

  // LSL inlets - data we receive
  final Map<String, LSLInlet> _remoteTeamInlets = {};

  // Stream controllers for app-wide events
  final _remoteTeamStateController = StreamController<TeamState>.broadcast();
  Stream<TeamState> get remoteTeamStateStream =>
      _remoteTeamStateController.stream;

  final _remotePlayerInputController = StreamController<String>.broadcast();
  Stream<String> get remotePlayerInputStream =>
      _remotePlayerInputController.stream;

  LSLService({required this.participantId, required this.teamId});

  Future<void> initialize() async {
    // Create streams for player input
    _playerInputStreamInfo = await LSL.createStreamInfo(
      streamName: '$kPlayerInputStreamType-$participantId',
      streamType: LSLContentType.markers,
      channelFormat: LSLChannelFormat.string, // "left", "right", "none"
      channelCount: 1,
      sampleRate: LSL_IRREGULAR_RATE,
      sourceId: '$teamId-$participantId-player',
    );
    _playerInputOutlet = await LSL.createOutlet(
      streamInfo: _playerInputStreamInfo,
    );

    // Create streams for team state
    _teamStateStreamInfo = await LSL.createStreamInfo(
      streamName: '$kTeamStateStreamType-$teamId',
      streamType: LSLContentType.markers,
      channelFormat: LSLChannelFormat.string, // JSON encoded team state
      channelCount: 1,
      sampleRate: LSL_IRREGULAR_RATE,
      sourceId: '$teamId-$participantId-team',
    );
    _teamStateOutlet = await LSL.createOutlet(streamInfo: _teamStateStreamInfo);

    // Push initial discovery data
    await _pushDiscoveryData();

    // Start looking for remote team streams
    _startDiscoveryTimer();
  }

  Future<void> _pushDiscoveryData() async {
    for (int i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      _playerInputOutlet.pushSample(["discovery"]);
      _teamStateOutlet.pushSample(["discovery"]);
    }
  }

  void _startDiscoveryTimer() {
    Timer.periodic(const Duration(seconds: 5), (_) async {
      await _discoverRemoteTeams();
    });
    // Run discovery immediately
    _discoverRemoteTeams();
  }

  Future<void> _discoverRemoteTeams() async {
    try {
      final List<LSLStreamInfo> streams = await LSL.resolveStreams(
        waitTime: 2.0,
        maxStreams: 10,
      );

      for (final stream in streams) {
        // Only look for team state streams that aren't our own team
        if (!stream.sourceId.startsWith(teamId) &&
            !_remoteTeamInlets.containsKey(stream.sourceId)) {
          appLog.info('Found remote team stream: ${stream.streamName}');

          final inlet = await LSL.createInlet(streamInfo: stream);
          _remoteTeamInlets[stream.sourceId] = inlet;

          // Start polling this inlet
          if (stream.streamName.startsWith(kPlayerInputStreamType)) {
            _startPollingInlet(stream.streamName, inlet, (LSLSample s) async {
              final input = s[0] as String;
              _remotePlayerInputController.add(input);
            });
          } else if (stream.streamName.startsWith(kTeamStateStreamType)) {
            _startPollingInlet(stream.streamName, inlet, (LSLSample s) async {
              final teamState = TeamState.decode(s[0]);
              _remoteTeamStateController.add(teamState);
            });
          } else {
            appLog.warning('Unknown stream type: ${stream.streamName}');
          }
        }
      }
    } catch (e) {
      appLog.severe('Error discovering remote teams: $e');
    }
  }

  void _startPollingInlet(
    String streamName,
    LSLInlet inlet,
    Future<void> Function(LSLSample s) consume,
  ) {
    Timer.periodic(const Duration(milliseconds: 1), (timer) async {
      try {
        final sample = await inlet.pullSample();
        if (sample.timestamp != 0) {
          consume(sample);
        }
      } catch (e) {
        appLog.warning('Error pulling sample from $streamName: $e');
      }
    });
  }

  void sendPlayerInput(String input) {
    try {
      _playerInputOutlet.pushSample([input]);
    } catch (e) {
      appLog.severe('Error sending player input: $e');
    }
  }

  void sendTeamState(TeamState state) {
    try {
      _teamStateOutlet.pushSample([state.encode()]);
    } catch (e) {
      appLog.severe('Error sending team state: $e');
    }
  }

  void dispose() {
    _playerInputOutlet.destroy();
    _teamStateOutlet.destroy();
    _playerInputStreamInfo.destroy();
    _teamStateStreamInfo.destroy();

    for (final inlet in _remoteTeamInlets.values) {
      inlet.destroy();
    }

    _remoteTeamStateController.close();
  }
}
