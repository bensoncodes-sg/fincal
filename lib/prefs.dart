/// Small preferences such as "the intro tour has been seen". A JSON file on
/// phones and in tests, localStorage in the browser.
library;

export 'platform/prefs_io.dart'
    if (dart.library.js_interop) 'platform/prefs_web.dart';
