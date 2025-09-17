import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:rise_together/src/services/log_service.dart';
import 'package:rise_together/src/services/network_coordinator.dart';
import 'package:rise_together/src/game/rise_together_game.dart';

/// HTTP API controller for headless server mode
class HeadlessApiController with AppLogging {
  final NetworkCoordinator coordinator;
  final RiseTogetherGame game;
  final Function() startGameCallback;
  final Function() stopGameCallback;

  HttpServer? _server;
  int _port = 8080;
  bool _isRunning = false;

  HeadlessApiController({
    required this.coordinator,
    required this.game,
    required this.startGameCallback,
    required this.stopGameCallback,
    int? port,
  }) : _port = port ?? 8080;

  /// Start the HTTP API server
  Future<void> start() async {
    if (_isRunning) return;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      _isRunning = true;

      appLog.info('Headless API server started on port $_port');

      // Handle requests
      _server!.listen(_handleRequest);
    } catch (e) {
      appLog.severe('Failed to start API server: $e');
    }
  }

  void _handleRequest(HttpRequest request) async {
    // Enable CORS for web clients
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add(
      'Access-Control-Allow-Methods',
      'GET, POST, PUT, DELETE, OPTIONS',
    );
    request.response.headers.add(
      'Access-Control-Allow-Headers',
      'Content-Type',
    );

    // Handle OPTIONS for CORS preflight
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;
    final method = request.method;

    appLog.info('API Request: $method $path');

    try {
      switch (path) {
        case '/status':
          await _handleStatus(request);
          break;
        case '/config':
          await _handleConfig(request);
          break;
        case '/players':
          await _handlePlayers(request);
          break;
        case '/teams/assign':
          await _handleTeamAssignment(request);
          break;
        case '/game/start':
          await _handleGameStart(request);
          break;
        case '/game/stop':
          await _handleGameStop(request);
          break;
        case '/game/reset':
          await _handleGameReset(request);
          break;
        case '/level/advance':
          await _handleLevelAdvance(request);
          break;
        default:
          _sendError(request, 'Unknown endpoint: $path', HttpStatus.notFound);
      }
    } catch (e) {
      appLog.severe('Error handling request: $e');
      _sendError(request, 'Internal server error: $e');
    }
  }

  Future<void> _handleStatus(HttpRequest request) async {
    final status = {
      'isCoordinator': coordinator.isCoordinator,
      'gameActive': coordinator.gameActive,
      'gameStarting': coordinator.gameStarting,
      'connectedNodes': coordinator.connectedNodes.length,
      'playerAssignments': coordinator.playerAssignments
          .map(
            (a) => {
              'nodeId': a.nodeId,
              'nodeName': a.nodeName,
              'teamId': a.teamId,
              'playerId': a.playerId,
            },
          )
          .toList(),
      'currentLevel': game.tournamentManager.currentLevel,
      'currentRound': game.tournamentManager.currentRound,
      'timeRemaining': game.timeProvider.timeRemaining,
      'teamDistances': {
        '0': game.distanceTracker.getTeamDistance(0),
        '1': game.distanceTracker.getTeamDistance(1),
      },
    };

    _sendJson(request, status);
  }

  Future<void> _handleConfig(HttpRequest request) async {
    if (request.method == 'GET') {
      final config = coordinator.getGameConfiguration();
      _sendJson(request, config);
    } else if (request.method == 'POST') {
      final body = await _readJsonBody(request);
      if (body != null) {
        coordinator.setGameConfiguration(body);
        _sendSuccess(request, 'Configuration updated');
      } else {
        _sendError(request, 'Invalid JSON body', HttpStatus.badRequest);
      }
    } else {
      _sendError(request, 'Method not allowed', HttpStatus.methodNotAllowed);
    }
  }

  Future<void> _handlePlayers(HttpRequest request) async {
    final players = coordinator.connectedNodes.map((node) {
      final assignment = coordinator.playerAssignments
          .where((a) => a.nodeId == node.uId)
          .firstOrNull;

      return {
        'nodeId': node.uId,
        'nodeName': node.name,
        'teamId': assignment?.teamId,
        'playerId': assignment?.playerId,
        'assigned': assignment != null,
      };
    }).toList();

    _sendJson(request, {'players': players});
  }

  Future<void> _handleTeamAssignment(HttpRequest request) async {
    if (request.method != 'POST') {
      _sendError(request, 'Method not allowed', HttpStatus.methodNotAllowed);
      return;
    }

    final body = await _readJsonBody(request);
    if (body == null) {
      _sendError(request, 'Invalid JSON body', HttpStatus.badRequest);
      return;
    }

    final nodeId = body['nodeId'] as String?;
    final teamId = body['teamId'] as int?;

    if (nodeId == null || teamId == null) {
      _sendError(request, 'Missing nodeId or teamId', HttpStatus.badRequest);
      return;
    }

    try {
      await coordinator.assignNodeToTeam(nodeId, teamId);
      _sendSuccess(request, 'Player assigned to team $teamId');
    } catch (e) {
      _sendError(request, 'Failed to assign player: $e', HttpStatus.badRequest);
    }
  }

  Future<void> _handleGameStart(HttpRequest request) async {
    if (request.method != 'POST') {
      _sendError(request, 'Method not allowed', HttpStatus.methodNotAllowed);
      return;
    }

    if (!coordinator.canStartGame()) {
      _sendError(
        request,
        'Cannot start game: no players assigned',
        HttpStatus.badRequest,
      );
      return;
    }

    startGameCallback();
    _sendSuccess(request, 'Game starting');
  }

  Future<void> _handleGameStop(HttpRequest request) async {
    if (request.method != 'POST') {
      _sendError(request, 'Method not allowed', HttpStatus.methodNotAllowed);
      return;
    }

    stopGameCallback();
    _sendSuccess(request, 'Game stopped');
  }

  Future<void> _handleGameReset(HttpRequest request) async {
    if (request.method != 'POST') {
      _sendError(request, 'Method not allowed', HttpStatus.methodNotAllowed);
      return;
    }

    game.resetGame();
    _sendSuccess(request, 'Game reset');
  }

  Future<void> _handleLevelAdvance(HttpRequest request) async {
    if (request.method != 'POST') {
      _sendError(request, 'Method not allowed', HttpStatus.methodNotAllowed);
      return;
    }

    await game.advanceLevel();
    _sendSuccess(request, 'Advanced to next level');
  }

  Future<Map<String, dynamic>?> _readJsonBody(HttpRequest request) async {
    try {
      final content = await utf8.decoder.bind(request).join();
      if (content.isEmpty) return null;
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      appLog.warning('Failed to parse JSON body: $e');
      return null;
    }
  }

  void _sendJson(HttpRequest request, Map<String, dynamic> data) {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(data));
    request.response.close();
  }

  void _sendSuccess(HttpRequest request, String message) {
    _sendJson(request, {'success': true, 'message': message});
  }

  void _sendError(
    HttpRequest request,
    String message, [
    int statusCode = HttpStatus.internalServerError,
  ]) {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'success': false, 'error': message}));
    request.response.close();
  }

  /// Stop the HTTP API server
  Future<void> stop() async {
    if (!_isRunning) return;

    await _server?.close();
    _server = null;
    _isRunning = false;

    appLog.info('Headless API server stopped');
  }

  void dispose() {
    stop();
  }
}
