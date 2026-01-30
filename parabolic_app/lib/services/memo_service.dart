import 'package:flutter/foundation.dart';
import '../models/user.dart';
import 'api_service.dart';

class MemoService {
  final ApiService _api = ApiService();

  Future<List<Memo>> getMemos(String symbol) async {
    final response = await _api.get('/api/memos/$symbol');

    debugPrint('getMemos response: ${response.statusCode} - ${response.body}');

    if (response.isSuccess && response.jsonList != null) {
      return response.jsonList!
          .map((json) => Memo.fromJson(json as Map<String, dynamic>))
          .toList();
    }

    return [];
  }

  Future<Memo?> createMemo(String symbol, String content) async {
    final response = await _api.post('/api/memos', {
      'symbol': symbol,
      'content': content,
    });

    debugPrint('createMemo response: ${response.statusCode} - ${response.body}');

    if (response.isSuccess && response.json != null) {
      return Memo.fromJson(response.json!);
    }

    return null;
  }

  Future<bool> updateMemo(int id, String content) async {
    final response = await _api.put('/api/memos/$id', {
      'content': content,
    });

    return response.isSuccess;
  }

  Future<bool> deleteMemo(int id) async {
    final response = await _api.delete('/api/memos/$id');
    return response.isSuccess;
  }
}
