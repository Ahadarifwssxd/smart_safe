import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  final classRegex = RegExp(r'\bconst\s+(_Step|BlinkDot|PulseRing|SlideUpFade|WaveBars|StatusBadge|Expanded|_StatCard|BorderSide|InputDecoration|AlwaysStoppedAnimation|_FlowStep|_BreathPhase|_BreathPattern|_ScoreFactor|_Suggestion|_StatPill|LinearGradient)\b');
  final varRegex = RegExp(r'\bstatic\s+const\s+([A-Za-z0-9_]+)\s*=');

  int count = 0;
  for (final file in files) {
    final content = file.readAsStringSync();
    
    // Replace const ClassName with ClassName
    var newContent = content.replaceAllMapped(classRegex, (m) {
      return m.group(1)!;
    });

    // Replace static const variable = with static final variable =
    newContent = newContent.replaceAllMapped(varRegex, (m) {
      return 'static final ${m.group(1)} =';
    });

    if (newContent != content) {
      file.writeAsStringSync(newContent);
      print('Updated: ${file.path}');
      count++;
    }
  }

  print('Completed. Modified $count files.');
}
