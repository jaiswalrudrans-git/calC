import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

void main() {
  test('Google Drive types and auth client verification', () {
    final client = GoogleAuthClient({'Authorization': 'Bearer test'});
    final driveApi = drive.DriveApi(client);
    expect(driveApi, isNotNull);
    expect(drive.DriveApi.driveFileScope, equals('https://www.googleapis.com/auth/drive.file'));
  });
}
