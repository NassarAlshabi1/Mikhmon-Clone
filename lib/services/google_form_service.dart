import 'package:dio/dio.dart';

class GoogleFormService {
  static const String _formUrl =
      'https://docs.google.com/forms/d/e/1FAIpQLSc4y5k40sMypISeOszwHkAGY5VQNOJgoOz7WM_14knVJgtXiQ/formResponse';

  static const String entryName = 'entry.397889645';
  static const String entryFeedback = 'entry.1590769829';

  static final Dio _dio = Dio(BaseOptions(
    headers: {
      'User-Agent': 'Mozilla/5.0',
      'Content-Type': 'application/x-www-form-urlencoded',
    },
  ));

  static Future<bool> submitFeedback({
    required String name,
    required String feedback,
  }) async {
    try {
      final response = await _dio.post(
        _formUrl,
        data: {
          entryName: name,
          entryFeedback: feedback,
          'fvv': '1',
          'pageHistory': '0',
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
