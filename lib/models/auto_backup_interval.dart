enum AutoBackupInterval {
  off,
  every30min,
  hourly,
  every6hours,
  daily;

  Duration? get duration {
    switch (this) {
      case AutoBackupInterval.off:
        return null;
      case AutoBackupInterval.every30min:
        return const Duration(minutes: 30);
      case AutoBackupInterval.hourly:
        return const Duration(hours: 1);
      case AutoBackupInterval.every6hours:
        return const Duration(hours: 6);
      case AutoBackupInterval.daily:
        return const Duration(hours: 24);
    }
  }

  static AutoBackupInterval fromStorageKey(String? key) {
    return AutoBackupInterval.values.firstWhere(
      (e) => e.name == key,
      orElse: () => AutoBackupInterval.off,
    );
  }

  /// Whether automatic sync should run now. At launch it runs whenever it is
  /// on, so a second device picks up changes straight away instead of an
  /// interval later.
  bool isDue({
    required DateTime? lastSync,
    required DateTime now,
    bool atLaunch = false,
  }) {
    final every = duration;
    if (every == null) return false;
    if (atLaunch || lastSync == null) return true;
    return now.difference(lastSync) >= every;
  }
}
