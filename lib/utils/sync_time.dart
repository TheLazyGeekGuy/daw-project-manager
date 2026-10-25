/// Instants in the JSON that Drive sync and local backup carry.
///
/// They are written in UTC, with their "Z". A local time without an offset
/// ("2026-10-25T02:30:00.000") names a different moment on a device in
/// another time zone, and two moments in the hour the clocks go back: read
/// there, a restore made at 02:30 came out an hour before its own deletion
/// and lost to it on every other device.
///
/// Reading gives back a local time, as the models and screens expect. Older
/// files, written without an offset, read as local time, as they always did.
///
/// Only instants — when something was made, changed, deleted, read. A date
/// on the calendar (a deadline, a due date, a release date) stays a local
/// date, the same day in every time zone.
library;

String syncInstant(DateTime t) => t.toUtc().toIso8601String();

String? syncInstantOrNull(DateTime? t) => t == null ? null : syncInstant(t);

DateTime parseSyncInstant(String raw) => DateTime.parse(raw).toLocal();

DateTime? tryParseSyncInstant(Object? raw) => raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
