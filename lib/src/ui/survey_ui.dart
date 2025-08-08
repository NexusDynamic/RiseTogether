import 'package:flutter/cupertino.dart';
import 'package:rise_together/src/ui/overlay.dart';
import 'package:rise_together/src/game/rise_together_game.dart';
import 'package:rise_together/src/services/log_service.dart';

/// IOS (Inclusion of Other in Self) Scale Survey UI
/// Single question about alignment between self and teammates
class SurveyUI extends StatefulWidget
    with AppLogging
    implements RiseTogetherOverlay {
  static final String overlayID = 'Survey';
  final RiseTogetherGame game;

  SurveyUI(this.game, {super.key});

  @override
  State<SurveyUI> createState() => _SurveyUIState();
}

class _SurveyUIState extends State<SurveyUI> {
  int _currentQuestion = 0;
  final List<String> _questions = [
    'How aligned do you feel your own and your teammates were during the last round?',
  ];

  final List<String> _alignmentOptions = [
    'Not at all aligned',
    'Hardly aligned',
    'A little aligned',
    'Somewhat aligned',
    'Very aligned',
    'Extremely aligned',
  ];

  final List<String> _answers = [];

  @override
  void initState() {
    super.initState();
    // Initialize answers list
    _answers.addAll(List.filled(_questions.length, ''));
  }

  @override
  Widget build(BuildContext context) {
    widget.appLog.info('Building Survey overlay');
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      width: screenWidth,
      height: screenHeight,
      color: Color.fromARGB(220, 0, 0, 0),
      child: Center(
        child: Container(
          width: screenWidth * 0.9,
          height: screenHeight * 0.8,
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
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                _buildHeader(),
                SizedBox(height: 30),
                _buildQuestion(),
                SizedBox(height: 30),
                Expanded(child: _buildAnswerOptions()),
                SizedBox(height: 20),
                _buildNavigationButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Text(
          'Team Alignment Survey',
          style: TextStyle(
            color: Color.fromARGB(255, 255, 255, 255),
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 10),
        Text(
          'IOS Scale (Inclusion of Other in Self)',
          style: TextStyle(
            color: Color.fromARGB(200, 255, 255, 255),
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _buildQuestion() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color.fromARGB(100, 60, 60, 60),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(
        _questions[_currentQuestion],
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color.fromARGB(255, 255, 255, 255),
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildAnswerOptions() {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 15,
        runSpacing: 15,
        children: _alignmentOptions.asMap().entries.map((entry) {
          final index = entry.key;
          final option = entry.value;
          final isSelected = _answers[_currentQuestion] == option;

          return GestureDetector(
            onTap: () {
              setState(() {
                _answers[_currentQuestion] = option;
              });
            },
            child: Container(
              width: 140,
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? Color.fromARGB(150, 0, 150, 255)
                    : Color.fromARGB(100, 100, 100, 100),
                borderRadius: BorderRadius.circular(15),
                border: isSelected
                    ? Border.all(
                        color: Color.fromARGB(255, 0, 150, 255),
                        width: 2,
                      )
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Circle visualization
                  _buildCircleVisualization(index),
                  SizedBox(height: 8),
                  // Text label below circles
                  Text(
                    option,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color.fromARGB(255, 255, 255, 255),
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCircleVisualization(int index) {
    // Calculate overlap based on index (0-5)
    // 0: no overlap, 5: maximum overlap
    double overlap = (index / 5.0) * 35; // 0 to 35 pixels overlap

    // Calculate the distance each circle should move from center
    double leftOffset = -(40 - overlap) / 2; // Left circle moves left
    double rightOffset = (40 - overlap) / 2; // Right circle moves right

    return SizedBox(
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Left circle (Self)
          Align(
            alignment: Alignment.center,
            child: Transform.translate(
              offset: Offset(leftOffset, 0),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Color.fromARGB(100, 100, 150, 255),
                  border: Border.all(
                    color: Color.fromARGB(255, 100, 150, 255),
                    width: 2,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    'Self',
                    style: TextStyle(
                      color: Color.fromARGB(255, 255, 255, 255),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Right circle (Teammates)
          Align(
            alignment: Alignment.center,
            child: Transform.translate(
              offset: Offset(rightOffset, 0),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Color.fromARGB(100, 255, 150, 100),
                  border: Border.all(
                    color: Color.fromARGB(255, 255, 150, 100),
                    width: 2,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    'Team',
                    style: TextStyle(
                      color: Color.fromARGB(255, 255, 255, 255),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons() {
    final canGoNext = _answers[_currentQuestion].isNotEmpty;
    final isLastQuestion = _currentQuestion == _questions.length - 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Previous button
        if (_currentQuestion > 0)
          GestureDetector(
            onTap: _previousQuestion,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Color.fromARGB(180, 100, 100, 100),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Previous',
                style: TextStyle(
                  color: Color.fromARGB(255, 255, 255, 255),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
        else
          SizedBox(), // Empty space for alignment
        // Next/Finish button
        GestureDetector(
          onTap: canGoNext
              ? (isLastQuestion ? _finishSurvey : _nextQuestion)
              : null,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: canGoNext
                  ? (isLastQuestion
                        ? Color.fromARGB(255, 0, 200, 0)
                        : Color.fromARGB(255, 0, 150, 255))
                  : Color.fromARGB(100, 100, 100, 100),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isLastQuestion ? 'Finish' : 'Next',
              style: TextStyle(
                color: canGoNext
                    ? Color.fromARGB(255, 255, 255, 255)
                    : Color.fromARGB(150, 255, 255, 255),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _previousQuestion() {
    if (_currentQuestion > 0) {
      setState(() {
        _currentQuestion--;
      });
    }
  }

  void _nextQuestion() {
    if (_currentQuestion < _questions.length - 1) {
      setState(() {
        _currentQuestion++;
      });
    }
  }

  void _finishSurvey() {
    widget.appLog.info('Survey completed with answers: $_answers');

    // Here you could save survey data to a database, file, etc.
    // For now, we'll just log the results
    for (int i = 0; i < _questions.length; i++) {
      widget.appLog.info('Q: ${_questions[i]} - A: ${_answers[i]}');
    }

    // Remove survey and continue to level transition
    widget.game.overlays.remove(SurveyUI.overlayID);
    widget.game.overlays.add('LevelTransition');
  }
}
