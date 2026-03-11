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
    for (final c in [...IndicatorConfig.trend, ...IndicatorConfig.osc]) {
      if (widget.indicators.containsKey(c.key)) {
        _local[c.key] = widget.indicators[c.key]!.copyWith();
      } else {
        _local[c.key] = IndicatorSettings(enabled: false);
      }
    }
  }

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
                        TextButton.icon(
                          onPressed: _showResetMenu,
                          icon: const Icon(Icons.settings_backup_restore, color: AppColors.primaryLight, size: 18),
                          label: const Text(
                            'リセット',
                            style: TextStyle(color: AppColors.primaryLight, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                          ),
                          style: TextButton.styleFrom(
                            backgroundColor: AppColors.primaryLight.withAlpha(25),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
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
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final itemWidth = (constraints.maxWidth - 36) / 2;
                        return Column(
                          children: [
                            const SizedBox(height: 21),
                            _buildSectionHeader(
                              'トレンド系',
                              'チャート上に表示',
                              Icons.show_chart,
                              AppColors.accent,
                              _trendExpanded,
                              () => setState(() => _trendExpanded = !_trendExpanded),
                              IndicatorConfig.trend.where((c) => _local[c.key]?.enabled ?? false).length,
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeInOutCubic,
                              child: _trendExpanded
                                  ? Padding(
                                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                      child: Wrap(
                                        spacing: 12,
                                        runSpacing: 12,
                                        children: IndicatorConfig.trend.map((c) => _buildIndicatorTile(c, itemWidth)).toList(),
                                      ),
                                    )
                                  : const SizedBox(width: double.infinity, height: 0),
                            ),
                            _buildSectionHeader(
                              'オシレーター系',
                              'サブチャートに表示',
                              Icons.ssid_chart,
                              AppColors.rsiLine,
                              _oscExpanded,
                              () => setState(() => _oscExpanded = !_oscExpanded),
                              IndicatorConfig.osc.where((c) => _local[c.key]?.enabled ?? false).length,
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeInOutCubic,
                              child: _oscExpanded
                                  ? Padding(
                                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                      child: Wrap(
                                        spacing: 12,
                                        runSpacing: 12,
                                        children: IndicatorConfig.osc.map((c) => _buildIndicatorTile(c, itemWidth)).toList(),
                                      ),
                                    )
                                  : const SizedBox(width: double.infinity, height: 0),
                            ),
                            const SizedBox(height: 24),
                          ],
                        );
                      },
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

  Widget _buildSectionHeader(String t, String s, IconData i, Color c, bool isExpanded, VoidCallback onTap, int activeCount) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isExpanded ? c.withAlpha(45) : c.withAlpha(15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isExpanded ? c.withAlpha(100) : c.withAlpha(40),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 4, height: 26,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(color: c.withAlpha(100), blurRadius: 4),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(t, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5)),
                      if (activeCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 2)],
                          ),
                          child: Text(activeCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ],
                  ),
                  Text(s, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isExpanded ? Colors.white70 : c.withAlpha(200))),
                ],
              ),
            ),
            Icon(
              isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              color: c,
              size: 26,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildIndicatorTile(IndicatorConfig config, double width) {
    final s = _local[config.key];
    final isE = s?.enabled ?? false;
    final isOsc = IndicatorConfig.osc.any((c) => c.key == config.key);
    
    return GestureDetector(
      onTap: () {
        final nv = !isE;
        setState(() {
          if (nv && isOsc) {
            for (final c in IndicatorConfig.osc) {
              if (_local.containsKey(c.key)) _local[c.key]!.enabled = false;
              if (c.key != config.key) widget.onToggle(c.key, false);
            }
          }
          if (!_local.containsKey(config.key)) _local[config.key] = IndicatorSettings(enabled: nv);
          else _local[config.key]!.enabled = nv;
        });
        widget.onToggle(config.key, nv);
      },
      child: Stack(
        children: [
          Container(
            width: width,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: isE ? config.color.withAlpha(40) : Colors.white.withAlpha(5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isE ? config.color : Colors.white.withAlpha(10),
                width: isE ? 2.0 : 1.0,
              ),
              boxShadow: isE ? [
                BoxShadow(
                  color: config.color.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ] : null,
            ),
            child: Column(
              children: [
                Icon(
                  config.icon,
                  size: 32,
                  color: isE ? Colors.white : config.color.withOpacity(0.7),
                ),
                const SizedBox(height: 12),
                Text(
                  config.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isE ? FontWeight.bold : FontWeight.normal,
                    color: isE ? Colors.white : AppColors.textSecondary,
                  ),
                ),
                Text(
                  config.fullName,
                  style: TextStyle(
                    fontSize: 10,
                    color: isE ? Colors.white70 : AppColors.textSecondary.withOpacity(0.5),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // 設定ボタン（右上に小さく配置）
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              icon: Icon(Icons.tune_rounded, size: 18, color: isE ? Colors.white : Colors.white24),
              onPressed: () => _showParamsDialog(config),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'パラメータ設定',
            ),
          ),
        ],
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
