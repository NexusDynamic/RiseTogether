import 'package:flutter/cupertino.dart';
import 'package:rise_together/src/ui/overlay.dart';
import 'package:rise_together/src/game/rise_together_game.dart';
import 'package:rise_together/src/services/log_service.dart';

/// Placeholder survey UI for future expansion
/// This can be extended to include actual survey questions, data collection, etc.
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
    'How did you feel about this level?',
    'How well did you cooperate with your team?',
    'How challenging was the level?',
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
          width: screenWidth * 0.8,
          height: screenHeight * 0.6,
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
            child: ListView
            (
              children: [
                _buildHeader(),
                SizedBox(height: 30),
                _buildQuestion(),
                SizedBox(height: 30),
                _buildAnswerOptions(),
                Spacer(),
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
          'Quick Survey',
          style: TextStyle(
            color: Color.fromARGB(255, 255, 255, 255),
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 10),
        Text(
          'Question ${_currentQuestion + 1} of ${_questions.length}',
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
    final options = ['Very Good', 'Good', 'Neutral', 'Poor', 'Very Poor'];

    return Column(
      children: options.map((option) {
        final isSelected = _answers[_currentQuestion] == option;
        return GestureDetector(
          onTap: () {
            setState(() {
              _answers[_currentQuestion] = option;
            });
          },
          child: Container(
            margin: EdgeInsets.symmetric(vertical: 5),
            padding: EdgeInsets.all(15),
            width: double.infinity,
            decoration: BoxDecoration(
              color: isSelected
                  ? Color.fromARGB(150, 0, 150, 255)
                  : Color.fromARGB(100, 100, 100, 100),
              borderRadius: BorderRadius.circular(10),
              border: isSelected
                  ? Border.all(
                      color: Color.fromARGB(255, 0, 150, 255),
                      width: 2,
                    )
                  : null,
            ),
            child: Text(
              option,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color.fromARGB(255, 255, 255, 255),
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
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
