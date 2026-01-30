import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../services/memo_service.dart';

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

  Future<void> _showAddMemoDialog() async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('メモを追加'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'メモを入力...',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final memo = await _memoService.createMemo(widget.symbol, result);
      if (mounted) {
        if (memo != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('メモを保存しました'), backgroundColor: Colors.green),
          );
          _loadMemos();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('メモの保存に失敗しました'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _showEditMemoDialog(Memo memo) async {
    final controller = TextEditingController(text: memo.content);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('メモを編集'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != memo.content) {
      final success = await _memoService.updateMemo(memo.id, result);
      if (success) {
        _loadMemos();
      }
    }
  }

  Future<void> _deleteMemo(Memo memo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('メモを削除'),
        content: const Text('このメモを削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('削除'),
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
    final displayName = widget.symbol.replaceAll('-USD', '');

    return Scaffold(
      appBar: AppBar(
        title: Text('$displayName メモ'),
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddMemoDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadMemos,
              child: const Text('再試行'),
            ),
          ],
        ),
      );
    }

    if (_memos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.note_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'メモがありません',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              '右下の + ボタンでメモを追加できます',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMemos,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _memos.length,
        itemBuilder: (context, index) {
          final memo = _memos[index];
          return _buildMemoCard(memo);
        },
      ),
    );
  }

  Widget _buildMemoCard(Memo memo) {
    final dateFormat = DateFormat('yyyy/MM/dd HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showEditMemoDialog(memo),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      dateFormat.format(memo.updatedAt),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _deleteMemo(memo),
                    color: Colors.grey.shade600,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                memo.content,
                style: const TextStyle(fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
