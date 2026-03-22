import 'dart:async';
import 'dart:developer' as developer;

/// Desktop notification polling fallback for platforms where FCM is unavailable.
///
/// Phase 11 requirement: Windows/macOS/Linux should poll our backend for pending
/// inbound signals/notifications when push service is not available.
///
/// This implementation is intentionally minimal and server-agnostic.
class DesktopNotificationPoller {
  static final DesktopNotificationPoller instance =
      DesktopNotificationPoller._();

  Timer? _timer;

  DesktopNotificationPoller._();

  void start() {
    _timer ??= Timer.periodic(Duration(seconds: 30), (_) => _poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    // TODO: Implement backend poll endpoint in server service:
    //  GET https://quizthespire.com/vault/api/notify/poll?username=<me>
    // and process returned wake notifications.

    // TODO: Add integration with the vault messaging/p2p service to open intent.
    // For now we log for visibility and keep the loop alive.
    developer.log('[DesktopNotificationPoller] polling for notifications ...');

    // Example placeholder response handling:
    // final items = await NotificationApi.instance.fetchPendingDesktopWakes();
    // for (final wake in items) {
    //   await _showNotification(wake.fromUsername, wake.message);
    //   p2pService.acceptConnection(wake.fromUsername, wake.roomCode);
    // }
  }
}
