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

  static final List<IndicatorConfig> trend = [
    IndicatorConfig(key: 'bb', name: 'BB', fullName: 'ボリンジャーバンド', description: '価格の変動範囲', color: Colors.blue, icon: Icons.stacked_line_chart),
    IndicatorConfig(key: 'ema', name: 'EMA', fullName: '指数移動平均線', description: '3本の指数移動平均', color: Colors.orange, icon: Icons.show_chart),
    IndicatorConfig(key: 'sma', name: 'SMA', fullName: '単純移動平均線', description: '単純な価格の平均', color: Colors.teal, icon: Icons.show_chart),
    IndicatorConfig(key: 'wma', name: 'WMA', fullName: '加重移動平均線', description: '直近に重みを置いた平均', color: Colors.indigo, icon: Icons.show_chart),
    IndicatorConfig(key: 'ichimoku', name: '一目均衡表', fullName: '一目均衡表', description: '相場の均衡を把握', color: Colors.redAccent, icon: Icons.grid_on),
    IndicatorConfig(key: 'parabolic', name: 'SAR', fullName: 'パラボリック', description: 'トレンドの転換点', color: Colors.amber, icon: Icons.radio_button_checked),
    IndicatorConfig(key: 'envelope', name: 'Env', fullName: 'エンベロープ', description: '移動平均からの乖離', color: Colors.purpleAccent, icon: Icons.waves),
    IndicatorConfig(key: 'keltner', name: 'KC', fullName: 'ケルトナーチャネル', description: 'ATRを用いたチャネル', color: Colors.lightGreen, icon: Icons.linear_scale),
    IndicatorConfig(key: 'supertrend', name: 'ST', fullName: 'スーパートレンド', description: 'トレンドの方向と転換', color: Colors.deepOrange, icon: Icons.trending_up),
    IndicatorConfig(key: 'gmma', name: 'GMMA', fullName: '複合型移動平均線', description: '12本の移動平均線', color: Colors.cyan, icon: Icons.waves),
  ];

  static final List<IndicatorConfig> osc = [
    IndicatorConfig(key: 'rsi', name: 'RSI', fullName: '相対力指数', description: '買われすぎ/売られすぎ', color: const Color(0xFF9C27B0), icon: Icons.trending_up), // RSI Line Color
    IndicatorConfig(key: 'macd', name: 'MACD', fullName: '移動平均収束拡散', description: 'トレンドの勢い', color: const Color(0xFF2196F3), icon: Icons.bar_chart), // MACD Line Color
    IndicatorConfig(key: 'stochastic', name: 'Stoch', fullName: 'ストキャスティクス', description: '逆張りの指標', color: const Color(0xFFFF9800), icon: Icons.ssid_chart), // Stoch K Color
    IndicatorConfig(key: 'cci', name: 'CCI', fullName: '商品チャンネル指数', description: '平均価格からの乖離', color: const Color(0xFF4CAF50), icon: Icons.multiline_chart), // CCI Line Color
    IndicatorConfig(key: 'ma_dev', name: '乖離率', fullName: '移動平均乖離率', description: 'SMAからの乖離幅', color: Colors.blueGrey, icon: Icons.align_vertical_center),
    IndicatorConfig(key: 'dmi', name: 'DMI', fullName: '方向性指数', description: 'トレンドの有無と強さ', color: Colors.pinkAccent, icon: Icons.compare_arrows),
    IndicatorConfig(key: 'adx', name: 'ADX', fullName: '平均方向性指数', description: 'トレンドの強さ', color: Colors.deepPurple, icon: Icons.speed),
    IndicatorConfig(key: 'rci', name: 'RCI', fullName: '順位相関指数', description: '時間と価格の相関', color: Colors.brown, icon: Icons.auto_graph),
    IndicatorConfig(key: 'momentum', name: 'Mom', fullName: 'モメンタム', description: '相場の勢い', color: Colors.lime, icon: Icons.rocket_launch),
    IndicatorConfig(key: 'roc', name: 'ROC', fullName: '変化率', description: '価格の変化率', color: Colors.orangeAccent, icon: Icons.data_saver_off),
    IndicatorConfig(key: 'ultimate', name: 'UO', fullName: 'アルティメット', description: '3つの期間の合わせ技', color: Colors.deepPurpleAccent, icon: Icons.exposure),
    IndicatorConfig(key: 'trix', name: 'TRIX', fullName: 'トリックス', description: '3重指数移動平均', color: Colors.blueAccent, icon: Icons.polyline),
  ];
}
