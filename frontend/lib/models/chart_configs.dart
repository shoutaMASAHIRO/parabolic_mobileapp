import 'package:flutter/material.dart';

enum ChartType { line, candlestick, heikinAshi, dot }

class IndicatorSettings {
  bool enabled;
  final Map<String, dynamic> params;
  IndicatorSettings({this.enabled = false, Map<String, dynamic>? params}) : params = params ?? {};
  IndicatorSettings copyWith({bool? enabled, Map<String, dynamic>? params}) =>
      IndicatorSettings(enabled: enabled ?? this.enabled, params: params ?? Map.from(this.params));
}

class IndicatorConfig {
  final String key, name, fullName, description;
  final Color color;
  final IconData icon;
  IndicatorConfig({
    required this.key,
    required this.name,
    required this.fullName,
    required this.description,
    required this.color,
    required this.icon,
  });
}
