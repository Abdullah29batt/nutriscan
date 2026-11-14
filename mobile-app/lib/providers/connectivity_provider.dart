import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityProvider extends ChangeNotifier {
  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  List<ConnectivityResult> _results = [ConnectivityResult.none];
  bool _showReconnectBanner = false;

  bool get isOnline =>
      _results.any((r) => r != ConnectivityResult.none);
  bool get isOffline => !isOnline;
  bool get showReconnectBanner => _showReconnectBanner;

  ConnectivityProvider() {
    _init();
  }

  Future<void> _init() async {
    _results = await _connectivity.checkConnectivity();
    _sub = _connectivity.onConnectivityChanged.listen(_onChanged);
    notifyListeners();
  }

  void _onChanged(List<ConnectivityResult> results) {
    final wasOffline = isOffline;
    _results = results;
    if (wasOffline && isOnline) {
      _showReconnectBanner = true;
      notifyListeners();
      Future.delayed(const Duration(seconds: 3), () {
        _showReconnectBanner = false;
        notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  void clearReconnectBanner() {
    _showReconnectBanner = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
