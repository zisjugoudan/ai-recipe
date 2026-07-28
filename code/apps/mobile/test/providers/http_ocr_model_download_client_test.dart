import 'package:ai_recipe/providers/ocr/http_ocr_model_download_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test(
    'disables redirects so trusted-host validation cannot be bypassed',
    () async {
      late http.BaseRequest captured;
      final client = _CapturingClient((request) async {
        captured = request;
        return http.StreamedResponse(
          const Stream<List<int>>.empty(),
          302,
          request: request,
        );
      });
      final downloadClient = HttpOcrModelDownloadClient(client: client);

      final response = await downloadClient.open(
        Uri.parse('https://models.example.test/model.onnx'),
      );

      expect(response.statusCode, 302);
      expect(captured.followRedirects, isFalse);
    },
  );
}

class _CapturingClient extends http.BaseClient {
  _CapturingClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _handler(request);
  }
}
