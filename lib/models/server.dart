class ServerModel {
  final String id;
  final String name;
  final String description;
  final String icon;
  final List<ChannelModel> channels;

  ServerModel({
    required this.id,
    required this.name,
    this.description = '',
    this.icon = '🛡️',
    required this.channels,
  });
}

class ChannelModel {
  final String id;
  final String name;
  final bool isVoice;

  ChannelModel({required this.id, required this.name, this.isVoice = false});
}
