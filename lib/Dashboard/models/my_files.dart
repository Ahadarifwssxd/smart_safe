import 'package:flutter/material.dart';

class CloudStorageInfo {
  final String? title, totalStorage;
  final int? numOfFiles, percentage;
  final Color? color;
  final IconData? icon;

  CloudStorageInfo({
    this.title,
    this.totalStorage,
    this.numOfFiles,
    this.percentage,
    this.color,
    this.icon,
  });
}
