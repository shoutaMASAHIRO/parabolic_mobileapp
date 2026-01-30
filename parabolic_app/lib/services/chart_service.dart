import '../models/candle.dart';
import 'api_service.dart';

class ChartService {
  final ApiService _api = ApiService();

  Future<List<Candle>> getChartData(String symbol, {String interval = '1d'}) async {
    final response = await _api.get('/api/data?ticker=$symbol&interval=$interval');

    if (response.isSuccess && response.jsonList != null) {
      return response.jsonList!
          .map((json) => Candle.fromJson(json as Map<String, dynamic>))
          .toList();
    }

    return [];
  }
}
