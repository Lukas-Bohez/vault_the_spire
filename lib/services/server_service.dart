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

  Future<void> updateServer(ServerModel server) async {
    final index = _servers.indexWhere((s) => s.id == server.id);
    if (index == -1) {
      _servers.add(server);
    } else {
      _servers[index] = server;
    }
    await ServerDao.instance.updateServer(server);
  }

  Future<ServerModel> addChannel(
    String serverId,
    String name, {
    bool isVoice = false,
  }) async {
    final serverIndex = _servers.indexWhere((s) => s.id == serverId);
    if (serverIndex == -1) throw StateError('Server not found');

    final server = _servers[serverIndex];
    final newChannel = ChannelModel(
      id: _uuid.v4(),
      name: name,
      isVoice: isVoice,
    );
    final updatedServer = server.copyWith(
      channels: [...server.channels, newChannel],
    );

    _servers[serverIndex] = updatedServer;
    await ServerDao.instance.updateServer(updatedServer);
    return updatedServer;
  }

  Future<void> removeChannel(String serverId, String channelId) async {
    final serverIndex = _servers.indexWhere((s) => s.id == serverId);
    if (serverIndex == -1) throw StateError('Server not found');

    final server = _servers[serverIndex];
    final updatedServer = server.copyWith(
      channels: server.channels.where((c) => c.id != channelId).toList(),
    );

    _servers[serverIndex] = updatedServer;
    await ServerDao.instance.updateServer(updatedServer);
  }

  Future<void> renameServer(String serverId, String name) async {
    final serverIndex = _servers.indexWhere((s) => s.id == serverId);
    if (serverIndex == -1) throw StateError('Server not found');

    final server = _servers[serverIndex];
    final updatedServer = server.copyWith(name: name);

    _servers[serverIndex] = updatedServer;
    await ServerDao.instance.updateServer(updatedServer);
  }

  Future<void> removeServer(String id) async {
    _servers.removeWhere((s) => s.id == id);
    await ServerDao.instance.deleteServer(id);
  }

  String generateInvite(ServerModel server) => server.id;
}
