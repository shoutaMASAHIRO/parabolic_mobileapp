import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/chart_configs.dart';
import '../theme/app_colors.dart';
import '../services/chart_service.dart';
import '../services/cross_detection_service.dart';

/// 通知・閾値設定モーダルウィジェット
class CrossSettingsModal extends StatefulWidget {
  final String symbol;
  final String interval;
  final List<CrossEvent> crossHistory;
  final double? threshold;
  final List<String> targetIndicators;
  final Map<String, IndicatorSettings> indicators;
  final bool emailNotificationEnabled;
  final double? currentPrice;
  final Function(double?) onThresholdChanged;
  final Function(List<String>) onTargetIndicatorsChanged;
  final Function(bool) onEmailNotificationChanged;
  final VoidCallback onClearHistory;

  const CrossSettingsModal({
    super.key,
    required this.symbol,
    required this.interval,
    required this.crossHistory,
    required this.threshold,
    required this.targetIndicators,
    required this.indicators,
    required this.emailNotificationEnabled,
    required this.currentPrice,
    required this.onThresholdChanged,
    required this.onTargetIndicatorsChanged,
    required this.onEmailNotificationChanged,
    required this.onClearHistory,
  });

  @override
  State<CrossSettingsModal> createState() => _CrossSettingsModalState();
}

class _CrossSettingsModalState extends State<CrossSettingsModal> {
  final ChartService _cs = ChartService();
  late TextEditingController _tc, _ec;
  late bool _ee;
  late List<String> _selectedIndicators; // 複数選択用に変更
  List<String> _emails = [];
  bool _le = false;

  @override
  void initState() {
    super.initState();
    _tc = TextEditingController(text: widget.threshold?.toStringAsFixed(2) ?? '');
    _ec = TextEditingController();
    _ee = widget.emailNotificationEnabled;
    _selectedIndicators = List.from(widget.targetIndicators);
    _load();
  }

  @override
  void dispose() {
    _tc.dispose();
    _ec.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _le = true);
    // 常にGLOBAL（アプリ共通）のメールアドレスのみを取得・管理する
    final es = await _cs.getEmails(symbol: 'GLOBAL');
    
    if (mounted) {
      setState(() {
        _emails = es;
        _le = false;
      });
    }
  }

  /// 実行確認ダイアログ
  Future<bool> _showConfirm({required String title, required String message, Color? confirmColor}) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            content: Text(message, style: const TextStyle(color: AppColors.textSecondary)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('キャンセル', style: TextStyle(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: confirmColor ?? AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('実行', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// メール内容確認ダイアログ
  Future<void> _showEmailContentDialog(CrossEvent e) async {
    final isUp = e.direction == CrossDirection.up;
    final directionText = isUp ? '上抜け' : '下抜け';
    final subject = '【Parabolic】${e.symbol} シグナル検知 (${e.displayName} $directionText)';
    final body = '''
${e.symbol} においてテクニカル指標のシグナルを検知しました。

■銘柄: ${e.symbol}
■時間足: ${e.interval}
■指標: ${e.displayName}
■方向（交差）: $directionText
■検知時価格: ${e.price.toStringAsFixed(e.symbol.contains('JPY') ? 1 : 4)}
■検知時刻: ${DateFormat('yyyy/MM/dd HH:mm:ss').format(e.timestamp)}

${e.displayName} のラインを価格が【$directionText】しました。
設定された閾値（${widget.threshold?.toStringAsFixed(2) ?? '未設定'}）に基づき、この価格から指定以上の変動があった場合に再度メール通知が行われます。
''';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            const Icon(Icons.mark_email_unread_outlined, color: AppColors.primaryLight),
            const SizedBox(width: 12),
            const Text('通知メール内容', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('SUBJECT:', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              const SizedBox(height: 4),
              Text(subject, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: Colors.white10),
              ),
              const Text('BODY:', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withAlpha(10)),
                ),
                child: Text(
                  body,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.6, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる', style: TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Stack(
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
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
                    child: Row(
                      children: [
                        const Text('通知・閾値設定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              if (await _showConfirm(title: '閾値クリア', message: '登録されている閾値を削除しますか？', confirmColor: AppColors.rise)) {
                                widget.onThresholdChanged(null);
                                _tc.clear();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          const Icon(Icons.delete_outline, color: Colors.white, size: 20),
                                          const SizedBox(width: 12),
                                          const Text('閾値をクリアしました', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                        ],
                                      ),
                                      duration: const Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                      backgroundColor: AppColors.rise.withOpacity(0.9),
                                      elevation: 8,
                                      margin: const EdgeInsets.all(20),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(color: Colors.white.withAlpha(40), width: 1),
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('閾値削除', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.rise,
                              foregroundColor: Colors.white,
                              elevation: 4,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 40),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white10),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      children: [
                        _buildSectionLabel('判定対象インジケーター'),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withAlpha(20)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'チャートに表示中の指標からクロス判定対象を選択します',
                                style: TextStyle(color: AppColors.textSecondary.withOpacity(0.9), fontSize: 12),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 10,
                                children: _getEnabledTrendIndicators().map((key) {
                                  final isSelected = _selectedIndicators.contains(key);
                                  return GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        if (isSelected) {
                                          _selectedIndicators.remove(key);
                                        } else {
                                          _selectedIndicators.add(key);
                                        }
                                      });
                                      widget.onTargetIndicatorsChanged(_selectedIndicators);
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isSelected ? AppColors.primary.withOpacity(0.12) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isSelected ? AppColors.primaryLight : Colors.white.withOpacity(0.1),
                                          width: isSelected ? 1.8 : 1.0,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isSelected ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                                            color: isSelected ? AppColors.primaryLight : Colors.white.withOpacity(0.2),
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _getIndicatorName(key),
                                            style: TextStyle(
                                              color: isSelected ? Colors.white : Colors.white.withOpacity(0.5),
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              if (_getEnabledTrendIndicators().isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text('有効なトレンド系指標がありません。インジケーター設定から表示してください。', style: TextStyle(color: AppColors.error, fontSize: 11)),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildSectionLabel('アラート閾値設定'),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withAlpha(20)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'クロス検知時の価格から指定した変動幅（閾値）以上の動きがあった場合に通知します',
                                style: TextStyle(color: AppColors.textSecondary.withOpacity(0.9), fontSize: 13, height: 1.5),
                              ),
                              const SizedBox(height: 20),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _tc,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                      decoration: InputDecoration(
                                        labelText: 'ターゲット変動幅',
                                        labelStyle: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold),
                                        hintText: widget.symbol.endsWith('JPY') || widget.symbol.endsWith('.T') ? '例: 500' : '例: 1.50',
                                        hintStyle: const TextStyle(color: Colors.white24),
                                        prefixIcon: const Icon(Icons.notifications_active, color: AppColors.warning),
                                        suffixText: widget.symbol.endsWith('JPY') || widget.symbol.endsWith('.T') ? '円' : 'USD',
                                        suffixStyle: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                                        filled: true,
                                        fillColor: Colors.black38,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primaryLight, width: 1.5)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                                      ),
                                      onSubmitted: (v) => widget.onThresholdChanged(double.tryParse(v)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    height: 64,
                                    child: ElevatedButton(
                                      onPressed: () async {
                                        if (await _showConfirm(title: '閾値更新', message: '通知する価格変動幅を更新しますか？')) {
                                          widget.onThresholdChanged(double.tryParse(_tc.text));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Row(
                                                children: [
                                                  const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                                                  const SizedBox(width: 12),
                                                  const Text('閾値を更新しました', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                                ],
                                              ),
                                              duration: const Duration(seconds: 2),
                                              behavior: SnackBarBehavior.floating,
                                              backgroundColor: AppColors.success.withOpacity(0.9),
                                              elevation: 8,
                                              margin: const EdgeInsets.all(20),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                side: BorderSide(color: Colors.white.withAlpha(40), width: 1),
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(horizontal: 24),
                                        elevation: 4,
                                      ),
                                      child: const Text('更新', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        _buildSectionLabel('メール通知・テスト送信'),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withAlpha(20)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('メール通知', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                      Text('シグナル検知を即座にメールでお知らせ', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                    ],
                                  ),
                                  Switch.adaptive(
                                    value: _ee,
                                    activeColor: AppColors.success,
                                    activeTrackColor: AppColors.success.withAlpha(100),
                                    onChanged: (v) {
                                      setState(() => _ee = v);
                                      widget.onEmailNotificationChanged(v);
                                    },
                                  ),
                                ],
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Divider(height: 1, color: Colors.white10),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('設定のテスト', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      if (await _showConfirm(title: 'テスト送信', message: '設定確認用のテストメールを送信しますか？')) {
                                        final success = await _cs.sendTestEmail(symbol: widget.symbol);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Row(
                                                children: [
                                                  Icon(
                                                    success ? Icons.mark_email_read_outlined : Icons.mail_lock_outlined,
                                                    color: Colors.white,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Text(
                                                    success ? 'テストメールを送信しました' : '送信に失敗しました',
                                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                                  ),
                                                ],
                                              ),
                                              backgroundColor: (success ? AppColors.success : AppColors.error).withOpacity(0.9),
                                              behavior: SnackBarBehavior.floating,
                                              elevation: 8,
                                              margin: const EdgeInsets.all(20),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                side: BorderSide(color: Colors.white.withAlpha(40), width: 1),
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    icon: const Icon(Icons.send_rounded, size: 16),
                                    label: const Text('送信テスト', style: TextStyle(fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white.withAlpha(20),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              const Text('配信先アドレスの登録', style: TextStyle(color: AppColors.primaryLight, fontSize: 13, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _ec,
                                      style: const TextStyle(color: Colors.white, fontSize: 15),
                                      decoration: InputDecoration(
                                        hintText: 'example@mail.com',
                                        hintStyle: const TextStyle(color: Colors.white24),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                        filled: true,
                                        fillColor: Colors.black38,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                        prefixIcon: const Icon(Icons.alternate_email, color: AppColors.textSecondary, size: 20),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  IconButton.filled(
                                    onPressed: () async {
                                      if (_ec.text.isEmpty) return;
                                      if (await _showConfirm(title: 'アドレス登録', message: 'このメールアドレスを全銘柄共通の通知先として登録しますか？')) {
                                        final success = await _cs.registerEmail(email: _ec.text, symbol: 'GLOBAL');
                                        if (success) {
                                          _ec.clear();
                                          _load();
                                        }
                                      }
                                    },
                                    icon: const Icon(Icons.add),
                                    style: IconButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      padding: const EdgeInsets.all(14),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_le)
                                const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                              else
                                ..._emails.map((e) => Container(
                                      margin: const EdgeInsets.only(top: 8),
                                      decoration: BoxDecoration(color: Colors.white.withAlpha(5), borderRadius: BorderRadius.circular(8)),
                                      child: ListTile(
                                        dense: true,
                                        contentPadding: const EdgeInsets.only(left: 16, right: 4), // 左右の余白を調整
                                        title: Text(e, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 18),
                                          onPressed: () async {
                                            if (await _showConfirm(title: 'アドレス削除', message: 'このメールアドレスを全ての通知先から削除しますか？', confirmColor: AppColors.rise)) {
                                              // 1. まず対象のアドレスを削除
                                              final success = await _cs.deleteEmail(email: e, symbol: 'GLOBAL');
                                              
                                              // 2. もしサーバーが全削除してしまった場合の保険として、
                                              // 残すべきアドレスがあれば再登録を試みる（APIの仕様に合わせて調整）
                                              // 現状はAPIが全削除してしまう挙動をしているため、個別に再送する
                                              if (success) {
                                                final remainingEmails = _emails.where((email) => email != e).toList();
                                                for (final email in remainingEmails) {
                                                  await _cs.registerEmail(email: email, symbol: 'GLOBAL');
                                                }
                                              }
                                              
                                              _load();
                                            }
                                          },
                                          style: IconButton.styleFrom(
                                            backgroundColor: AppColors.rise,
                                            elevation: 2,
                                            padding: const EdgeInsets.all(10),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ),
                                        ),
                                      ),
                                    )),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildSectionLabel('検知履歴 (${widget.interval})'),
                        if (widget.crossHistory.where((e) => e.interval == widget.interval).isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(5),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withAlpha(5)),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.history_toggle_off, color: Colors.white.withAlpha(20), size: 48),
                                const SizedBox(height: 12),
                                const Text('履歴はありません', style: TextStyle(color: Colors.white24, fontSize: 14, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          )
                        else
                          ...widget.crossHistory.where((e) => e.interval == widget.interval).take(5).map((e) {
                            final isUp = e.direction == CrossDirection.up;
                            final color = isUp ? AppColors.rise : AppColors.fall;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(12),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: color.withAlpha(40), width: 1),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  onTap: () => _showEmailContentDialog(e),
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        right: -10,
                                        top: -10,
                                        child: Icon(isUp ? Icons.trending_up : Icons.trending_down, color: color.withAlpha(15), size: 80),
                                      ),
                                      ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        leading: Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(color: color.withAlpha(30), shape: BoxShape.circle),
                                          child: Icon(isUp ? Icons.arrow_upward : Icons.arrow_downward, color: color, size: 20),
                                        ),
                                        title: Row(
                                          children: [
                                            Text(e.indicatorName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(color: color.withAlpha(40), borderRadius: BorderRadius.circular(4)),
                                              child: Text(isUp ? '上昇' : '下落', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                                            ),
                                          ],
                                        ),
                                        subtitle: Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            '価格: ${e.price.toStringAsFixed(widget.symbol.contains('JPY') ? 1 : 4)}',
                                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                          ),
                                        ),
                                        trailing: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(DateFormat('MM/dd').format(e.timestamp), style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                                            Text(DateFormat('HH:mm').format(e.timestamp), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        const SizedBox(height: 40),
                        const SafeArea(child: SizedBox(height: 10)),
                      ],
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
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12, top: 8),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      );

  List<String> _getEnabledTrendIndicators() {
    const trendKeys = ['bb', 'ema', 'sma', 'wma', 'ichimoku', 'parabolic', 'envelope', 'keltner', 'supertrend', 'gmma'];
    return trendKeys.where((k) => widget.indicators[k]?.enabled ?? false).toList();
  }

  String _getIndicatorName(String key) {
    switch (key) {
      case 'bb': return 'ボリンジャーバンド';
      case 'ema': return 'EMA';
      case 'sma': return 'SMA';
      case 'wma': return 'WMA';
      case 'ichimoku': return '一目均衡表';
      case 'parabolic': return 'パラボリック';
      case 'envelope': return 'エンベロープ';
      case 'keltner': return 'ケルトナー';
      case 'supertrend': return 'スーパートレンド';
      case 'gmma': return 'GMMA';
      default: return key.toUpperCase();
    }
  }
}
