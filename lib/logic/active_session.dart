import 'package:shared_preferences/shared_preferences.dart';

/// The in-progress workout, remembered across app switches.
///
/// UI state only — nothing about completion, history, or summaries reads it,
/// and it is never a database column (invariant 14).
abstract final class ActiveSession {
  // Not the session id: sessions are created lazily on the first confirmed set
  // (invariant 3), so at Start time there is no id to store.
  static const _dateKey = 'active_session_date';
  static const _routineKey = 'active_session_routine';

  /// The remembered workout, or null if there is none.
  static Future<({String date, int routineId})?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final date = prefs.getString(_dateKey);
    final routineId = prefs.getInt(_routineKey);
    if (date == null || routineId == null) return null;
    return (date: date, routineId: routineId);
  }

  /// Remembers the workout being started.
  static Future<void> write({
    required String date,
    required int routineId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dateKey, date);
    await prefs.setInt(_routineKey, routineId);
  }

  /// Forgets the workout — on Finish, or when the stored date is not today.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dateKey);
    await prefs.remove(_routineKey);
  }
}
