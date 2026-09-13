import 'dart:io';

/// Writes [content] to a file and returns a sentence saying where it went.
Future<String> saveTextFile(String fileName, String content) async {
  final dir = Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}basis',
  );
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final f = File('${dir.path}${Platform.pathSeparator}$fileName');
  await f.writeAsString(content, flush: true);
  return 'Written to ${f.path}';
}

const bool kSaveIsDownload = false;
