import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../bridge/rust_bridge.dart';
import '../models/track.dart';

final tracksProvider = FutureProvider.autoDispose<List<Track>>((ref) async {
  return RustBridge.instance.listTracks();
});

final albumsProvider = FutureProvider.autoDispose<List<Album>>((ref) async {
  return RustBridge.instance.listAlbums();
});

final artistsProvider = FutureProvider.autoDispose<List<Artist>>((ref) async {
  return RustBridge.instance.listArtists();
});

final playlistsProvider = FutureProvider.autoDispose<List<Playlist>>((ref) async {
  return RustBridge.instance.listPlaylists();
});

final recentlyPlayedProvider = FutureProvider.autoDispose<List<Track>>((ref) async {
  return RustBridge.instance.getRecentlyPlayed();
});

final favoritesProvider = FutureProvider.autoDispose<List<Track>>((ref) async {
  return RustBridge.instance.getFavorites();
});

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider.autoDispose<List<Track>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) return [];
  await Future.delayed(const Duration(milliseconds: 150));
  return RustBridge.instance.searchTracks(query);
});
