class TorrentModel {
  final String id;
  final String name;
  final int? totalSize;
  final int? totalPieces;
  final int? pieceLength;
  final String? piecesHave;
  final String? status;
  final String type;
  final String? vaultKey;
  final String? filePath;
  final String? vaultLink;
  final String? magnetLink;
  final int bytesDown;
  final int bytesUp;
  final int? addedAt;
  final int? completedAt;
  final bool isSequential;
  final String? selectedFiles;
  final double? maxSeedRatio;
  final bool deleteAfterRatioReached;

  TorrentModel({
    required this.id,
    required this.name,
    required this.type,
    this.totalSize,
    this.totalPieces,
    this.pieceLength,
    this.piecesHave,
    this.status,
    this.vaultKey,
    this.filePath,
    this.vaultLink,
    this.magnetLink,
    this.bytesDown = 0,
    this.bytesUp = 0,
    this.addedAt,
    this.completedAt,
    this.isSequential = false,
    this.selectedFiles,
    this.maxSeedRatio,
    this.deleteAfterRatioReached = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'total_size': totalSize,
      'total_pieces': totalPieces,
      'piece_length': pieceLength,
      'pieces_have': piecesHave,
      'status': status,
      'type': type,
      'vault_key': vaultKey,
      'file_path': filePath,
      'vault_link': vaultLink,
      'magnet_link': magnetLink,
      'bytes_down': bytesDown,
      'bytes_up': bytesUp,
      'added_at': addedAt,
      'completed_at': completedAt,
      'is_sequential': isSequential ? 1 : 0,
      'selected_files': selectedFiles,
      'max_seed_ratio': maxSeedRatio,
      'delete_after_ratio_reached': deleteAfterRatioReached ? 1 : 0,
    };
  }

  factory TorrentModel.fromMap(Map<String, dynamic> map) {
    return TorrentModel(
      id: map['id'] as String,
      name: map['name'] as String,
      type: map['type'] as String,
      totalSize: map['total_size'] as int?,
      totalPieces: map['total_pieces'] as int?,
      pieceLength: map['piece_length'] as int?,
      piecesHave: map['pieces_have'] as String?,
      status: map['status'] as String?,
      vaultKey: map['vault_key'] as String?,
      filePath: map['file_path'] as String?,
      vaultLink: map['vault_link'] as String?,
      magnetLink: map['magnet_link'] as String?,
      bytesDown: map['bytes_down'] as int? ?? 0,
      bytesUp: map['bytes_up'] as int? ?? 0,
      addedAt: map['added_at'] as int?,
      completedAt: map['completed_at'] as int?,
      isSequential: (map['is_sequential'] as int? ?? 0) == 1,
      selectedFiles: map['selected_files'] as String?,
      maxSeedRatio: (map['max_seed_ratio'] as num?)?.toDouble(),
      deleteAfterRatioReached:
          (map['delete_after_ratio_reached'] as int? ?? 0) == 1,
    );
  }
}
