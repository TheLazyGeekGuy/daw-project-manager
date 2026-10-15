import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/services/auto_start/shell_link.dart';

/// Builds a `.lnk` laid out as MS-SHLLINK describes — the same layout the
/// shell's WScript.Shell writes, which the parser was also checked against
/// on a real Windows machine (a Startup shortcut to the Store build's exe,
/// and one to an execution alias with `--minimized`).
Uint8List buildShellLink({
  String? basePath,
  String suffix = '',
  bool unicodeLinkInfo = false,
  bool withIdList = true,
  String? name,
  String? workingDir,
  String? arguments,
  bool unicodeStrings = true,
}) {
  final out = BytesBuilder();
  void u16(int v) => out.add((ByteData(2)..setUint16(0, v, Endian.little))
      .buffer
      .asUint8List());
  void u32(int v) => out.add((ByteData(4)..setUint32(0, v, Endian.little))
      .buffer
      .asUint8List());

  var flags = 0;
  if (withIdList) flags |= 1 << 0;
  if (basePath != null) flags |= 1 << 1;
  if (name != null) flags |= 1 << 2;
  if (workingDir != null) flags |= 1 << 4;
  if (arguments != null) flags |= 1 << 5;
  if (unicodeStrings) flags |= 1 << 7;

  // ShellLinkHeader: size, CLSID, flags, then attributes/times/etc. as zeros.
  u32(0x4C);
  out.add(List.filled(16, 0));
  u32(flags);
  out.add(List.filled(0x4C - 0x18, 0));

  if (withIdList) {
    final idList = [0x14, 0x00, ...List.filled(0x12, 0xAB), 0x00, 0x00];
    u16(idList.length);
    out.add(idList);
  }

  if (basePath != null) {
    final headerSize = unicodeLinkInfo ? 0x24 : 0x1C;
    final volumeId = [...List.filled(0x10, 0), 0];
    final baseAnsi = [...latin1.encode(basePath.replaceAll(RegExp(r'[^\x00-\xff]'), '?')), 0];
    final suffixAnsi = [...latin1.encode(suffix), 0];
    List<int> utf16z(String s) => [
          for (final unit in s.codeUnits) ...[unit & 0xFF, unit >> 8],
          0,
          0,
        ];
    final baseUnicode = unicodeLinkInfo ? utf16z(basePath) : <int>[];
    final suffixUnicode = unicodeLinkInfo ? utf16z(suffix) : <int>[];

    final volumeIdOffset = headerSize;
    final baseOffset = volumeIdOffset + volumeId.length;
    final suffixOffset = baseOffset + baseAnsi.length;
    final baseUnicodeOffset = suffixOffset + suffixAnsi.length;
    final suffixUnicodeOffset = baseUnicodeOffset + baseUnicode.length;
    final size = suffixUnicodeOffset + suffixUnicode.length;

    u32(size);
    u32(headerSize);
    u32(1); // VolumeIDAndLocalBasePath
    u32(volumeIdOffset);
    u32(baseOffset);
    u32(0); // CommonNetworkRelativeLinkOffset
    u32(suffixOffset);
    if (unicodeLinkInfo) {
      u32(baseUnicodeOffset);
      u32(suffixUnicodeOffset);
    }
    out
      ..add(volumeId)
      ..add(baseAnsi)
      ..add(suffixAnsi)
      ..add(baseUnicode)
      ..add(suffixUnicode);
  }

  for (final text in [name, workingDir, arguments]) {
    if (text == null) continue;
    u16(text.length);
    if (unicodeStrings) {
      for (final unit in text.codeUnits) {
        u16(unit);
      }
    } else {
      out.add(latin1.encode(text));
    }
  }
  // ExtraData terminal block.
  u32(0);
  return out.toBytes();
}

void main() {
  const storeExe = r'C:\Program Files\WindowsApps\'
      r'BandPassRecords.DAWProjectManager_2.9.3.0_x64__fhaegvzcre19p\daw_project_manager.exe';
  const alias = r'C:\Users\me\AppData\Local\Microsoft\WindowsApps\dawprojectmanager.exe';

  test('reads the target and arguments of a Startup shortcut', () {
    final link = parseShellLink(
      buildShellLink(basePath: alias, arguments: '--minimized'),
    )!;
    expect(link.target, alias);
    expect(link.arguments, '--minimized');
  });

  test('reads an old-style shortcut to the versioned exe', () {
    // What 2.9.x wrote: the startup check must see this path to know the
    // shortcut is stale once the version folder is gone.
    final link = parseShellLink(buildShellLink(basePath: storeExe))!;
    expect(link.target, storeExe);
    expect(link.arguments, '');
  });

  test('joins the base path and the common path suffix', () {
    final link = parseShellLink(
      buildShellLink(basePath: r'C:\Apps\', suffix: 'dpm.exe'),
    )!;
    expect(link.target, r'C:\Apps\dpm.exe');
  });

  test('prefers the Unicode path when there is one', () {
    const path = r'C:\Users\José\AppData\Local\Microsoft\WindowsApps\dawprojectmanager.exe';
    final link = parseShellLink(
      buildShellLink(basePath: path, unicodeLinkInfo: true),
    )!;
    expect(link.target, path);
  });

  test('finds the arguments after the other strings', () {
    final link = parseShellLink(buildShellLink(
      basePath: alias,
      name: 'DAW Project Manager',
      workingDir: r'C:\Users\me',
      arguments: '--minimized',
    ))!;
    expect(link.arguments, '--minimized');
  });

  test('reads ANSI strings too', () {
    final link = parseShellLink(buildShellLink(
      basePath: alias,
      arguments: '--minimized',
      unicodeStrings: false,
    ))!;
    expect(link.arguments, '--minimized');
  });

  test('works without a target ID list', () {
    final link = parseShellLink(
      buildShellLink(basePath: alias, withIdList: false),
    )!;
    expect(link.target, alias);
  });

  test('a shortcut without link info has no target', () {
    final link = parseShellLink(buildShellLink(arguments: '--minimized'))!;
    expect(link.target, isNull);
    expect(link.arguments, '--minimized');
  });

  test('rejects bytes that are not a shortcut', () {
    expect(parseShellLink(Uint8List(0)), isNull);
    expect(parseShellLink(Uint8List.fromList(utf8.encode('not a shortcut at all'))), isNull);
  });

  test('rejects a truncated shortcut instead of reading past the end', () {
    final full = buildShellLink(basePath: alias, arguments: '--minimized');
    for (final cut in [0x20, 0x4C + 10, full.length - 10]) {
      expect(parseShellLink(Uint8List.sublistView(full, 0, cut)), isNull,
          reason: 'cut at $cut');
    }
  });
}
