import 'package:uuid/uuid.dart';
import 'package:vault_the_spire/models/server.dart';

class ServerService {
  ServerService._();
  static final ServerService instance = ServerService._();

  final _uuid = const Uuid();
  final List<ServerModel> _servers = [];

  List<ServerModel> get servers => List.unmodifiable(_servers);

  ServerModel createServer({required String name, String description = ''}) {
    final server = ServerModel(
      id: _uuid.v4(),
      name: name,
      description: description,
      channels: [
        ChannelModel(id: _uuid.v4(), name: 'general', isVoice: false),
        ChannelModel(id: _uuid.v4(), name: 'voice-1', isVoice: true),
      ],
    );
    _servers.add(server);
    return server;
  }

  bool joinServer(String inviteCode) {
    // shim: accept any code that matches a server id.
    final server = _servers.firstWhere(
      (s) => s.id == inviteCode,
      orElse: () => ServerModel(id: '', name: '', channels: []),
    );
    return server.id.isNotEmpty;
  }

  String generateInvite(ServerModel server) => server.id;
}
