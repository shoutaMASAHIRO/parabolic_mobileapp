// モバイル/デスクトップ用のHTTPクライアント
import 'package:http/http.dart' as http;

http.Client createClient() {
  return http.Client();
}
