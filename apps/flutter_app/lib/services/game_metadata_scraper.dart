import '../models/game_metadata_candidate.dart';
import 'cover_downloader.dart';
import 'vndb_client.dart';

/// Single entry point for game metadata scraping: search and cover download.
/// Does not perform persistence; UI calls GameManager to apply results.
class GameMetadataScraper {
  GameMetadataScraper({
    VndbClient? vndbClient,
    CoverDownloader? coverDownloader,
  })  : _vndb = vndbClient ?? VndbClient(),
        _downloader = coverDownloader ?? CoverDownloader();

  final VndbClient _vndb;
  final CoverDownloader _downloader;

  /// Search by keyword (e.g. game name). Returns list of candidates.
  Future<List<GameMetadataCandidate>> search(String keyword) async {
    return _vndb.search(keyword);
  }

  /// Download cover for the selected candidate to local covers/ dir.
  /// Returns local file path or null on failure.
  Future<String?> downloadCover(GameMetadataCandidate candidate) async {
    return _downloader.downloadCover(candidate);
  }
}
