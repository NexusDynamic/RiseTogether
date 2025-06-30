import 'package:meta/meta.dart';

mixin class Resetable {
  /// Resets the state of the object to its initial state.
  @mustBeOverridden
  void reset() {
    // This method should be overridden by subclasses to implement specific reset logic.
    throw UnimplementedError('reset() must be implemented by subclasses');
  }
}
