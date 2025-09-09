import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, InkWell;
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:rise_together/src/ui/overlay.dart';
import 'package:rise_together/src/game/rise_together_game.dart';
import 'package:rise_together/src/models/team.dart';
import 'package:rise_together/src/attributes/team_color_provider.dart';
import 'package:rise_together/src/services/log_service.dart';
import 'package:rise_together/src/settings/app_settings.dart';

class SettingsUI extends StatefulWidget
    with AppLogging
    implements RiseTogetherOverlay {
  static final String overlayID = 'Settings';
  final RiseTogetherGame game;

  SettingsUI(this.game, {super.key});

  @override
  State<SettingsUI> createState() => _SettingsUIState();
}

class _SettingsUIState extends State<SettingsUI>
    with AppSettings, TeamColorProvider {
  bool _debugMode = true;
  bool _simulatedPlayers = false;
  bool _localOnlyMode = false;
  double _gameScale = 0.0001;
  double _ballRadius = 1.0;
  double _gravity = 9.81;
  double _paddleWidthMultiplier = 1.0;
  double _thrustMultiplier = 1.0;
  double _rotationMultiplier = 1.0;
  double _levelDuration = 120.0;
  double _distanceMultiplier = 100.0;
  int _tournamentRounds = 3;
  int _levelsPerRound = 5;
  bool _enableSurveys = false;

  // Team colors
  Color _teamAColor = CupertinoColors.systemBlue;
  Color _teamBColor = CupertinoColors.systemOrange;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    try {
      _debugMode = appSettings.getBool('game.debug_mode');
      _simulatedPlayers = appSettings.getBool('game.simulated_players');
      _localOnlyMode = appSettings.getBool('game.local_only_mode');
      _gameScale = appSettings.getDouble('game.game_scale');
      _ballRadius = appSettings.getDouble('game.ball_radius');
      _levelDuration = appSettings.getDouble('game.level_duration');
      _distanceMultiplier = appSettings.getDouble('game.distance_multiplier');
      _tournamentRounds = appSettings.getInt('game.tournament_rounds');
      _levelsPerRound = appSettings.getInt('game.levels_per_round');
      _enableSurveys = appSettings.getBool('game.enable_surveys');
      _gravity = appSettings.getDouble('physics.gravity');
      _paddleWidthMultiplier = appSettings.getDouble(
        'physics.paddle_width_multiplier',
      );
      _thrustMultiplier = appSettings.getDouble('physics.thrust_multiplier');
      _rotationMultiplier = appSettings.getDouble('physics.rotation_multiplier');

      // Load team colors
      _teamAColor = Color(appSettings.getInt('colors.team_a_color'));
      _teamBColor = Color(appSettings.getInt('colors.team_b_color'));
    } catch (e) {
      widget.appLog.warning('Could not load settings: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isWideScreen = screenWidth / screenHeight > 1.5;

    // Use responsive sizing for wider screens
    final horizontalMargin = isWideScreen
        ? screenWidth * 0.15
        : screenWidth * 0.1;
    final verticalMargin = screenHeight * 0.08;
    return Container(
      width: screenWidth,
      height: screenHeight,
      color: Color.fromARGB(220, 0, 0, 0), // Semi-transparent background
      child: Stack(
        children: [
          Center(
            child: Container(
              width: screenWidth - horizontalMargin * 2,
              height: screenHeight - verticalMargin * 2,
              decoration: BoxDecoration(
                color: Color.fromARGB(255, 40, 40, 40),
                borderRadius: BorderRadius.circular(5),
                boxShadow: [
                  BoxShadow(
                    color: Color.fromARGB(150, 0, 0, 0),
                    spreadRadius: 4,
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ListView(
                children: [
                  // Header with close button
                  _buildHeader(context),

                  // Settings content
                  _buildSettingsContent(context),
                ],
              ),
            ),
          ),
          Positioned(
            top: verticalMargin - 20,
            right: horizontalMargin - 20,
            child: GestureDetector(
              onTap: _closeSettings,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Color.fromARGB(255, 100, 100, 100),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  CupertinoIcons.xmark,
                  color: Color.fromARGB(255, 255, 255, 255),
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color.fromARGB(255, 60, 60, 60),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Settings',
            style: TextStyle(
              color: Color.fromARGB(255, 255, 255, 255),
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsContent(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Game Settings Section
          _buildSectionHeader('Game Settings'),
          SizedBox(height: 20),

          // Debug Mode Toggle
          _buildBooleanSetting(
            'Debug Mode',
            'Enable debugging features',
            _debugMode,
            (value) {
              setState(() {
                _debugMode = value;
              });
              _saveSetting('game.debug_mode', value);
            },
          ),

          SizedBox(height: 20),

          // Simulated Players Toggle
          _buildBooleanSetting(
            'Simulated Players',
            'Show 4-player controls for demo/presentation',
            _simulatedPlayers,
            (value) {
              setState(() {
                _simulatedPlayers = value;
              });
              _saveSetting('game.simulated_players', value);
            },
          ),

          SizedBox(height: 20),

          // Local-Only Mode Toggle
          _buildBooleanSetting(
            'Enable Local-Only Mode',
            'Run in demo mode without network communication',
            _localOnlyMode,
            (value) {
              setState(() {
                _localOnlyMode = value;
              });
              _saveSetting('game.local_only_mode', value);
            },
          ),

          SizedBox(height: 20),

          // Level Duration Slider
          _buildSliderSetting(
            'Level Duration',
            'Game time limit in seconds',
            _levelDuration,
            5.0,
            600.0,
            (value) {
              setState(() {
                _levelDuration = value;
              });
              _saveSetting('game.level_duration', value);
            },
            suffix: 's',
            decimalPlaces: 0,
          ),

          SizedBox(height: 20),

          // Distance Multiplier Slider
          _buildSliderSetting(
            'Distance Multiplier',
            'Meters per game unit',
            _distanceMultiplier,
            50.0,
            500.0,
            (value) {
              setState(() {
                _distanceMultiplier = value;
              });
              _saveSetting('game.distance_multiplier', value);
            },
            suffix: 'm/unit',
            decimalPlaces: 0,
          ),

          SizedBox(height: 30),

          // Tournament Settings Section
          _buildSectionHeader('Tournament Settings'),
          SizedBox(height: 20),

          // Tournament Rounds Slider
          _buildSliderSetting(
            'Tournament Rounds',
            'Number of rounds in tournament',
            _tournamentRounds.toDouble(),
            1.0,
            10.0,
            (value) {
              setState(() {
                _tournamentRounds = value.round();
              });
              _saveSetting('game.tournament_rounds', _tournamentRounds);
            },
            suffix: ' rounds',
            decimalPlaces: 0,
          ),

          SizedBox(height: 20),

          // Levels Per Round Slider
          _buildSliderSetting(
            'Levels Per Round',
            'Number of levels in each round',
            _levelsPerRound.toDouble(),
            1.0,
            10.0,
            (value) {
              setState(() {
                _levelsPerRound = value.round();
              });
              _saveSetting('game.levels_per_round', _levelsPerRound);
            },
            suffix: ' levels',
            decimalPlaces: 0,
          ),

          SizedBox(height: 20),

          // Enable Surveys Toggle
          _buildBooleanSetting(
            'Enable Surveys',
            'Show surveys between levels (for research)',
            _enableSurveys,
            (value) {
              setState(() {
                _enableSurveys = value;
              });
              _saveSetting('game.enable_surveys', value);
            },
          ),

          SizedBox(height: 30),

          // Physics Settings Section
          _buildSectionHeader('Physics Settings'),
          SizedBox(height: 20),

          // Gravity Slider
          _buildSliderSetting(
            'Gravity',
            'Gravity in m/s²',
            _gravity,
            0.0,
            20.0,
            (value) {
              setState(() {
                _gravity = value;
              });
              _saveSetting('physics.gravity', value);
            },
            suffix: ' m/s²',
            decimalPlaces: 2,
          ),
          SizedBox(height: 20),
          // Paddle Width Multiplier Slider
          _buildSliderSetting(
            'Paddle Width Multiplier',
            'Adjust paddle width',
            _paddleWidthMultiplier,
            0.5,
            2.0,
            (value) {
              setState(() {
                _paddleWidthMultiplier = value;
              });
              _saveSetting('physics.paddle_width_multiplier', value);
            },
            suffix: 'x',
            decimalPlaces: 2,
          ),
          SizedBox(height: 20),

          // Thrust Multiplier Slider
          _buildSliderSetting(
            'Thrust Multiplier',
            'Adjust paddle thrust strength',
            _thrustMultiplier,
            0.1,
            3.0,
            (value) {
              setState(() {
                _thrustMultiplier = value;
              });
              _saveSetting('physics.thrust_multiplier', value);
            },
            suffix: 'x',
            decimalPlaces: 2,
          ),
          SizedBox(height: 20),

          // Rotation Multiplier Slider
          _buildSliderSetting(
            'Rotation Multiplier',
            'Adjust paddle rotation speed',
            _rotationMultiplier,
            0.1,
            3.0,
            (value) {
              setState(() {
                _rotationMultiplier = value;
              });
              _saveSetting('physics.rotation_multiplier', value);
            },
            suffix: 'x',
            decimalPlaces: 2,
          ),
          SizedBox(height: 20),

          // Game Scale Slider
          _buildSliderSetting(
            'Game Scale',
            'Relative size of game elements',
            _gameScale,
            0.00001,
            0.001,
            (value) {
              setState(() {
                _gameScale = value;
              });
              _saveSetting('game.game_scale', value);
            },
          ),

          SizedBox(height: 20),

          // Ball Radius Slider
          _buildSliderSetting(
            'Ball Radius',
            'Size of the ball',
            _ballRadius,
            0.5,
            2.0,
            (value) {
              setState(() {
                _ballRadius = value;
              });
              _saveSetting('game.ball_radius', value);
            },
          ),

          SizedBox(height: 30),

          // Team Colors Section
          _buildSectionHeader('Team Colors'),
          SizedBox(height: 20),

          // Team A Color
          _buildColorSetting(
            Team.a.displayName,
            'Primary color for ${Team.a.shortName}',
            _teamAColor,
            (color) {
              setState(() {
                _teamAColor = color;
              });
              _saveSetting('colors.team_a_color', color.toARGB32());
            },
          ),

          SizedBox(height: 20),

          // Team B Color
          _buildColorSetting(
            Team.b.displayName,
            'Primary color for ${Team.b.shortName}',
            _teamBColor,
            (color) {
              setState(() {
                _teamBColor = color;
              });
              _saveSetting('colors.team_b_color', color.toARGB32());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Color.fromARGB(255, 200, 200, 200),
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildBooleanSetting(
    String title,
    String description,
    bool value,
    Function(bool) onChanged,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Color.fromARGB(255, 255, 255, 255),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                description,
                style: TextStyle(
                  color: Color.fromARGB(150, 255, 255, 255),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        CupertinoSwitch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: Color.fromARGB(255, 0, 150, 255),
        ),
      ],
    );
  }

  Widget _buildSliderSetting(
    String title,
    String description,
    double value,
    double min,
    double max,
    Function(double) onChanged, {
    String? suffix,
    int? decimalPlaces,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                color: Color.fromARGB(255, 255, 255, 255),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${value.toStringAsFixed(decimalPlaces ?? 5)}${suffix ?? ''}',
              style: TextStyle(
                color: Color.fromARGB(200, 255, 255, 255),
                fontSize: 14,
              ),
            ),
          ],
        ),
        Text(
          description,
          style: TextStyle(
            color: Color.fromARGB(150, 255, 255, 255),
            fontSize: 14,
          ),
        ),
        SizedBox(height: 10),
        CupertinoSlider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
          activeColor: Color.fromARGB(255, 0, 150, 255),
        ),
      ],
    );
  }

  Widget _buildColorSetting(
    String title,
    String description,
    Color currentColor,
    Function(Color) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                color: Color.fromARGB(255, 255, 255, 255),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            GestureDetector(
              onTap: () => _showColorPicker(title, currentColor, onChanged),
              child: Container(
                width: 40,
                height: 30,
                decoration: BoxDecoration(
                  color: currentColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Color.fromARGB(100, 255, 255, 255),
                    width: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 5),
        Text(
          description,
          style: TextStyle(
            color: Color.fromARGB(150, 255, 255, 255),
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  void _showColorPicker(
    String title,
    Color currentColor,
    Function(Color) onChanged,
  ) {
    showCupertinoDialog(
      context: context,
      builder: (BuildContext context) {
        Color selectedColor = currentColor;

        return CupertinoAlertDialog(
          title: Text('Choose $title Color'),
          content: SizedBox(
            height: 300,
            child: SingleChildScrollView(
              child: BlockPicker(
                pickerColor: currentColor,
                onColorChanged: (color) {
                  selectedColor = color;
                },
                availableColors: [
                  // Cupertino system colors
                  CupertinoColors.systemBlue,
                  CupertinoColors.systemGreen,
                  CupertinoColors.systemIndigo,
                  CupertinoColors.systemOrange,
                  CupertinoColors.systemPink,
                  CupertinoColors.systemPurple,
                  CupertinoColors.systemRed,
                  CupertinoColors.systemTeal,
                  CupertinoColors.systemYellow,
                  CupertinoColors.systemGrey,
                  // Additional vibrant colors
                ],
                itemBuilder:
                    (
                      Color color,
                      bool isCurrentColor,
                      void Function() changeColor,
                    ) {
                      return Container(
                        margin: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.8),
                              offset: const Offset(1, 2),
                              blurRadius: 5,
                            ),
                          ],
                        ),
                        child: Material(
                          color: CupertinoColors.transparent,
                          child: InkWell(
                            onTap: changeColor,
                            borderRadius: BorderRadius.circular(50),
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 210),
                              opacity: isCurrentColor ? 1 : 0,
                              child: Icon(
                                CupertinoIcons.check_mark,
                                color: useWhiteForeground(color)
                                    ? CupertinoColors.white
                                    : CupertinoColors.black,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
              ),
            ),
          ),
          actions: [
            CupertinoDialogAction(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            CupertinoDialogAction(
              child: Text('Select'),
              onPressed: () {
                onChanged(selectedColor);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _saveSetting(String key, dynamic value) {
    try {
      if (value is bool) {
        appSettings.setBool(key, value);
      } else if (value is int) {
        appSettings.setInt(key, value);
      } else if (value is double) {
        appSettings.setDouble(key, value);
      }
      widget.appLog.info('Saved setting $key: $value');

      // Reload settings in game if it's a game-related setting
      if (key.startsWith('game.') ||
          key.startsWith('physics.') ||
          key.startsWith('colors.')) {
        // Fire and forget - don't block UI for network reinitialization
        widget.game.reloadSettings();
        widget.appLog.info('Reloaded game settings after changing $key');
      }
    } catch (e) {
      widget.appLog.warning('Could not save setting $key: $e');
    }
  }

  void _closeSettings() {
    widget.appLog.info('Closing settings overlay');
    widget.game.overlays.remove(SettingsUI.overlayID);
  }
}
