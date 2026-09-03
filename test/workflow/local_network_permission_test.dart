import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/workflow/local_network_permission.dart';
import 'package:sitemark_system_api/sitemark_system_api.dart';

class _FakePermission implements LocalNetworkPermission {
  _FakePermission({
    required this.currentState,
    this.requestResult = LocationPermissionState.granted,
  });

  LocationPermissionState currentState;
  LocationPermissionState requestResult;
  int requestCount = 0;

  @override
  Future<LocationPermissionState> current() async => currentState;

  @override
  Future<LocationPermissionState> request() async {
    requestCount++;
    currentState = requestResult;
    return requestResult;
  }
}

void main() {
  test('public hosts skip the local-network permission prompt', () async {
    final permission = _FakePermission(
      currentState: LocationPermissionState.denied,
    );
    final access = LocalNetworkAccess(permission);

    expect(await access.ensureForHost('nas.example.com'), isTrue);
    expect(permission.requestCount, 0);
  });

  test('LAN hosts that are already granted skip the prompt', () async {
    final permission = _FakePermission(
      currentState: LocationPermissionState.granted,
    );
    final access = LocalNetworkAccess(permission);

    expect(await access.ensureForHost('192.168.1.10'), isTrue);
    expect(permission.requestCount, 0);
  });

  test('LAN hosts request permission and continue when granted', () async {
    final permission = _FakePermission(
      currentState: LocationPermissionState.denied,
      requestResult: LocationPermissionState.granted,
    );
    final access = LocalNetworkAccess(permission);

    expect(await access.ensureForHost('192.168.1.10'), isTrue);
    expect(permission.requestCount, 1);
  });

  test('LAN hosts that stay denied cannot be reached', () async {
    final permission = _FakePermission(
      currentState: LocationPermissionState.denied,
      requestResult: LocationPermissionState.denied,
    );
    final access = LocalNetworkAccess(permission);

    expect(await access.ensureForHost('10.0.0.5'), isFalse);
    expect(permission.requestCount, 1);
  });

  test('permanently denied LAN hosts do not re-prompt', () async {
    final permission = _FakePermission(
      currentState: LocationPermissionState.permanentlyDenied,
    );
    final access = LocalNetworkAccess(permission);

    expect(await access.ensureForHost('nas.local'), isFalse);
    expect(permission.requestCount, 0);
  });
}
