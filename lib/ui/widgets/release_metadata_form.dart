import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../generated/l10n/app_localizations.dart';
import '../../generated/l10n/app_localizations_en.dart';

enum ReleaseFieldKind {
  text,
  multiline,
  number,
  date,
  dateTime,
  path,
  stringList,
  choice,
  references,
}

/// Typed field definitions shared by the native release forms.
class ReleaseMetadataField {
  const ReleaseMetadataField(
    this.key,
    this.label, {
    this.kind = ReleaseFieldKind.text,
    this.required = false,
    this.choices = const {},
    this.defaultValue,
  });

  final String key;
  final String label;
  final ReleaseFieldKind kind;
  final bool required;
  final Map<String, String> choices;
  final Object? defaultValue;
}

Future<Map<String, dynamic>?> showReleaseMetadataForm({
  required BuildContext context,
  required String title,
  required Map<String, dynamic> initial,
  required List<ReleaseMetadataField> fields,
}) => showDialog<Map<String, dynamic>>(
  context: context,
  builder: (_) =>
      _ReleaseMetadataDialog(title: title, initial: initial, fields: fields),
);

class _ReleaseMetadataDialog extends StatefulWidget {
  const _ReleaseMetadataDialog({
    required this.title,
    required this.initial,
    required this.fields,
  });
  final String title;
  final Map<String, dynamic> initial;
  final List<ReleaseMetadataField> fields;
  @override
  State<_ReleaseMetadataDialog> createState() => _ReleaseMetadataDialogState();
}

class _ReleaseMetadataDialogState extends State<_ReleaseMetadataDialog> {
  final _form = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final _values = <String, dynamic>{};
  String? _error;
  AppLocalizations get l =>
      AppLocalizations.of(context) ?? AppLocalizationsEn();

  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      final value = widget.initial[field.key] ?? field.defaultValue;
      if (field.kind == ReleaseFieldKind.references) {
        _values[field.key] = value is List
            ? List<String>.from(value)
            : <String>[];
      } else if (field.kind == ReleaseFieldKind.choice) {
        final choice = value?.toString();
        _values[field.key] = choice == '' ? null : choice;
      } else {
        var text = value?.toString() ?? '';
        if (field.kind == ReleaseFieldKind.stringList && value is List) {
          text = value.join(', ');
        }
        if (field.kind == ReleaseFieldKind.dateTime && text.isNotEmpty) {
          text = DateTime.tryParse(text)?.toLocal().toIso8601String() ?? text;
        }
        if (field.kind == ReleaseFieldKind.date && text.isNotEmpty) {
          final date = DateTime.tryParse(text);
          if (date != null) text = date.toIso8601String().substring(0, 10);
        }
        _controllers[field.key] = TextEditingController(text: text);
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _date(ReleaseMetadataField field) async {
    final parsed = DateTime.tryParse(_controllers[field.key]!.text);
    final initial =
        (field.kind == ReleaseFieldKind.date ? parsed : parsed?.toLocal()) ??
        DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (date == null || !mounted) return;
    if (field.kind == ReleaseFieldKind.date) {
      _controllers[field.key]!.text = date.toIso8601String().substring(0, 10);
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    _controllers[field.key]!.text = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toIso8601String();
  }

  Future<void> _file(ReleaseMetadataField field) async {
    try {
      final result = await FilePicker.pickFiles();
      if (!mounted) return;
      final path = result.firstOrNull?.path;
      if (path != null) _controllers[field.key]!.text = path;
      setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _apply() {
    if (!_form.currentState!.validate()) return;
    final result = Map<String, dynamic>.from(widget.initial);
    for (final field in widget.fields) {
      if (field.kind == ReleaseFieldKind.references) {
        result[field.key] = List<String>.from(_values[field.key] as List);
      } else if (field.kind == ReleaseFieldKind.choice) {
        final value = _values[field.key];
        if (value == null || value == '') {
          result[field.key] = null;
        } else {
          result[field.key] = value;
        }
      } else {
        final text = _controllers[field.key]!.text.trim();
        if (field.kind == ReleaseFieldKind.stringList) {
          result[field.key] = text
              .split(',')
              .map((v) => v.trim())
              .where((v) => v.isNotEmpty)
              .toSet()
              .toList();
        } else if (text.isEmpty) {
          result[field.key] = null;
        } else if (field.kind == ReleaseFieldKind.number) {
          result[field.key] = double.parse(text.replaceAll(',', '.'));
        } else if (field.kind == ReleaseFieldKind.dateTime) {
          result[field.key] = DateTime.parse(text).toUtc().toIso8601String();
        } else if (field.kind == ReleaseFieldKind.date) {
          result[field.key] = DateTime.parse(
            text,
          ).toIso8601String().substring(0, 10);
        } else {
          result[field.key] = text;
        }
      }
    }
    Navigator.of(context).pop(result);
  }

  Widget _field(ReleaseMetadataField field) {
    if (field.kind == ReleaseFieldKind.references) {
      final values = _values[field.key] as List<String>;
      final options = {...field.choices};
      for (final id in values) {
        options.putIfAbsent(
          id,
          () => '${l.releaseManagerUnexpectedStatus}: $id',
        );
      }
      return InputDecorator(
        decoration: InputDecoration(
          labelText: field.label,
          border: const OutlineInputBorder(),
        ),
        child: options.isEmpty
            ? Text(l.releaseManagerEmpty)
            : Wrap(
                spacing: 6,
                children: [
                  for (final entry in options.entries)
                    FilterChip(
                      label: Text(entry.value),
                      selected: values.contains(entry.key),
                      onSelected: (selected) => setState(() {
                        selected
                            ? values.add(entry.key)
                            : values.remove(entry.key);
                      }),
                    ),
                ],
              ),
      );
    }
    if (field.kind == ReleaseFieldKind.choice) {
      final options = {...field.choices};
      final current = _values[field.key] as String?;
      if (current != null && !options.containsKey(current)) {
        options[current] = '${l.releaseManagerUnexpectedStatus}: $current';
      }
      return DropdownButtonFormField<String>(
        key: ValueKey('field-${field.key}'),
        initialValue: current,
        isExpanded: true,
        decoration: InputDecoration(labelText: field.label),
        items: [
          if (!field.required)
            DropdownMenuItem(value: '', child: Text(l.releaseManagerNone)),
          for (final entry in options.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (value) => _values[field.key] = value,
        validator: (value) => field.required && (value == null || value.isEmpty)
            ? l.releaseManagerRequired
            : null,
      );
    }
    return TextFormField(
      key: ValueKey('field-${field.key}'),
      controller: _controllers[field.key],
      maxLines: field.kind == ReleaseFieldKind.multiline ? 4 : 1,
      keyboardType: field.kind == ReleaseFieldKind.number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: field.label,
        helperText: field.kind == ReleaseFieldKind.stringList
            ? l.releaseManagerCommaSeparated
            : field.kind == ReleaseFieldKind.dateTime ||
                  field.kind == ReleaseFieldKind.date
            ? l.releaseManagerLocalTime
            : null,
        suffixIcon: field.kind == ReleaseFieldKind.path
            ? IconButton(
                tooltip: l.releaseManagerFilePicker,
                onPressed: () => _file(field),
                icon: const Icon(Icons.folder_open),
              )
            : field.kind == ReleaseFieldKind.dateTime
            ? IconButton(
                onPressed: () => _date(field),
                icon: const Icon(Icons.calendar_month),
              )
            : null,
      ),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (field.required && text.isEmpty) return l.releaseManagerRequired;
        if (text.isNotEmpty &&
            field.kind == ReleaseFieldKind.number &&
            double.tryParse(text.replaceAll(',', '.'))?.isFinite != true) {
          return l.releaseManagerInvalidNumber;
        }
        if (text.isNotEmpty &&
            (field.kind == ReleaseFieldKind.dateTime ||
                field.kind == ReleaseFieldKind.date) &&
            DateTime.tryParse(text) == null) {
          return l.releaseManagerInvalidDate;
        }
        if (text.isNotEmpty &&
            field.kind == ReleaseFieldKind.date &&
            (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
                DateTime.parse(text).toIso8601String().substring(0, 10) !=
                    text)) {
          return l.releaseManagerInvalidDate;
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              for (final field in widget.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _field(field),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l.cancel),
      ),
      FilledButton(
        key: const ValueKey('apply-record'),
        onPressed: _apply,
        child: Text(l.apply),
      ),
    ],
  );
}
