import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../core/constants/app_constants.dart';
import 'auth_storage.dart';

typedef SocketListenerId = int;

/// Socket.IO client with **multicast** listeners so screens can subscribe/unsubscribe
/// without wiping handlers registered by other screens (e.g. dashboard + live map).
class SocketService {
  static io.Socket? _socket;
  static bool _isConnected = false;
  static int _listenerSeq = 0;

  static final Map<int, void Function(Map<String, dynamic>)> _newReportListeners = {};
  static final Map<int, void Function(Map<String, dynamic>)> _flaggedReportListeners = {};
  static final Map<int, void Function(Map<String, dynamic>)> _staffLocationListeners = {};
  static final Map<int, void Function(Map<String, dynamic>)> _staffCheckInListeners = {};
  static final Map<int, void Function(Map<String, dynamic>)> _staffCheckOutListeners = {};
  static final Map<int, void Function(Map<String, dynamic>)> _staffTrackingStatusListeners = {};
  static final Map<int, void Function(Map<String, dynamic>)> _orgUpdatedListeners = {};

  static SocketListenerId onNewReport(void Function(Map<String, dynamic>) listener) =>
      _add(_newReportListeners, listener);

  static SocketListenerId onFlaggedReport(void Function(Map<String, dynamic>) listener) =>
      _add(_flaggedReportListeners, listener);

  static SocketListenerId onStaffLocation(void Function(Map<String, dynamic>) listener) =>
      _add(_staffLocationListeners, listener);

  static SocketListenerId onStaffCheckIn(void Function(Map<String, dynamic>) listener) =>
      _add(_staffCheckInListeners, listener);

  static SocketListenerId onStaffCheckOut(void Function(Map<String, dynamic>) listener) =>
      _add(_staffCheckOutListeners, listener);

  static SocketListenerId onStaffTrackingStatus(void Function(Map<String, dynamic>) listener) =>
      _add(_staffTrackingStatusListeners, listener);

  static SocketListenerId onOrgUpdated(void Function(Map<String, dynamic>) listener) =>
      _add(_orgUpdatedListeners, listener);

  static void off(SocketListenerId id) {
    _newReportListeners.remove(id);
    _flaggedReportListeners.remove(id);
    _staffLocationListeners.remove(id);
    _staffCheckInListeners.remove(id);
    _staffCheckOutListeners.remove(id);
    _staffTrackingStatusListeners.remove(id);
    _orgUpdatedListeners.remove(id);
  }

  static SocketListenerId _add(
    Map<int, void Function(Map<String, dynamic>)> map,
    void Function(Map<String, dynamic>) listener,
  ) {
    final id = ++_listenerSeq;
    map[id] = listener;
    return id;
  }

  static void _broadcast(
    Map<int, void Function(Map<String, dynamic>)> map,
    dynamic data,
  ) {
    if (data is! Map) return;
    final payload = Map<String, dynamic>.from(data);
    for (final cb in map.values) {
      cb(payload);
    }
  }

  static Future<void> connect() async {
    if (_isConnected && _socket != null) return;
    final token = await AuthStorage.getToken();
    if (token == null) return;

    _socket?.dispose();
    _socket = io.io(
      AppConstants.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setAuth({'token': token})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(2000)
          .build(),
    );

    _socket!.onConnect((_) {
      _isConnected = true;
      debugPrint('Socket connected');
    });
    _socket!.onDisconnect((_) {
      _isConnected = false;
      debugPrint('Socket disconnected');
    });
    _socket!.on('report:new', (d) => _broadcast(_newReportListeners, d));
    _socket!.on('report:flagged', (d) => _broadcast(_flaggedReportListeners, d));
    _socket!.on('staff:location', (d) => _broadcast(_staffLocationListeners, d));
    _socket!.on('staff:checkin', (d) => _broadcast(_staffCheckInListeners, d));
    _socket!.on('staff:checkout', (d) => _broadcast(_staffCheckOutListeners, d));
    _socket!.on('staff:tracking_status', (d) => _broadcast(_staffTrackingStatusListeners, d));
    _socket!.on('org:updated', (d) => _broadcast(_orgUpdatedListeners, d));
    _socket!.connect();
  }

  static void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
    _newReportListeners.clear();
    _flaggedReportListeners.clear();
    _staffLocationListeners.clear();
    _staffCheckInListeners.clear();
    _staffCheckOutListeners.clear();
    _staffTrackingStatusListeners.clear();
    _orgUpdatedListeners.clear();
  }

  static bool get isConnected => _isConnected;
}
