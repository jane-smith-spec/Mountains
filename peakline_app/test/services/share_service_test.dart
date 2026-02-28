import 'package:flutter_test/flutter_test.dart';
import 'package:peakline_app/services/share_service.dart';

void main() {
  group('ShareResult', () {
    test('successful result has file path', () {
      const result = ShareResult(
        success: true,
        filePath: '/tmp/test.png',
      );

      expect(result.success, true);
      expect(result.filePath, '/tmp/test.png');
      expect(result.error, isNull);
    });

    test('failed result has error message', () {
      const result = ShareResult(
        success: false,
        error: 'File not found',
      );

      expect(result.success, false);
      expect(result.filePath, isNull);
      expect(result.error, 'File not found');
    });

    test('static failed constant', () {
      expect(ShareResult.failed.success, false);
      expect(ShareResult.failed.error, isNotNull);
    });
  });

  group('ShareService', () {
    test('can be instantiated', () {
      final service = ShareService();
      expect(service, isNotNull);
    });

    // Note: captureWidget, saveToTempFile, and saveToDocuments
    // require platform channels (path_provider, file I/O) and
    // a real widget tree, so they're tested via integration tests
    // on a real device rather than unit tests.
  });
}
