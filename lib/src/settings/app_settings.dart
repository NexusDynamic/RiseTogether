import 'game.dart';
import 'physics.dart';
import 'colors.dart';
import 'network.dart';
import 'settings_manager.dart';

mixin class AppSettings {
  final Settings appSettings = Settings();
  static bool _isInitialized = false;

  Future<void> initSettings() async {
    if (_isInitialized) return;
    _isInitialized = true;
    appSettings.register(gameSettings);
    appSettings.register(physicsSettings);
    appSettings.register(colorSettings);
    appSettings.register(networkSettings);
    await appSettings.init();
  }
}
