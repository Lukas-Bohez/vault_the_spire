import 'package:vault_the_spire/db/torrents_dao.dart';
import 'package:vault_the_spire/models/torrent.dart';

class TorrentService {
  TorrentService._();

  static final TorrentService instance = TorrentService._();

  Future<List<TorrentModel>> allTorrents() =>
      TorrentsDao.instance.getAllTorrents();

  Future<void> addTorrent(TorrentModel torrent) =>
      TorrentsDao.instance.insertTorrent(torrent);

  Future<void> updateTorrent(TorrentModel torrent) =>
      TorrentsDao.instance.updateTorrent(torrent);

  Future<void> removeTorrent(String id) =>
      TorrentsDao.instance.deleteTorrent(id);
}
