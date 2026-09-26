import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/local_cache.dart';
import '../models/unit_category.dart';

final unitCategoriesProvider = Provider<List<UnitCategory>>((ref) {
  return UnitCatalog.categories;
});

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) => state = query;
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(SearchQueryNotifier.new);

final filteredCategoriesProvider = Provider<List<UnitCategory>>((ref) {
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final all = ref.watch(unitCategoriesProvider);
  if (query.isEmpty) return all;

  return all.where((cat) {
    final matchesName = cat.name.toLowerCase().contains(query);
    final matchesSubtitle = cat.subtitle.toLowerCase().contains(query);
    final matchesUnit = cat.units.any(
      (u) => u.name.toLowerCase().contains(query) || u.symbol.toLowerCase().contains(query),
    );
    return matchesName || matchesSubtitle || matchesUnit;
  }).toList();
});

class PrecisionNotifier extends Notifier<int> {
  @override
  int build() => 4;

  void setPrecision(int precision) => state = precision;
}

final precisionProvider = NotifierProvider<PrecisionNotifier, int>(PrecisionNotifier.new);

// Conversion History
class HistoryNotifier extends Notifier<List<ConversionRecord>> {
  @override
  List<ConversionRecord> build() {
    loadHistory();
    return [];
  }

  Future<void> loadHistory() async {
    final records = await LocalDatabaseService.getConversionHistory();
    state = records;
  }

  Future<void> addRecord({
    required String category,
    required String fromUnit,
    required String toUnit,
    required double fromValue,
    required double toValue,
  }) async {
    final record = ConversionRecord(
      id: const Uuid().v4(),
      category: category,
      fromUnit: fromUnit,
      toUnit: toUnit,
      fromValue: fromValue,
      toValue: toValue,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    await LocalDatabaseService.recordConversion(record);
    await loadHistory();
  }

  Future<void> clearHistory() async {
    await LocalDatabaseService.clearConversions();
    state = [];
  }
}

final historyProvider = NotifierProvider<HistoryNotifier, List<ConversionRecord>>(HistoryNotifier.new);

// Favorites
class FavoritesNotifier extends Notifier<List<ConversionRecord>> {
  @override
  List<ConversionRecord> build() {
    loadFavorites();
    return [];
  }

  Future<void> loadFavorites() async {
    final favs = await LocalDatabaseService.getFavorites();
    state = favs;
  }

  Future<void> toggleFav(ConversionRecord record) async {
    final newStatus = !record.isFavorite;
    await LocalDatabaseService.toggleFavorite(record.id, newStatus);
    await loadFavorites();
  }
}

final favoritesProvider = NotifierProvider<FavoritesNotifier, List<ConversionRecord>>(FavoritesNotifier.new);
