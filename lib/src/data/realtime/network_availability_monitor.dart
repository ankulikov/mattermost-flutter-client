import 'package:connectivity_plus/connectivity_plus.dart';

enum NetworkAvailability { available, unavailable }

/// Narrow, injectable network lifecycle boundary used by realtime transport.
abstract interface class NetworkAvailabilityMonitor {
  Future<NetworkAvailability> get current;

  Stream<NetworkAvailability> get changes;
}

final class ConnectivityNetworkAvailabilityMonitor
    implements NetworkAvailabilityMonitor {
  ConnectivityNetworkAvailabilityMonitor({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<NetworkAvailability> get current async =>
      _map(await _connectivity.checkConnectivity());

  @override
  Stream<NetworkAvailability> get changes =>
      _connectivity.onConnectivityChanged.map(_map).distinct();

  static NetworkAvailability _map(List<ConnectivityResult> results) =>
      results.any(
        (ConnectivityResult result) => result != ConnectivityResult.none,
      )
      ? NetworkAvailability.available
      : NetworkAvailability.unavailable;
}
