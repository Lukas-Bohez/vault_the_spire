import 'package:vault_the_spire/services/search_service.dart';

class AiTriggerEvent {
  final String prompt;
  final bool auto;

  const AiTriggerEvent({required this.prompt, this.auto = true});
}

class AiTriggers {
  AiTriggerEvent onResultSelected(SearchResult result) {
    return AiTriggerEvent(
      prompt:
          'The user is looking at ${result.name}. Give a brief overview: what it likely is, estimated quality, and any red flags based on seeders/leechers ratio and age.',
    );
  }

  AiTriggerEvent onDownloadStarted({required String name, required String size}) {
    return AiTriggerEvent(
      prompt:
          'The user just started downloading $name ($size). Any tips on what to expect, file structure, or how long it might take at typical speeds?',
    );
  }

  AiTriggerEvent onDownloadCompleted(String name) {
    return AiTriggerEvent(
      prompt:
          'The user finished downloading $name. What are the next steps - how do they typically use or play this type of file?',
    );
  }

  AiTriggerEvent onZeroResults(String query) {
    return AiTriggerEvent(
      prompt:
          "The user searched for '$query' and got no results. Suggest 3 alternative search terms or strategies.",
    );
  }

  AiTriggerEvent onCategoryChanged(String category) {
    return AiTriggerEvent(
      prompt:
          'The user is now browsing $category. What should they know about finding quality torrents in this category?',
    );
  }
}
