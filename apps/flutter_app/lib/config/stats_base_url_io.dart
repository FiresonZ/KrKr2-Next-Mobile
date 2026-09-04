import 'dart:io' show Platform;

/// 本地统计服务根 URL。Android 模拟器用 10.0.2.2，其余用 127.0.0.1。
String get statsBaseUrl {
  if (Platform.isAndroid) return 'http://10.0.2.2:8080';
  return 'http://127.0.0.1:8080';
}
