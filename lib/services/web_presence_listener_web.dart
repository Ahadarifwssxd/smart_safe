// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void bindTabVisibilityHeartbeat(void Function() onVisible) {
  html.document.onVisibilityChange.listen((_) {
    if (html.document.visibilityState == 'visible') {
      onVisible();
    }
  });
}
