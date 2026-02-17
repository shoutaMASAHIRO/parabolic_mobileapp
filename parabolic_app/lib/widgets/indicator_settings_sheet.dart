import 'package:flutter/material.dart';
import '../models/chart_configs.dart';
import '../theme/app_colors.dart';

class IndicatorSettingsSheet extends StatefulWidget {
  final Map<String, IndicatorSettings> indicators;
  final Function(String, IndicatorSettings) onChanged;
  final Function(String, bool) onToggle;
  final Map<String, IndicatorSettings> Function() onReset;

  const IndicatorSettingsSheet({
    super.key,
    required this.indicators,
    required this.onChanged,
    required this.onToggle,
    required this.onReset,
  });

  @override
  State<IndicatorSettingsSheet> createState() => _IndicatorSettingsSheetState();
}

class _IndicatorSettingsSheetState extends State<IndicatorSettingsSheet> {
  late Map<String, IndicatorSettings> _local;
  bool _trendExpanded = false;
  bool _oscExpanded = false;

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
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
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
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                child: Row(
                  children: [
                    Container(
                      width: 4, height: 18,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(2)),
                    ),
                    const Expanded(
                      child: Text(
                        'インジケーター設定',
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight.withAlpha(30),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            onPressed: _showResetMenu,
                            icon: const Icon(Icons.settings_backup_restore, color: AppColors.primaryLight, size: 24),
                            tooltip: '設定リセットメニュー',
                            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                          ),
                        ),
                        const SizedBox(width: 36), // ×ボタンのためのスペースを確保
                      ],
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
                        _buildSectionHeader(
                          'トレンド系',
                          'チャート上に表示',
                          Icons.show_chart,
                          AppColors.primary,
                          _trendExpanded,
                          () => setState(() => _trendExpanded = !_trendExpanded),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOutCubic,
                          child: _trendExpanded
                              ? Column(children: _trend.map((c) => _buildIndicatorTile(c)).toList())
                              : const SizedBox(width: double.infinity, height: 0),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionHeader(
                          'オシレーター系',
                          'サブチャートに表示',
                          Icons.ssid_chart,
                          AppColors.rsiLine,
                          _oscExpanded,
                          () => setState(() => _oscExpanded = !_oscExpanded),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOutCubic,
                          child: _oscExpanded
                              ? Column(children: _osc.map((c) => _buildIndicatorTile(c)).toList())
                              : const SizedBox(width: double.infinity, height: 0),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white54, size: 20),
            ),
            tooltip: '閉じる',
          ),
        ),
      ],
    );
  }

  void _showResetMenu() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.settings_backup_restore, color: AppColors.primaryLight, size: 24),
            SizedBox(width: 12),
            Text('インジケーターのリセット', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildResetOption(
              icon: Icons.tune,
              title: '設定値をリセット',
              subtitle: '期間などの数値を初期値に戻します',
              color: AppColors.warning,
              onTap: () {
                Navigator.pop(context);
                // 親（DetailScreen）側のデータをリセットし、最新のデータを取得する
                final updatedIndicators = widget.onReset();
                
                setState(() {
                  for (final key in updatedIndicators.keys) {
                    if (_local.containsKey(key)) {
                      // 現在の画面上のON/OFF状態を維持する
                      final currentEnabled = _local[key]?.enabled ?? false;
                      _local[key] = updatedIndicators[key]!.copyWith();
                      _local[key]!.enabled = currentEnabled;
                    }
                  }
                });
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('パラメータを初期値に戻しました')));
              },
            ),
            const SizedBox(height: 12),
            _buildResetOption(
              icon: Icons.visibility_off_outlined,
              title: 'すべてオフにする',
              subtitle: '表示中の指標をすべて非表示にします',
              color: AppColors.error,
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  for (final k in _local.keys) {
                    _local[k]!.enabled = false;
                    widget.onToggle(k, false);
                  }
                });
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('すべての指標をオフにしました')));
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildResetOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(30)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withAlpha(30), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                Text(subtitle, style: TextStyle(color: AppColors.textSecondary.withOpacity(0.8), fontSize: 11)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
        ],
      ),
    ),
  );

  Widget _buildSectionHeader(String t, String s, IconData i, Color c, bool isExpanded, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(color: c.withAlpha(20)),
      child: Row(
        children: [
          Icon(i, color: c, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c)),
                Text(s, style: TextStyle(fontSize: 11, color: c.withAlpha(180))),
              ],
            ),
          ),
          Icon(
            isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            color: c.withAlpha(180),
            size: 20,
          ),
        ],
      ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: config.color.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                  child: Icon(config.icon, color: config.color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${config.name} 設定', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      Text(config.fullName, style: TextStyle(color: config.color.withOpacity(0.7), fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white10, height: 1),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16, top: 8),
                child: Text(
                  '数値を入力してインジケーターの計算期間を調整できます。',
                  style: TextStyle(color: AppColors.textSecondary.withOpacity(0.8), fontSize: 13),
                ),
              ),
              ...tempParams.entries.map((e) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withAlpha(10)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_getParamLabel(e.key), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            Text('Parameter: ${e.key}', style: TextStyle(color: AppColors.textSecondary.withOpacity(0.5), fontSize: 10)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                          textAlign: TextAlign.right,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.black26,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: config.color, width: 1.5)),
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
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('キャンセル', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _local[config.key] = settings.copyWith(params: tempParams);
                    });
                    widget.onChanged(config.key, _local[config.key]!);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: config.color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('保存する', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getParamLabel(String key) {
    switch (key) {
      case 'period': return '計算期間';
      case 'period1': return '短期EMA期間';
      case 'period2': return '中期EMA期間';
      case 'period3': return '長期EMA期間';
      case 'stdDev1': return '標準偏差 (1σ)';
      case 'stdDev2': return '標準偏差 (2σ)';
      case 'fast': return '短期EMA (Fast)';
      case 'slow': return '長期EMA (Slow)';
      case 'signal': return 'シグナル期間';
      case 'kPeriod': return '%K期間';
      case 'dPeriod': return '%D期間';
      case 'smooth': return '平滑化 (Slowing)';
      case 'tenkan': return '転換線 期間';
      case 'kijun': return '基準線 期間';
      case 'senkouB': return '先行スパンB 期間';
      case 'displacement': return '先行スパン 変位';
      case 'acceleration': return '加速係数 (AF)';
      case 'maxAcceleration': return '最大加速係数';
      case 'deviation': return '乖離率 (%)';
      case 'multiplier': return '乗数 (Multiplier)';
      case 'short1': return '短期線1';
      case 'short2': return '短期線2';
      case 'short3': return '短期線3';
      case 'short4': return '短期線4';
      case 'short5': return '短期線5';
      case 'short6': return '短期線6';
      case 'long1': return '長期線1';
      case 'long2': return '長期線2';
      case 'long3': return '長期線3';
      case 'long4': return '長期線4';
      case 'long5': return '長期線5';
      case 'long6': return '長期線6';
      default: return key;
    }
  }
}
