import 'package:package_info_plus/package_info_plus.dart';

class RiseTogetherPackageInfo {
  static final instance = RiseTogetherPackageInfo._internal();
  static String get version => instance._version;
  static String get buildNumber => instance._buildNumber;
  late final String _version;
  late final String _buildNumber;

  RiseTogetherPackageInfo._internal();

  factory RiseTogetherPackageInfo() => instance;

  Future<void> init(PackageInfo info) async {
    _version = info.version;
    _buildNumber = info.buildNumber;
  }

  @override
  String toString() => 'Version: $_version (Build: $_buildNumber)';
}
