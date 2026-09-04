import 'dart:io';

void main() async {
  final file = File('lib/widgets/app_drawer.dart');
  String content = await file.readAsString();
  content = content.replaceAll(r'\n', '\n');
  await file.writeAsString(content);
  print('Fixed newlines');
}
