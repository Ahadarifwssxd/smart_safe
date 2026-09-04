import 'package:flutter/material.dart';
import 'osm_map_widget_stub.dart'
    if (dart.library.html) 'osm_map_widget_web.dart';

abstract class OsmMapWidget extends StatelessWidget {
  final double latitude;
  final double longitude;

  const OsmMapWidget({
    super.key,
    required this.latitude,
    required this.longitude,
  });

  factory OsmMapWidget.create({
    required double latitude,
    required double longitude,
  }) => getOsmMapWidget(latitude: latitude, longitude: longitude);
}
