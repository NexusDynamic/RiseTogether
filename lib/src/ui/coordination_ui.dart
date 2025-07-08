import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:rise_together/src/ui/overlay.dart';
import 'package:rise_together/src/game/rise_together_game.dart';
import 'package:rise_together/src/services/coordination_manager.dart';
import 'package:rise_together/src/services/log_service.dart';

class CoordinationUI extends StatelessWidget
    with AppLogging
    implements RiseTogetherOverlay {
  static final String overlayID = 'Coordination';
  final RiseTogetherGame game;
  final CoordinationManager coordinationManager;

  CoordinationUI(this.game, this.coordinationManager, {super.key});

  @override
  Widget build(BuildContext context) {
    appLog.info('Building Coordination overlay');
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      width: screenWidth,
      height: screenHeight,
      color: Color.fromARGB(200, 0, 0, 0), // Semi-transparent background
      child: Stack(
        children: [
          // Main content
          Positioned(
            top: screenHeight * 0.1,
            left: screenWidth * 0.1,
            right: screenWidth * 0.1,
            bottom: screenHeight * 0.1,
            child: Container(
              decoration: BoxDecoration(
                color: Color.fromARGB(240, 20, 20, 20),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Color.fromARGB(100, 150, 0, 255),
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  _buildHeader(context),
                  Expanded(child: _buildContent(context)),
                  _buildFooter(context),
                ],
              ),
            ),
          ),
          
          // Close button
          Positioned(
            top: screenHeight * 0.08,
            right: screenWidth * 0.08,
            child: _buildCloseButton(context),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            'Network Coordination',
            style: TextStyle(
              color: Color.fromARGB(255, 255, 255, 255),
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 10),
          ChangeNotifierProvider.value(
            value: coordinationManager,
            child: Consumer<CoordinationManager>(
              builder: (context, manager, child) {
                return Text(
                  'Status: ${manager.isCoordinator ? "Coordinator" : "Participant"} | '
                  'Nodes: ${manager.connectedNodes.length}',
                  style: TextStyle(
                    color: Color.fromARGB(200, 255, 255, 255),
                    fontSize: 16,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: coordinationManager,
      child: Consumer<CoordinationManager>(
        builder: (context, manager, child) {
          return Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connected Nodes:',
                  style: TextStyle(
                    color: Color.fromARGB(255, 255, 255, 255),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 15),
                Expanded(
                  child: manager.connectedNodes.isEmpty
                    ? _buildEmptyState()
                    : _buildNodeList(manager),
                ),
                if (manager.isCoordinator) ...[
                  SizedBox(height: 20),
                  _buildCoordinatorControls(manager),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.wifi_slash,
            color: Color.fromARGB(150, 255, 255, 255),
            size: 48,
          ),
          SizedBox(height: 15),
          Text(
            'No other nodes discovered',
            style: TextStyle(
              color: Color.fromARGB(150, 255, 255, 255),
              fontSize: 16,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Make sure other devices are running RiseTogether\non the same network',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color.fromARGB(100, 255, 255, 255),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeList(CoordinationManager manager) {
    return ListView.builder(
      itemCount: manager.connectedNodes.length,
      itemBuilder: (context, index) {
        final node = manager.connectedNodes[index];
        final assignment = manager.playerAssignments
            .where((a) => a.nodeId == node.nodeId)
            .firstOrNull;
        
        return Container(
          margin: EdgeInsets.only(bottom: 10),
          padding: EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Color.fromARGB(100, 50, 50, 50),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: node.nodeId == manager.deviceId
                ? Color.fromARGB(255, 0, 255, 0)
                : Color.fromARGB(50, 255, 255, 255),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.nodeName,
                      style: TextStyle(
                        color: Color.fromARGB(255, 255, 255, 255),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'ID: ${node.nodeId.substring(0, 12)}...',
                      style: TextStyle(
                        color: Color.fromARGB(150, 255, 255, 255),
                        fontSize: 12,
                      ),
                    ),
                    if (assignment != null) ...[
                      SizedBox(height: 5),
                      Text(
                        'Team ${assignment.teamId + 1}',
                        style: TextStyle(
                          color: assignment.teamId == 0
                            ? Color.fromARGB(255, 0, 150, 255)
                            : Color.fromARGB(255, 255, 100, 0),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (node.nodeId == manager.deviceId)
                Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  color: Color.fromARGB(255, 0, 255, 0),
                  size: 24,
                ),
              if (manager.isCoordinator && node.nodeId != manager.deviceId) ...[
                SizedBox(width: 10),
                _buildTeamAssignmentButtons(manager, node.nodeId),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTeamAssignmentButtons(CoordinationManager manager, String nodeId) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTeamButton(manager, nodeId, 0, 'Team 1'),
        SizedBox(width: 5),
        _buildTeamButton(manager, nodeId, 1, 'Team 2'),
      ],
    );
  }

  Widget _buildTeamButton(CoordinationManager manager, String nodeId, int teamId, String label) {
    final isAssigned = manager.playerAssignments
        .any((a) => a.nodeId == nodeId && a.teamId == teamId);
    
    return GestureDetector(
      onTap: () => manager.assignNodeToTeam(nodeId, teamId),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isAssigned
            ? (teamId == 0 ? Color.fromARGB(255, 0, 150, 255) : Color.fromARGB(255, 255, 100, 0))
            : Color.fromARGB(100, 100, 100, 100),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Color.fromARGB(255, 255, 255, 255),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildCoordinatorControls(CoordinationManager manager) {
    return Container(
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Color.fromARGB(100, 150, 0, 255),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Coordinator Controls',
            style: TextStyle(
              color: Color.fromARGB(255, 255, 255, 255),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Assign nodes to teams above. Game can start with ${manager.canStartGame() ? "current" : "no"} assignments.',
            style: TextStyle(
              color: Color.fromARGB(200, 255, 255, 255),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: _closeCoordination,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              decoration: BoxDecoration(
                color: Color.fromARGB(255, 100, 100, 100),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Text(
                'Close',
                style: TextStyle(
                  color: Color.fromARGB(255, 255, 255, 255),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloseButton(BuildContext context) {
    return GestureDetector(
      onTap: _closeCoordination,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Color.fromARGB(200, 100, 100, 100),
          shape: BoxShape.circle,
        ),
        child: Icon(
          CupertinoIcons.xmark,
          color: Color.fromARGB(255, 255, 255, 255),
          size: 20,
        ),
      ),
    );
  }

  void _closeCoordination() {
    appLog.info('Closing coordination overlay');
    game.overlays.remove(CoordinationUI.overlayID);
  }
}