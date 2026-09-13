/// Scenario persistence. Phones and tests write a JSON file; the browser
/// build keeps the same JSON in localStorage. `createScenarioStore` picks
/// the right one, so nothing else in the app knows which platform it is on.
library;

export 'platform/scenario_store_io.dart'
    if (dart.library.js_interop) 'platform/scenario_store_web.dart';
