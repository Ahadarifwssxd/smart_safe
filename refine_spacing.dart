import 'dart:io';

void main() async {
  final dir = Directory('lib/pages');
  final files = await dir.list().toList();

  final regexFontSize = RegExp(r"fontSize:\s*(20|22|24|26|28)(,\s*)?(fontWeight:\s*FontWeight\.w[789]00)?");
  final regexWidth10 = RegExp(r"SizedBox\(width:\s*10\)");
  final regexHeight10 = RegExp(r"SizedBox\(height:\s*10\)");
  final regexHeight14 = RegExp(r"SizedBox\(height:\s*14\)");
  final regexHeight20 = RegExp(r"SizedBox\(height:\s*20\)");
  final regexHeight30 = RegExp(r"SizedBox\(height:\s*30\)");
  final regexHeight40 = RegExp(r"SizedBox\(height:\s*40\)");
  final regexPadding10 = RegExp(r"EdgeInsets\.only\(bottom:\s*10\)");
  final regexPadding14 = RegExp(r"EdgeInsets\.all\(14\)");

  for (var fileEntity in files) {
    if (fileEntity is File && fileEntity.path.endsWith('.dart')) {
      final name = fileEntity.path.split(Platform.pathSeparator).last;
      
      // We process 10_ to 28_ 
      if (name.startsWith(RegExp(r'^(1[0-9]|2[0-8])_'))) {
        print('Processing $name...');
        String content = await fileEntity.readAsString();

        // Add letterSpacing: -0.2 to headers 20+
        // Wait, replacing this might be tricky with regex if it already has letterSpacing.
        // So we do a targeted replace for typical headers.
        content = content.replaceAll(
          "fontSize: 22, fontWeight: FontWeight.w800)",
          "fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.2)",
        );
        content = content.replaceAll(
          "fontSize: 24, fontWeight: FontWeight.w800)",
          "fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.2)",
        );
        content = content.replaceAll(
          "fontSize: 20, fontWeight: FontWeight.w800)",
          "fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.2)",
        );
        
        // 4-pt grid fixes
        content = content.replaceAll(regexWidth10, "SizedBox(width: 8)");
        content = content.replaceAll(regexHeight10, "SizedBox(height: 12)"); // typically 12 between items
        content = content.replaceAll(regexHeight14, "SizedBox(height: 16)"); // typically 16 between sections
        content = content.replaceAll(regexHeight20, "SizedBox(height: 24)"); // typically 24 between major sections
        content = content.replaceAll(regexHeight30, "SizedBox(height: 32)"); 
        content = content.replaceAll(regexHeight40, "SizedBox(height: 40)"); 
        content = content.replaceAll(regexPadding10, "EdgeInsets.only(bottom: 12)");
        content = content.replaceAll(regexPadding14, "EdgeInsets.all(16)");

        // Make sure font weights are updated for body (this is risky via simple regex, but we look for typical body patterns)
        // We'll skip body weight regex to avoid breaking icons or specific widgets.

        await fileEntity.writeAsString(content);
      }
    }
  }
  print('Done.');
}
