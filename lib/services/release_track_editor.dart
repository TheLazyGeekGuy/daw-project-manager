/// Pure, non-destructive updates to ordered release tracks.
class ReleaseTrackEditor {
  static Map<String, dynamic> upsert(
    Map<String, dynamic> source,
    Map<String, String> track, {
    int? index,
  }) {
    final id = (track['id'] ?? '').trim();
    if (id.isEmpty) throw const FormatException('Track ID is required');
    final current = source['tracks'];
    if (current is! List) throw const FormatException('Tracks must be a list');
    final entries = current.map((item) {
      if (item is! Map) throw const FormatException('Invalid track record');
      return Map<String, dynamic>.from(item);
    }).toList();
    if (entries.indexed.any((e) => e.$2['id'] == id && e.$1 != index)) {
      throw const FormatException('Duplicate track ID');
    }
    if (index == null) {
      entries.add({...track});
    } else {
      if (index < 0 || index >= entries.length) throw RangeError.index(index, entries);
      entries[index] = {...entries[index], ...track};
    }
    return {...source, 'tracks': entries};
  }

  static Map<String, dynamic> remove(Map<String, dynamic> source, int index) {
    final tracks = source['tracks'];
    if (tracks is! List) throw const FormatException('Tracks must be a list');
    final entries = List<dynamic>.from(tracks)..removeAt(index);
    return {...source, 'tracks': entries};
  }

  static Map<String, dynamic> move(
      Map<String, dynamic> source, int from, int to) {
    final tracks = source['tracks'];
    if (tracks is! List) throw const FormatException('Tracks must be a list');
    final entries = List<dynamic>.from(tracks);
    if (to < 0 || to >= entries.length) throw RangeError.index(to, entries);
    final item = entries.removeAt(from);
    entries.insert(to, item);
    return {...source, 'tracks': entries};
  }
}
