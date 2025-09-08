import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:rise_together/src/ui/overlay.dart';
import 'package:rise_together/src/game/rise_together_game.dart';
import 'package:rise_together/src/services/network_coordinator.dart';
import 'package:rise_together/src/services/log_service.dart';

class CoordinationUI extends StatelessWidget
    with AppLogging
    implements RiseTogetherOverlay {
  static final String overlayID = 'Coordination';
  final RiseTogetherGame game;
  final NetworkCoordinator networkCoordinator;

  CoordinationUI(this.game, this.networkCoordinator, {super.key});

  @override
  Widget build(BuildContext context) {
    appLog.info('Building Coordination overlay');
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    // TODO: Move popover menus to consistent base class.
    final isWideScreen = screenWidth / screenHeight > 1.5;

    // Use responsive sizing for wider screens
    final horizontalMargin = isWideScreen
        ? screenWidth * 0.15
        : screenWidth * 0.1;
    final verticalMargin = screenHeight * 0.08;

    return Container(
      width: screenWidth,
      height: screenHeight,
      color: Color.fromARGB(200, 0, 0, 0), // Semi-transparent background
      child: Stack(
        children: [
          // Main content
          Positioned(
            top: verticalMargin,
            left: horizontalMargin,
            right: horizontalMargin,
            bottom: verticalMargin,
            child: Container(
              decoration: BoxDecoration(
                color: Color.fromARGB(240, 20, 20, 20),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: Color.fromARGB(100, 150, 0, 255),
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  //_buildHeader(context),
                  Expanded(child: _buildContent(context)),
                  // _buildFooter(context),
                ],
              ),
            ),
          ),

          // Close button
          Positioned(
            top: verticalMargin - 20,
            right: horizontalMargin - 20,
            child: _buildCloseButton(context),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: networkCoordinator,
      child: Consumer<NetworkCoordinator>(
        builder: (context, coordinator, child) {
          return Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (coordinator.isCoordinator) ...[
                  _buildCoordinatorControls(coordinator),
                  SizedBox(height: 20),
                ],
                Expanded(
                  child: coordinator.connectedNodes.isEmpty
                      ? _buildEmptyState()
                      : _buildNodeList(coordinator),
                ),
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

  Widget _buildNodeList(NetworkCoordinator coordinator) {
    return ListView.builder(
      itemCount: coordinator.connectedNodes.length,
      itemBuilder: (context, index) {
        final node = coordinator.connectedNodes[index];
        final assignment = coordinator.playerAssignments
            .where((a) => a.nodeId == node.uId)
            .firstOrNull;

        return Container(
          margin: EdgeInsets.only(bottom: 12),
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color.fromARGB(100, 50, 50, 50),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: node.uId == coordinator.deviceId
                  ? Color.fromARGB(255, 0, 255, 0)
                  : Color.fromARGB(50, 255, 255, 255),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.name,
                          style: TextStyle(
                            color: Color.fromARGB(255, 255, 255, 255),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'ID: ${node.uId.substring(0, 12)}...',
                          style: TextStyle(
                            color: Color.fromARGB(150, 255, 255, 255),
                            fontSize: 12,
                          ),
                        ),
                        if (assignment != null) ...[
                          SizedBox(height: 5),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: assignment.teamId == 0
                                  ? Color.fromARGB(120, 0, 150, 255)
                                  : Color.fromARGB(120, 255, 100, 0),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Currently on Team ${assignment.teamId + 1}',
                              style: TextStyle(
                                color: assignment.teamId == 0
                                    ? Color.fromARGB(255, 100, 200, 255)
                                    : Color.fromARGB(255, 255, 150, 50),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ] else ...[
                          SizedBox(height: 5),
                          Text(
                            'Unassigned',
                            style: TextStyle(
                              color: Color.fromARGB(150, 255, 255, 255),
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (node.uId == coordinator.deviceId)
                    Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      color: Color.fromARGB(255, 0, 255, 0),
                      size: 24,
                    ),
                ],
              ),
              if (coordinator.isCoordinator &&
                  node.uId != coordinator.deviceId) ...[
                SizedBox(height: 12),
                _buildTeamAssignmentButtons(coordinator, node.uId),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTeamAssignmentButtons(
    NetworkCoordinator coordinator,
    String nodeId,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Assign to team:',
          style: TextStyle(
            color: Color.fromARGB(180, 255, 255, 255),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildTeamButton(coordinator, nodeId, 0, 'Team 1')),
            SizedBox(width: 12),
            Expanded(child: _buildTeamButton(coordinator, nodeId, 1, 'Team 2')),
            SizedBox(width: 12),
            Expanded(child: _buildUnassignButton(coordinator, nodeId)),
          ],
        ),
      ],
    );
  }

  Widget _buildTeamButton(
    NetworkCoordinator coordinator,
    String nodeId,
    int teamId,
    String label,
  ) {
    final assignment = coordinator.playerAssignments
        .where((a) => a.nodeId == nodeId)
        .firstOrNull;
    final isAssigned = assignment?.teamId == teamId;

    return GestureDetector(
      onTap: () {
        appLog.info('UI: Assigning node $nodeId to team $teamId');
        coordinator.assignNodeToTeam(nodeId, teamId);
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: isAssigned
              ? (teamId == 0
                    ? Color.fromARGB(255, 0, 150, 255)
                    : Color.fromARGB(255, 255, 100, 0))
              : Color.fromARGB(80, 60, 60, 60),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isAssigned
                ? (teamId == 0
                      ? Color.fromARGB(255, 100, 200, 255)
                      : Color.fromARGB(255, 255, 150, 50))
                : Color.fromARGB(80, 120, 120, 120),
            width: isAssigned ? 2 : 1,
          ),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isAssigned) ...[
                Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  color: Color.fromARGB(255, 255, 255, 255),
                  size: 16,
                ),
                SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: Color.fromARGB(255, 255, 255, 255),
                  fontSize: 13,
                  fontWeight: isAssigned ? FontWeight.bold : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnassignButton(NetworkCoordinator coordinator, String nodeId) {
    final hasAssignment = coordinator.playerAssignments.any(
      (a) => a.nodeId == nodeId,
    );

    return GestureDetector(
      onTap: hasAssignment
          ? () {
              appLog.info('UI: Unassigning node $nodeId');
              coordinator.unassignNode(nodeId);
            }
          : null,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: hasAssignment
              ? Color.fromARGB(120, 200, 80, 80)
              : Color.fromARGB(50, 100, 100, 100),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasAssignment
                ? Color.fromARGB(150, 255, 120, 120)
                : Color.fromARGB(50, 150, 150, 150),
            width: hasAssignment ? 2 : 1,
          ),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.clear_circled,
                color: hasAssignment
                    ? Color.fromARGB(255, 255, 255, 255)
                    : Color.fromARGB(120, 255, 255, 255),
                size: 16,
              ),
              SizedBox(width: 6),
              Text(
                'Clear',
                style: TextStyle(
                  color: hasAssignment
                      ? Color.fromARGB(255, 255, 255, 255)
                      : Color.fromARGB(120, 255, 255, 255),
                  fontSize: 13,
                  fontWeight: hasAssignment ? FontWeight.bold : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoordinatorControls(NetworkCoordinator coordinator) {
    final assignedCount = coordinator.playerAssignments.length;
    final totalNodes = coordinator.connectedNodes.length;

    // Debug assignment info
    appLog.info('UI: Found $assignedCount assignments for $totalNodes nodes');
    for (final assignment in coordinator.playerAssignments) {
      appLog.info(
        '  - Node ${assignment.nodeId} -> Team ${assignment.teamId + 1}',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Coordinator Controls',
                style: TextStyle(
                  color: Color.fromARGB(255, 255, 255, 255),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: assignedCount > 0
                    ? Color.fromARGB(150, 0, 150, 0)
                    : Color.fromARGB(150, 150, 150, 0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$assignedCount/$totalNodes assigned',
                style: TextStyle(
                  color: Color.fromARGB(255, 255, 255, 255),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        //_buildConfigurationStatus(coordinator),
      ],
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
