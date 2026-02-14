import 'package:flutter/material.dart';
import '../models/chart_configs.dart';
import '../theme/app_colors.dart';

class IndicatorSettingsSheet extends StatefulWidget {
  final Map<String, IndicatorSettings> indicators;
  final Function(String, IndicatorSettings) onChanged;
  final Function(String, bool) onToggle;

  const IndicatorSettingsSheet({
    super.key,
    required this.indicators,
    required this.onChanged,
    required this.onToggle,
  });

  @override
  State<IndicatorSettingsSheet> createState() => _IndicatorSettingsSheetState();
}

class _IndicatorSettingsSheetState extends State<IndicatorSettingsSheet> {
  late Map<String, IndicatorSettings> _local;

  @override
  void initState() {
    super.initState();
    _local = {};
    widget.indicators.forEach((k, v) => _local[k] = v.copyWith());
  }

  static final List<IndicatorConfig> _trend = [
    IndicatorConfig(key: 'bb', name: 'BB', fullName: 'ボリンジャーバンド', description: '価格の変動範囲', color: Colors.blue, icon: Icons.stacked_line_chart),
    IndicatorConfig(key: 'ema', name: 'EMA', fullName: '指数移動平均線', description: '3本の移動平均', color: Colors.orange, icon: Icons.show_chart)
  ];

  static final List<IndicatorConfig> _osc = [
    IndicatorConfig(key: 'rsi', name: 'RSI', fullName: '相対力指数', description: '買われすぎ/売られすぎ', color: AppColors.rsiLine, icon: Icons.trending_up),
    IndicatorConfig(key: 'macd', name: 'MACD', fullName: '移動平均収束拡散', description: 'トレンドの勢い', color: AppColors.macdLine, icon: Icons.bar_chart),
    IndicatorConfig(key: 'stochastic', name: 'Stoch', fullName: 'ストキャスティクス', description: '逆張りの指標', color: AppColors.stochK, icon: Icons.ssid_chart),
    IndicatorConfig(key: 'cci', name: 'CCI', fullName: '商品チャンネル指数', description: '平均価格からの乖離', color: AppColors.cciLine, icon: Icons.multiline_chart)
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85, maxWidth: 500),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('インジケーター設定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                TextButton(
                  onPressed: () => setState(() {
                    for (final k in _local.keys) {
                      _local[k]!.enabled = false;
                      widget.onToggle(k, false);
                    }
                  }),
                  child: const Text('すべてオフ', style: TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          Flexible(
            child: SingleChildScrollView(
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    _buildSectionHeader('トレンド系', 'チャート上に表示', Icons.show_chart, AppColors.primary),
                    ..._trend.map((c) => _buildIndicatorTile(c)),
                    const SizedBox(height: 16),
                    _buildSectionHeader('オシレーター系', 'サブチャートに表示', Icons.ssid_chart, AppColors.rsiLine),
                    ..._osc.map((c) => _buildIndicatorTile(c)),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String t, String s, IconData i, Color c) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    decoration: BoxDecoration(color: c.withAlpha(20)),
    child: Row(
      children: [
        Icon(i, color: c, size: 22),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c)),
            Text(s, style: TextStyle(fontSize: 11, color: c.withAlpha(180))),
          ],
        )
      ],
    ),
  );

  Widget _buildIndicatorTile(IndicatorConfig config) {
    final s = _local[config.key];
    final isE = s?.enabled ?? false;
    final isOsc = _osc.any((c) => c.key == config.key);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isE ? config.color.withAlpha(15) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isE ? config.color.withAlpha(50) : Colors.transparent),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: config.color.withAlpha(30), borderRadius: BorderRadius.circular(10)),
          child: Icon(config.icon, color: config.color, size: 24),
        ),
        title: Text(config.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
        subtitle: Text(config.fullName, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        trailing: Switch(
          value: isE,
          activeTrackColor: config.color.withAlpha(100),
          activeThumbColor: config.color,
          onChanged: (v) {
            setState(() {
              if (v && isOsc) {
                for (final c in _osc) {
                  _local[c.key]?.enabled = false;
                  if (c.key != config.key) widget.onToggle(c.key, false);
                }
              }
              _local[config.key]!.enabled = v;
            });
            widget.onToggle(config.key, v);
          },
        ),
        onTap: () {
          final nv = !isE;
          setState(() {
            if (nv && isOsc) {
              for (final c in _osc) {
                _local[c.key]?.enabled = false;
                if (c.key != config.key) widget.onToggle(c.key, false);
              }
            }
            _local[config.key]!.enabled = nv;
          });
          widget.onToggle(config.key, nv);
        },
      ),
    );
  }
}
