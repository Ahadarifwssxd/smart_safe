import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
  
  int count = 0;
  final regex = RegExp(r'const\s+(TextStyle|BoxDecoration|Icon|Border|ColorScheme|Divider|Text|Positioned|Center|Padding|SizedBox|Row|Column|Container|Align|BoxShadow|Color|Drawer|AppBar|Scaffold|FloatingActionButton|ListTile|CircleAvatar|Card|ElevatedButton|OutlinedButton|TextButton)\(');
  final regexArray = RegExp(r'const\s+\[');
  
  for (final file in files) {
    final content = file.readAsStringSync();
    final newContent = content.replaceAllMapped(regex, (m) => '${m.group(1)}(').replaceAllMapped(regexArray, (m) => '[');
    
    if (newContent != content) {
      count++;
      file.writeAsStringSync(newContent);
    }
  }
  print('Modified $count files');
}
