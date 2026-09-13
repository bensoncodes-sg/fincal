import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// localStorage, guarded. Safari private browsing and full storage both throw
/// on write, and saving must never take the app down.
String? readLocal(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (e) {
    debugPrint('Basis: localStorage unavailable ($e).');
    return null;
  }
}

bool writeLocal(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
    return true;
  } catch (e) {
    debugPrint('Basis: could not write localStorage ($e).');
    return false;
  }
}
