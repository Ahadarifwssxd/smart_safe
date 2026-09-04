import 'dart:io';

void main() async {
  final file = File('lib/widgets/app_drawer.dart');
  final lines = await file.readAsLines();

  int startIndex = -1;
  int endIndex = -1;

  for (int i = 0; i < lines.length; i++) {
    if (lines[i].contains("const _SectionLabel('Travel Guard')")) {
      startIndex = i;
    }
    if (lines[i].contains("const SizedBox(height: 8),") && lines[i+1].contains("const _SectionLabel('Travel Guard')")) {
        startIndex = i; // capture the SizedBox above Travel Guard
    }
    if (lines[i].contains("const SafetyFeedPage()")) {
      endIndex = i + 3; // wait, what's after SafetyFeedPage?
    }
  }
  
  if (startIndex == -1) { print('Start not found'); return; }

  // Let's refine endIndex search
  for (int i = startIndex; i < lines.length; i++) {
    if (lines[i].trim() == "]," && lines[i+1].trim() == "),") {
      endIndex = i - 1;
      break;
    }
  }
  print('Start: $startIndex, End: $endIndex');

  if (endIndex == -1 || startIndex >= endIndex) {
    print('Failed to find replace block');
    return;
  }

  final replacement = '''
                  const SizedBox(height: 8),
                  StreamBuilder<List<AppSection>>(
                    stream: AppStructureService.instance.watchSections(contextFilter: 'app'),
                    builder: (context, secSnap) {
                      final sections = secSnap.data ?? [];
                      return StreamBuilder<List<AppSectionItem>>(
                        stream: AppStructureService.instance.watchItems(contextFilter: 'app'),
                        builder: (context, itemSnap) {
                          final items = itemSnap.data ?? [];
                          if (sections.isEmpty) return const SizedBox.shrink();
                          
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: sections.map((section) {
                              if (section.title.toLowerCase().contains('crisis') || section.title.toLowerCase().contains('sos')) {
                                return const SizedBox.shrink();
                              }
                              
                              final sectionItems = items.where((i) => i.sectionId == section.id).toList();
                              if (sectionItems.isEmpty) return const SizedBox.shrink();
                              
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _SectionLabel(section.title),
                                  ...sectionItems.map((item) {
                                    return _DrawerTile(
                                      icon: item.icon,
                                      label: item.label,
                                      subtitle: item.subtitle.isEmpty ? null : item.subtitle,
                                      color: item.color,
                                      onTap: () {
                                        Navigator.pop(context);
                                        AppPageRouter.open(context, item.routeKey, onSOSTap: onSOSTap);
                                      },
                                    );
                                  }).toList(),
                                  const SizedBox(height: 8),
                                ],
                              );
                            }).toList(),
                          );
                        },
                      );
                    },
                  ),
''';

  List<String> newLines = [];
  
  // Imports at the top
  newLines.add("import '../services/app_structure_service.dart';");
  newLines.add("import '../models/app_structure.dart';");
  newLines.add("import '../navigation/app_page_router.dart';");

  for (int i = 0; i < lines.length; i++) {
    if (i < startIndex) {
      newLines.add(lines[i]);
    } else if (i == startIndex) {
      newLines.add(replacement);
    } else if (i > endIndex) {
      newLines.add(lines[i]);
    }
  }

  await file.writeAsString(newLines.join('\\n'));
  print('Done.');
}
