import 'package:flutter/cupertino.dart';
import 'package:rise_together/src/ui/overlay.dart';
import 'package:rise_together/src/game/rise_together_game.dart';
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

class _SettingsUIState extends State<SettingsUI> with AppSettings {
  bool _debugMode = true;
  double _gameScale = 0.0001;
  double _ballRadius = 1.0;
  double _levelDuration = 120.0;
  double _distanceMultiplier = 100.0;
  int _tournamentRounds = 3;
  int _levelsPerRound = 5;
  bool _enableSurveys = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    try {
      _debugMode = appSettings.getBool('game.debug_mode');
      _gameScale = appSettings.getDouble('game.game_scale');
      _ballRadius = appSettings.getDouble('game.ball_radius');
      _levelDuration = appSettings.getDouble('game.level_duration');
      _distanceMultiplier = appSettings.getDouble('game.distance_multiplier');
      _tournamentRounds = appSettings.getInt('game.tournament_rounds');
      _levelsPerRound = appSettings.getInt('game.levels_per_round');
      _enableSurveys = appSettings.getBool('game.enable_surveys');
    } catch (e) {
      widget.appLog.warning('Could not load settings: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      width: screenWidth,
      height: screenHeight,
      color: Color.fromARGB(220, 0, 0, 0), // Semi-transparent background
      child: Center(
        child: Container(
          width: screenWidth * 0.8,
          height: screenHeight * 0.7,
          decoration: BoxDecoration(
            color: Color.fromARGB(255, 40, 40, 40),
            borderRadius: BorderRadius.circular(20),
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
          GestureDetector(
            onTap: _closeSettings,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Color.fromARGB(100, 255, 0, 0),
                shape: BoxShape.circle,
              ),
              child: Icon(
                CupertinoIcons.xmark,
                color: Color.fromARGB(255, 255, 255, 255),
                size: 20,
              ),
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
            'Show simulated player controls',
            _debugMode,
            (value) {
              setState(() {
                _debugMode = value;
              });
              _saveSetting('game.debug_mode', value);
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
    } catch (e) {
      widget.appLog.warning('Could not save setting $key: $e');
    }
  }

  void _closeSettings() {
    widget.appLog.info('Closing settings overlay');
    widget.game.overlays.remove(SettingsUI.overlayID);
  }
}
