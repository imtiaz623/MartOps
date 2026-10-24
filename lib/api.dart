import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Paste your deployed Apps Script /exec URL.
const kApiUrl = 'PASTE_APPS_SCRIPT_EXEC_URL';

/// Apps Script answers POST with a 302 redirect; Dart does not follow it for POST, so we do it by hand.
Future<Map> rawCall(String? token, String action, [Map<String, dynamic>? data]) async {
  final client = http.Client();
  try {
    final req = http.Request('POST', Uri.parse(kApiUrl))
      ..followRedirects = false
      ..headers['Content-Type'] = 'text/plain'
      ..body = jsonEncode({'action': action, 'token': token, ...?data});
    var res = await http.Response.fromStream(await client.send(req).timeout(const Duration(seconds: 30)));
    if (res.statusCode >= 300 && res.statusCode < 400 && res.headers['location'] != null) {
      res = await http.get(Uri.parse(res.headers['location']!));
    }
    return jsonDecode(res.body) as Map;
  } catch (e) {
    return {'ok': false, 'error': 'network'};
  } finally {
    client.close();
  }
}

class Session {
  static String? token, role, name, userId, companyName, companyCode;

  static Future<void> save(Map r) async {
    token = r['token']; role = r['role']; name = r['name']; userId = r['userId'];
    companyName = r['company']['name']; companyCode = r['company']['code'];
    final p = await SharedPreferences.getInstance();
    await p.setString('session', jsonEncode({'token': token, 'role': role, 'name': name, 'userId': userId, 'cn': companyName, 'cc': companyCode}));
  }

  static Future<bool> restore() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('session');
    if (s == null) return false;
    final m = jsonDecode(s);
    token = m['token']; role = m['role']; name = m['name']; userId = m['userId']; companyName = m['cn']; companyCode = m['cc'];
    return true;
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('session'); await p.remove('cfg'); await p.remove('leftAt');
    token = null; role = null;
  }

  static Future<Map> call(String action, [Map<String, dynamic>? data]) => rawCall(token, action, data);
}
