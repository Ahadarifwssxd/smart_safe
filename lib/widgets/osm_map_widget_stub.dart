import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/colors.dart';
import 'osm_map_widget.dart';

OsmMapWidget getOsmMapWidget(
        {required double latitude, required double longitude}) =>
    MobileOsmMapWidget(latitude: latitude, longitude: longitude);

class MobileOsmMapWidget extends OsmMapWidget {
  const MobileOsmMapWidget({
    super.key,
    required super.latitude,
    required super.longitude,
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        center: LatLng(latitude, longitude),
        zoom: 16.0,
        minZoom: 3.0,
        interactiveFlags: InteractiveFlag.all,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c'],
          userAgentPackageName: 'com.example.smartsafe',
        ),
        MarkerLayer(
          markers: [
            Marker(
              width: 60,
              height: 60,
              point: LatLng(latitude, longitude),
              builder: (context) => Icon(
                Icons.location_on_rounded,
                size: 48,
                color: C.accent,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
