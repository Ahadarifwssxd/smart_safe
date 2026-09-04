import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
  
  int count = 0;
  for (final file in files) {
    String content = file.readAsStringSync();
    String oldContent = content;
    
    // Replace Colors.white70 first so it doesn't get partially matched
    content = content.replaceAll('Colors.white70', 'C.white.withOpacity(0.7)');
    // Then replace Colors.white
    content = content.replaceAll('Colors.white', 'C.white');
    
    if (content != oldContent) {
      count++;
      file.writeAsStringSync(content);
    }
  }
  print('Replaced Colors.white with C.white in $count files');
}
