// lib/services/lsl_service.dart
import 'dart:async';
import 'package:liblsl/lsl.dart';
import 'package:logging/logging.dart';
import '../models/game_state.dart';
// ignore: implementation_imports @TODO: export this in the library
import 'package:liblsl/src/lsl/isolated_outlet.dart' show LSLIsolatedOutlet;
// ignore: implementation_imports @TODO: export this in the library
import 'package:liblsl/src/lsl/isolated_inlet.dart' show LSLIsolatedInlet;

class LSLService {
  static final Logger _log = Logger('LSLService');

  // Stream types
  static const String kPlayerInputStreamType = 'PlayerInput';
  static const String kTeamStateStreamType = 'TeamState';

  // Local participant info
  final String participantId;
  final String teamId;

  // LSL outlets - data we send
  late LSLStreamInfo _playerInputStreamInfo;
  late LSLIsolatedOutlet _playerInputOutlet;

  late LSLStreamInfo _teamStateStreamInfo;
  late LSLIsolatedOutlet _teamStateOutlet;

  // LSL inlets - data we receive
  Map<String, LSLIsolatedInlet> _remoteTeamInlets = {};

  // Stream controllers for app-wide events
  final _remoteTeamStateController = StreamController<TeamState>.broadcast();
  Stream<TeamState> get remoteTeamStateStream =>
      _remoteTeamStateController.stream;

  LSLService({required this.participantId, required this.teamId});

  Future<void> initialize() async {
    // Create streams for player input
    _playerInputStreamInfo = await LSL.createStreamInfo(
      streamName: '$kPlayerInputStreamType-$participantId',
      streamType: LSLContentType.markers,
      channelFormat: LSLChannelFormat.string, // "left", "right", "none"
      channelCount: 1,
      sampleRate: LSL_IRREGULAR_RATE,
      sourceId: 'player-$participantId-$teamId',
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
      sourceId: 'team-$teamId-$participantId-$teamId',
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
        if (stream.streamType == kTeamStateStreamType &&
            !stream.streamName.contains(teamId) &&
            !_remoteTeamInlets.containsKey(stream.streamName)) {
          _log.info('Found remote team stream: ${stream.streamName}');

          final inlet = await LSL.createInlet(streamInfo: stream);
          _remoteTeamInlets[stream.streamName] = inlet;

          // Start polling this inlet
          _startPollingInlet(stream.streamName, inlet);
        }
      }
    } catch (e) {
      _log.severe('Error discovering remote teams: $e');
    }
  }

  void _startPollingInlet(String streamName, LSLIsolatedInlet inlet) {
    Timer.periodic(const Duration(milliseconds: 50), (timer) async {
      try {
        final sample = await inlet.pullSample();
        if (sample.isNotEmpty &&
            sample[0] is String &&
            sample[0] != "discovery") {
          final teamState = TeamState.decode(sample[0]);
          _remoteTeamStateController.add(teamState);
        }
      } catch (e) {
        _log.warning('Error pulling sample from $streamName: $e');
      }
    });
  }

  void sendPlayerInput(String input) {
    try {
      _playerInputOutlet.pushSample([input]);
    } catch (e) {
      _log.severe('Error sending player input: $e');
    }
  }

  void sendTeamState(TeamState state) {
    try {
      _teamStateOutlet.pushSample([state.encode()]);
    } catch (e) {
      _log.severe('Error sending team state: $e');
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
