import 'local_storage_web.dart';

/// Browser preferences in localStorage. Same API as the file-based store.
class PrefsStore {
  PrefsStore({Object? directory, this.fileName = 'prefs.json'});

  final String fileName;

  Future<String?> read(String key) async => readLocal('basis.pref.$key');

  Future<void> write(String key, String value) async {
    writeLocal('basis.pref.$key', value);
  }
}

PrefsStore createPrefsStore() => PrefsStore();
