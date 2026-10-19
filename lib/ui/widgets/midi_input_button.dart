import 'package:flutter/material.dart';

import '../../services/midi/input/midi_input.dart';

/// The MIDI input button's strings.
class MidiInputLabels {
  const MidiInputLabels({
    required this.input,
    required this.off,
    required this.all,
    required this.noDevices,
    required this.listening,
    required this.busy,
    required this.stepInput,
  });

  /// The button's tooltip while nothing is listened to: "MIDI input".
  final String input;

  /// The menu's choices: "No MIDI input", "All MIDI inputs".
  final String off, all;

  /// In the menu when nothing is plugged in.
  final String noDevices;

  /// The tooltip while listening: "MIDI input: KeyStep".
  final String Function(String names) listening;

  /// The tooltip when the input couldn't be opened.
  final String Function(String names) busy;

  /// The step input toggle's tooltip.
  final String stepInput;
}

/// The piano roll's MIDI input button: lit while a keyboard is listened
/// to, red when the one chosen couldn't be opened. Its menu offers none,
/// all, or each input plugged in now — asked for each time it opens, so
/// a keyboard plugged in since shows up. Choosing the same input again
/// opens it again (after it was unplugged and plugged back in, say).
class MidiInputButton extends StatelessWidget {
  const MidiInputButton({
    super.key,
    required this.choice,
    required this.listening,
    required this.failed,
    required this.devices,
    required this.onChanged,
    required this.labels,
  });

  final MidiInputChoice choice;

  /// The names of the inputs listened to, and of those that wouldn't open.
  final List<String> listening, failed;

  /// The inputs plugged in now.
  final Future<List<MidiInputDevice>> Function() devices;
  final ValueChanged<MidiInputChoice> onChanged;
  final MidiInputLabels labels;

  String get _tooltip {
    if (listening.isNotEmpty) return labels.listening(listening.join(', '));
    if (failed.isNotEmpty) return labels.busy(failed.join(', '));
    return labels.input;
  }

  Future<void> _showMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    // Under the button.
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(box.size.bottomLeft(Offset.zero), ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final available = await devices();
    if (!context.mounted) return;
    final picked = await showMenu<MidiInputChoice>(
      context: context,
      position: position,
      items: [
        CheckedPopupMenuItem(
          value: MidiInputChoice.off,
          checked: choice.isOff,
          child: Text(labels.off),
        ),
        CheckedPopupMenuItem(
          value: MidiInputChoice.all,
          checked: choice.isAll,
          child: Text(labels.all),
        ),
        const PopupMenuDivider(),
        if (available.isEmpty)
          PopupMenuItem(enabled: false, child: Text(labels.noDevices))
        else
          for (final device in available)
            CheckedPopupMenuItem(
              value: MidiInputChoice.named(device.name),
              checked: choice.name == device.name,
              child: Text(device.name),
            ),
      ],
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      key: const ValueKey('midi-piano-roll-midi-input'),
      tooltip: _tooltip,
      icon: const Icon(Icons.piano),
      color: listening.isNotEmpty
          ? scheme.primary
          : failed.isNotEmpty
              ? scheme.error
              : null,
      onPressed: () => _showMenu(context),
    );
  }
}
