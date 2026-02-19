import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../services/memo_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class MemoScreen extends StatefulWidget {
  final String symbol;

  const MemoScreen({super.key, required this.symbol});

  @override
  State<MemoScreen> createState() => _MemoScreenState();
}

class _MemoScreenState extends State<MemoScreen> {
  final MemoService _memoService = MemoService();
  List<Memo> _memos = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMemos();
  }

  Future<void> _loadMemos() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final memos = await _memoService.getMemos(widget.symbol);
      if (mounted) {
        setState(() {
          _memos = memos;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showMemoInput({Memo? existingMemo}) async {
    final controller = TextEditingController(text: existingMemo?.content);
    final isEditing = existingMemo != null;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 500),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEditing ? 'メモを編集' : '新規メモ',
                    style: AppTextStyles.headline3,
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                maxLines: 8,
                style: AppTextStyles.body1,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'ここにメモを入力...',
                  hintStyle: AppTextStyles.bodySecondary,
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, controller.text),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    isEditing ? '更新する' : '保存する',
                    style: AppTextStyles.button.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      if (isEditing) {
        if (result != existingMemo.content) {
          final success = await _memoService.updateMemo(existingMemo.id, result);
          if (success) _loadMemos();
        }
      } else {
        final memo = await _memoService.createMemo(widget.symbol, result);
        if (mounted) {
          if (memo != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('メモを保存しました'),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
              ),
            );
            _loadMemos();
          }
        }
      }
    }
  }

  Future<void> _deleteMemo(Memo memo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('メモを削除', style: AppTextStyles.headline3),
        content: Text('このメモを削除しますか？\nこの操作は取り消せません。', style: AppTextStyles.body2),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _memoService.deleteMemo(memo.id);
      if (success) {
        _loadMemos();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.symbol.replaceAll('-USD', '').replaceAll('=X', '');

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppColors.scaffoldBackground,
        elevation: 0,
        title: Text('$displayName メモ', style: AppTextStyles.headline3),
        centerTitle: true,
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showMemoInput(),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white, size: 30),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text(_error!, style: AppTextStyles.bodySecondary, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadMemos,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('再試行'),
              ),
            ],
          ),
        ),
      );
    }

    if (_memos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.edit_note, size: 64, color: AppColors.primary.withOpacity(0.5)),
            ),
            const SizedBox(height: 24),
            Text('メモがありません', style: AppTextStyles.headline3.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Text(
              '分析内容や気づきを記録しましょう',
              style: AppTextStyles.bodySecondary,
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    final todayMemos = _memos.where((m) {
      final memoDate = DateTime(m.updatedAt.year, m.updatedAt.month, m.updatedAt.day);
      return memoDate.isAtSameMomentAs(today);
    }).toList();
    
    final pastMemos = _memos.where((m) {
      final memoDate = DateTime(m.updatedAt.year, m.updatedAt.month, m.updatedAt.day);
      return memoDate.isBefore(today);
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadMemos,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          if (todayMemos.isNotEmpty) ...[
            _buildSectionHeader('今日のメモ', Icons.today, AppColors.primaryLight),
            ...todayMemos.map((memo) => _buildMemoCard(memo)),
          ],
          if (pastMemos.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSectionHeader('過去のメモ', Icons.history, AppColors.textSecondary),
            ...pastMemos.map((memo) => _buildMemoCard(memo)),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 16, bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: AppTextStyles.label.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: color.withOpacity(0.2))),
        ],
      ),
    );
  }

  Widget _buildMemoCard(Memo memo) {
    final dateStr = DateFormat('yyyy年MM月dd日 HH:mm').format(memo.updatedAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showMemoInput(existingMemo: memo),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time, size: 14, color: AppColors.primaryLight),
                            const SizedBox(width: 6),
                            Text(
                              dateStr,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.primaryLight,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => _deleteMemo(memo),
                          color: AppColors.error,
                          tooltip: '削除',
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    memo.content,
                    style: AppTextStyles.body1.copyWith(
                      height: 1.6,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
