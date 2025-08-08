import 'package:rise_together/src/models/team.dart';

/// Mixin that provides convenient team-based access to collections
///
/// This mixin allows classes to provide both absolute and relative team access
/// to their collections (like worlds, controllers, distances, etc.)
mixin TeamProvider {
  /// The player context for relative team operations
  PlayerContext? get playerContext => null;

  /// Convert a team to its array index
  int teamToIndex(Team team) => team.id;

  /// Convert a relative team to its array index (requires player context)
  int? relativeTeamToIndex(RelativeTeam relativeTeam) {
    final context = playerContext;
    if (context == null) return null;

    final absoluteTeam = context.resolveTeam(relativeTeam);
    return absoluteTeam?.id;
  }
}

/// Extension on List to provide team-based access
extension TeamList<T> on List<T> {
  /// Get item by absolute team
  T forTeam(Team team) {
    final index = team.id;
    if (index >= length) {
      throw RangeError.index(index, this, 'team', 'Team index out of range');
    }
    return this[index];
  }

  /// Get item by relative team (requires player context)
  T? forRelativeTeam(RelativeTeam relativeTeam, PlayerContext? context) {
    if (context == null) return null;

    final absoluteTeam = context.resolveTeam(relativeTeam);
    if (absoluteTeam == null) return null;

    return forTeam(absoluteTeam);
  }

  /// Set item by absolute team
  void setForTeam(Team team, T value) {
    final index = team.id;
    if (index >= length) {
      throw RangeError.index(index, this, 'team', 'Team index out of range');
    }
    this[index] = value;
  }

  /// Set item by relative team (requires player context)
  bool setForRelativeTeam(
    RelativeTeam relativeTeam,
    T value,
    PlayerContext? context,
  ) {
    if (context == null) return false;

    final absoluteTeam = context.resolveTeam(relativeTeam);
    if (absoluteTeam == null) return false;

    setForTeam(absoluteTeam, value);
    return true;
  }
}

/// Extension on Map to provide team-based access
extension TeamMap<T> on Map<int, T> {
  /// Get item by absolute team
  T? forTeam(Team team) => this[team.id];

  /// Get item by relative team (requires player context)
  T? forRelativeTeam(RelativeTeam relativeTeam, PlayerContext? context) {
    if (context == null) return null;

    final absoluteTeam = context.resolveTeam(relativeTeam);
    if (absoluteTeam == null) return null;

    return forTeam(absoluteTeam);
  }

  /// Set item by absolute team
  void setForTeam(Team team, T value) {
    this[team.id] = value;
  }

  /// Set item by relative team (requires player context)
  bool setForRelativeTeam(
    RelativeTeam relativeTeam,
    T value,
    PlayerContext? context,
  ) {
    if (context == null) return false;

    final absoluteTeam = context.resolveTeam(relativeTeam);
    if (absoluteTeam == null) return false;

    setForTeam(absoluteTeam, value);
    return true;
  }

  /// Get all teams that have values
  Iterable<Team> get teams => keys
      .where((id) => Team.values.any((team) => team.id == id))
      .map((id) => Team.fromId(id));

  /// Convert to team-keyed map
  Map<Team, T> toTeamMap() {
    final result = <Team, T>{};
    for (final entry in entries) {
      try {
        final team = Team.fromId(entry.key);
        result[team] = entry.value;
      } catch (e) {
        // Skip invalid team IDs
      }
    }
    return result;
  }
}

/// Convenient wrapper for team-based collections
class TeamCollection<T> {
  final List<T> _items;
  final PlayerContext? _context;

  TeamCollection(this._items, [this._context]);

  /// Create a team collection with initial values
  TeamCollection.filled(T value, [PlayerContext? context])
    : _items = List.filled(Team.values.length, value),
      _context = context;

  /// Create an empty team collection (requires a default value)
  TeamCollection.generate(T Function() generator, [PlayerContext? context])
    : _items = List.generate(Team.values.length, (_) => generator()),
      _context = context;

  /// Get by absolute team
  T operator [](Team team) => _items.forTeam(team);

  /// Set by absolute team
  void operator []=(Team team, T value) => _items.setForTeam(team, value);

  /// Get by relative team
  T? mine() => _items.forRelativeTeam(RelativeTeam.mine, _context);
  T? other() => _items.forRelativeTeam(RelativeTeam.other, _context);

  /// Set by relative team
  bool setMine(T value) =>
      _items.setForRelativeTeam(RelativeTeam.mine, value, _context);
  bool setOther(T value) =>
      _items.setForRelativeTeam(RelativeTeam.other, value, _context);

  /// Get all teams
  Iterable<Team> get teams => Team.values;

  /// Get all values
  List<T> get values => List.from(_items);

  /// Iterate over team-value pairs
  Iterable<MapEntry<Team, T>> get entries =>
      Team.values.map((team) => MapEntry(team, _items.forTeam(team)));

  /// Apply function to all teams
  void forEach(void Function(Team team, T value) action) {
    for (final team in Team.values) {
      action(team, _items.forTeam(team));
    }
  }

  /// Map values to a new collection
  TeamCollection<R> map<R>(R Function(Team team, T value) transform) {
    final newItems = <R>[];
    for (final team in Team.values) {
      newItems.add(transform(team, _items.forTeam(team)));
    }
    return TeamCollection(newItems, _context);
  }

  /// Length of the collection
  int get length => _items.length;
}
