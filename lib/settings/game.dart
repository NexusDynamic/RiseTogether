import 'settings_common.dart';

final gameSettingsGroup = SettingsGroup(
  items: [BoolSetting(key: 'enable_sound', defaultValue: true)],
);

class GameSettings extends SettingsBase {
  GameSettings() : super(key: 'game_settings', items: gameSettingsGroup);
}
