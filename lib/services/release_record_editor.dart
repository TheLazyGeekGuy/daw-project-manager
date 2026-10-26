/// Immutable operations on release workflow record lists.
///
/// Never reconstruct a list from display names; preserve stable IDs and all
/// unrelated fields of existing entries.
class ReleaseRecordEditor {
  static const sections = {
    'rights_filings': ('organization', 'status'),
    'distribution': ('distributor', 'status'),
    'communications': ('platform', 'status'),
  };

  static Map<String, dynamic> update(
    Map<String, dynamic> source,
    String section,
    int? index,
    Map<String, String> values,
  ) {
    final fields = sections[section];
    if (fields == null) throw ArgumentError.value(section, 'section');
    final primary = values[fields.$1]?.trim() ?? '';
    final status = values[fields.$2]?.trim() ?? '';
    if (primary.isEmpty || status.isEmpty) {
      throw const FormatException('Name and status are mandatory');
    }
    final entries = _entries(source, section);
    if (index == null) {
      entries.add({...values});
    } else {
      if (index < 0 || index >= entries.length) {
        throw RangeError.index(index, entries);
      }
      entries[index] = {...entries[index], ...values};
    }
    return {...source, section: entries};
  }

  static Map<String, dynamic> remove(
    Map<String, dynamic> source,
    String section,
    int index,
  ) {
    if (!sections.containsKey(section)) throw ArgumentError.value(section);
    final entries = _entries(source, section);
    entries.removeAt(index);
    return {...source, section: entries};
  }

  static List<Map<String, dynamic>> _entries(
    Map<String, dynamic> source,
    String section,
  ) {
    final value = source[section];
    if (value is! List) throw FormatException('$section must be a list');
    return value.map((item) {
      if (item is! Map) throw FormatException('Invalid $section record');
      return Map<String, dynamic>.from(item);
    }).toList();
  }
}
