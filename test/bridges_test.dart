import 'package:flutter_test/flutter_test.dart';
import 'package:vault_the_spire/bridges/signal_qr.dart';
import 'package:vault_the_spire/bridges/telegram_bridge.dart';

void main() {
  test('Signal QR parse returns contact', () {
    final qr = 'https://signal.me/#p/abcd1234ABCD5678';
    final contact = SignalQrImport.tryParse(qr);
    expect(contact, isNotNull);
    expect(contact!.publicKey, 'abcd1234ABCD5678');
  });

  test('Telegram channel name extraction', () {
    final ch1 = TelegramBridge.extractChannelName('https://t.me/channelname');
    final ch2 = TelegramBridge.extractChannelName('t.me/channelname');
    final ch3 = TelegramBridge.extractChannelName('@channelname');
    expect(ch1, 'channelname');
    expect(ch2, 'channelname');
    expect(ch3, 'channelname');
  });
}
