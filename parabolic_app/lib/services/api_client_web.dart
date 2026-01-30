// Web用のHTTPクライアント（withCredentials対応）
import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart';

http.Client createClient() {
  final client = BrowserClient();
  client.withCredentials = true;
  return client;
}
