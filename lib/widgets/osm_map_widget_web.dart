import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'osm_map_widget.dart';

OsmMapWidget getOsmMapWidget({required double latitude, required double longitude}) => WebOsmMapWidget(latitude: latitude, longitude: longitude);

class WebOsmMapWidget extends OsmMapWidget {
  const WebOsmMapWidget({
    super.key,
    required super.latitude,
    required super.longitude,
  });

  @override
  Widget build(BuildContext context) {
    // Generate a unique viewId to force recreating the iframe on location changes
    final viewId = 'osm-map-${latitude.toStringAsFixed(6)}-${longitude.toStringAsFixed(6)}';

    // Register the platform view factory on-the-fly
    ui_web.platformViewRegistry.registerViewFactory(
      viewId,
      (int id) {
        const bboxDelta = 0.003;
        final minLon = longitude - bboxDelta;
        final minLat = latitude - bboxDelta;
        final maxLon = longitude + bboxDelta;
        final maxLat = latitude + bboxDelta;

        final src = 'https://www.openstreetmap.org/export/embed.html'
            '?bbox=$minLon%2C$minLat%2C$maxLon%2C$maxLat'
            '&layer=mapnik'
            '&marker=$latitude%2C$longitude';

        return html.IFrameElement()
          ..src = src
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%';
      },
    );

    return HtmlElementView(
      key: ValueKey(viewId),
      viewType: viewId,
    );
  }
}
