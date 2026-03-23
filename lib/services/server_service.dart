import 'package:uuid/uuid.dart';
import 'package:vault_the_spire/db/server_dao.dart';
import 'package:vault_the_spire/models/server.dart';

class ServerService {
  ServerService._();
  static final ServerService instance = ServerService._();

  final _uuid = const Uuid();
  final List<ServerModel> _servers = [];

  List<ServerModel> get servers => List.unmodifiable(_servers);

  Future<void> init() async {
    _servers
      ..clear()
      ..addAll(await ServerDao.instance.getAllServers());
  }

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
    ServerDao.instance.insertServer(server);
    return server;
  }

  Future<bool> joinServer(String inviteCode) async {
    // inviteCode currently equals a server id; in future support real invite tokens.
    final existing = _servers.firstWhere(
      (s) => s.id == inviteCode,
      orElse: () => ServerModel(id: '', name: '', channels: []),
    );

    if (existing.id.isNotEmpty) {
      return true;
    }

    final server = await ServerDao.instance.getServerById(inviteCode);
    if (server == null) return false;

    _servers.add(server);
    return true;
  }

  Future<void> removeServer(String id) async {
    _servers.removeWhere((s) => s.id == id);
    await ServerDao.instance.deleteServer(id);
  }

  String generateInvite(ServerModel server) => server.id;
}
