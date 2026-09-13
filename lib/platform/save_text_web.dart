import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Hands [content] to the browser as a download. On iPhone Safari this opens
/// the download prompt and the file lands in the Files app.
Future<String> saveTextFile(String fileName, String content) async {
  // A byte-order mark so Excel and Numbers read the S$ sign correctly.
  final bytes = utf8.encode('﻿$content');
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.append(a);
  a.click();
  a.remove();
  // Revoke later, so a slow download is not cut off.
  Future<void>.delayed(
    const Duration(seconds: 30),
    () => web.URL.revokeObjectURL(url),
  );
  return 'Downloaded $fileName';
}

const bool kSaveIsDownload = true;
