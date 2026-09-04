import 'dart:io';

void main() async {
  final dir = Directory('lib');
  final files = await dir.list(recursive: true).toList();

  for (var fileEntity in files) {
    if (fileEntity is File && fileEntity.path.endsWith('.dart')) {
      String content = await fileEntity.readAsString();
      bool modified = false;

      if (content.contains('C.textMutedhite')) {
        content = content.replaceAll('C.textMutedhite', 'C.textMuted');
        modified = true;
      }
      if (content.contains('FontWeight.w750')) {
        content = content.replaceAll('FontWeight.w750', 'FontWeight.w700');
        modified = true;
      }
      if (content.contains('FontWeight.w850')) {
        content = content.replaceAll('FontWeight.w850', 'FontWeight.w800');
        modified = true;
      }

      if (modified) {
        print('Fixed ${fileEntity.path}');
        await fileEntity.writeAsString(content);
      }
    }
  }
  print('Done.');
}
