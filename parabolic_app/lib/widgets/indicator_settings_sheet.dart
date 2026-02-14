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
    // すべての定義済み設定をローカルにコピーし、足りないものはデフォルトで作成
    for (final c in [..._trend, ..._osc]) {
      if (widget.indicators.containsKey(c.key)) {
        _local[c.key] = widget.indicators[c.key]!.copyWith();
      } else {
        _local[c.key] = IndicatorSettings(enabled: false);
      }
    }
  }

  static final List<IndicatorConfig> _trend = [
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

  static final List<IndicatorConfig> _osc = [
    IndicatorConfig(key: 'rsi', name: 'RSI', fullName: '相対力指数', description: '買われすぎ/売られすぎ', color: AppColors.rsiLine, icon: Icons.trending_up),
    IndicatorConfig(key: 'macd', name: 'MACD', fullName: '移動平均収束拡散', description: 'トレンドの勢い', color: AppColors.macdLine, icon: Icons.bar_chart),
    IndicatorConfig(key: 'stochastic', name: 'Stoch', fullName: 'ストキャスティクス', description: '逆張りの指標', color: AppColors.stochK, icon: Icons.ssid_chart),
    IndicatorConfig(key: 'cci', name: 'CCI', fullName: '商品チャンネル指数', description: '平均価格からの乖離', color: AppColors.cciLine, icon: Icons.multiline_chart),
    IndicatorConfig(key: 'ma_dev', name: '乖離率', fullName: '移動平均乖離率', description: 'SMAからの乖離幅', color: Colors.blueGrey, icon: Icons.align_vertical_center),
    IndicatorConfig(key: 'dmi', name: 'DMI', fullName: '方向性指数', description: 'トレンドの有無と強さ', color: Colors.pinkAccent, icon: Icons.compare_arrows),
    IndicatorConfig(key: 'adx', name: 'ADX', fullName: '平均方向性指数', description: 'トレンドの強さ', color: Colors.deepPurple, icon: Icons.speed),
    IndicatorConfig(key: 'rci', name: 'RCI', fullName: '順位相関指数', description: '時間と価格の相関', color: Colors.brown, icon: Icons.auto_graph),
    IndicatorConfig(key: 'momentum', name: 'Mom', fullName: 'モメンタム', description: '相場の勢い', color: Colors.lime, icon: Icons.rocket_launch),
    IndicatorConfig(key: 'roc', name: 'ROC', fullName: '変化率', description: '価格の変化率', color: Colors.orangeAccent, icon: Icons.data_saver_off),
    IndicatorConfig(key: 'ultimate', name: 'UO', fullName: 'アルティメット', description: '3つの期間の合わせ技', color: Colors.deepPurpleAccent, icon: Icons.exposure),
    IndicatorConfig(key: 'trix', name: 'TRIX', fullName: 'トリックス', description: '3重指数移動平均', color: Colors.blueAccent, icon: Icons.polyline),
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 設定ボタンを追加
            IconButton(
              icon: Icon(Icons.settings_outlined, color: isE ? config.color : Colors.white24, size: 20),
              onPressed: () => _showParamsDialog(config),
              tooltip: 'パラメータ設定',
            ),
            Switch(
              value: isE,
              activeTrackColor: config.color.withAlpha(100),
              activeThumbColor: config.color,
              onChanged: (v) {
                setState(() {
                  if (v && isOsc) {
                    for (final c in _osc) {
                      if (_local.containsKey(c.key)) _local[c.key]!.enabled = false;
                      if (c.key != config.key) widget.onToggle(c.key, false);
                    }
                  }
                  if (!_local.containsKey(config.key)) _local[config.key] = IndicatorSettings(enabled: v);
                  else _local[config.key]!.enabled = v;
                });
                widget.onToggle(config.key, v);
              },
            ),
          ],
        ),
        onTap: () {
          final nv = !isE;
          setState(() {
            if (nv && isOsc) {
              for (final c in _osc) {
                if (_local.containsKey(c.key)) _local[c.key]!.enabled = false;
                if (c.key != config.key) widget.onToggle(c.key, false);
              }
            }
            if (!_local.containsKey(config.key)) _local[config.key] = IndicatorSettings(enabled: nv);
            else _local[config.key]!.enabled = nv;
          });
          widget.onToggle(config.key, nv);
        },
      ),
    );
  }

  void _showParamsDialog(IndicatorConfig config) {
    final settings = _local[config.key]!;
    final Map<String, dynamic> tempParams = Map.from(settings.params);
    
    // パラメータがない指標の場合は何もしないかメッセージを出す
    if (tempParams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('この指標に調整可能なパラメータはありません')));
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(config.icon, color: config.color, size: 24),
            const SizedBox(width: 12),
            Text('${config.name} 設定', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: tempParams.entries.map((e) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(_getParamLabel(e.key), style: const TextStyle(color: AppColors.textSecondary))),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.right,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.black26,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                        controller: TextEditingController(text: e.value.toString()),
                        onChanged: (v) {
                          if (e.value is int) {
                            tempParams[e.key] = int.tryParse(v) ?? e.value;
                          } else if (e.value is double) {
                            tempParams[e.key] = double.tryParse(v) ?? e.value;
                          }
                        },
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル', style: TextStyle(color: AppColors.textSecondary))),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _local[config.key] = settings.copyWith(params: tempParams);
              });
              widget.onChanged(config.key, _local[config.key]!);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: config.color, foregroundColor: Colors.white),
            child: const Text('保存', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _getParamLabel(String key) {
    switch (key) {
      case 'period': return '期間';
      case 'period1': return '短期期間';
      case 'period2': return '中期期間';
      case 'period3': return '長期期間';
      case 'stdDev1': return '標準偏差1';
      case 'stdDev2': return '標準偏差2';
      case 'fast': return '短期EMA';
      case 'slow': return '長期EMA';
      case 'signal': return 'シグナル';
      case 'kPeriod': return '%K期間';
      case 'dPeriod': return '%D期間';
      case 'smooth': return '平滑化';
      default: return key;
    }
  }
}
