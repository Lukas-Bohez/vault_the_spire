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
    // inviteCode currently equals a server id; in future support real invite tokens.
    final server = _servers.firstWhere(
      (s) => s.id == inviteCode,
      orElse: () => ServerModel(id: '', name: '', channels: []),
    );
    if (server.id.isEmpty) return false;

    // Already known server from local list: success.
    final exists = _servers.any((s) => s.id == server.id);
    if (!exists) {
      _servers.add(server);
    }

    return true;
  }

  String generateInvite(ServerModel server) => server.id;
}
