import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/nas_sync.dart';

void main() {
  test('nasRemoteFileName uses the photo number as a jpeg', () {
    expect(nasRemoteFileName('003'), '003.jpg');
  });

  group('isLanNasHost', () {
    test('treats RFC1918, loopback, link-local and .local as LAN', () {
      expect(isLanNasHost('192.168.1.10'), isTrue);
      expect(isLanNasHost('10.0.0.5'), isTrue);
      expect(isLanNasHost('172.16.0.1'), isTrue);
      expect(isLanNasHost('172.31.255.255'), isTrue);
      expect(isLanNasHost('127.0.0.1'), isTrue);
      expect(isLanNasHost('localhost'), isTrue);
      expect(isLanNasHost('nas.local'), isTrue);
      expect(isLanNasHost('NAS.LOCAL'), isTrue);
      expect(isLanNasHost('169.254.1.1'), isTrue);
      expect(isLanNasHost('nas'), isTrue);
      expect(isLanNasHost('fd12:3456::1'), isTrue);
      expect(isLanNasHost('fe80::1'), isTrue);
    });

    test('treats public addresses and public hostnames as not LAN', () {
      expect(isLanNasHost('8.8.8.8'), isFalse);
      expect(isLanNasHost('nas.example.com'), isFalse);
      expect(isLanNasHost('quickconnect.to'), isFalse);
      expect(isLanNasHost('172.32.0.1'), isFalse);
      expect(isLanNasHost('fc.example.com'), isFalse);
      expect(isLanNasHost(''), isFalse);
    });
  });
}
