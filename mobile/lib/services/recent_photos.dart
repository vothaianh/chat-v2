import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// New camera-roll images since the last time Volt showed the chat tray.
class RecentPhotos {
  static const _seenKey = 'volt_photo_tray_seen_ms';
  static const _lookback = Duration(hours: 24);
  static const _justNow = Duration(minutes: 5);
  static const _perm = PermissionRequestOption(iosAccessLevel: IosAccessLevel.readWrite);
  static final _dismissed = <String>{};

  static DateTime _takenAt(AssetEntity a) {
    final created = a.createDateTime;
    final modified = a.modifiedDateTime;
    return modified.isAfter(created) ? modified : created;
  }

  /// Photos taken in the last 24 hours that the tray has not dismissed yet.
  static Future<List<AssetEntity>> loadNew({bool promptIfNeeded = false}) async {
    var perm = await PhotoManager.getPermissionState(requestOption: _perm);
    if (!perm.hasAccess) {
      if (!promptIfNeeded && perm == PermissionState.denied) return const [];
      perm = await PhotoManager.requestPermissionExtend(requestOption: _perm);
      if (!perm.hasAccess) return const [];
    }

    await PhotoManager.clearFileCache();
    final filter = FilterOptionGroup(
      imageOption: const FilterOption(needTitle: true, sizeConstraint: SizeConstraint(ignoreSize: true)),
      orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
      updateTimeCond: DateTimeCond(min: DateTime.now().subtract(_lookback), max: DateTime.now().add(const Duration(minutes: 2))),
    );
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      filterOption: filter,
    );
    if (albums.isEmpty) return const [];

    final byId = <String, AssetEntity>{};
    Future<void> take(AssetPathEntity album, int n) async {
      final page = await album.getAssetListPaged(page: 0, size: n);
      for (final a in page) {
        byId[a.id] = a;
      }
    }

    AssetPathEntity? all;
    for (final p in albums) {
      if (p.isAll) all = p;
    }
    if (all != null) await take(all, 40);
    for (final p in albums) {
      final name = p.name.toLowerCase();
      if (name.contains('screenshot') || name.contains('screen shot')) {
        await take(p, 20);
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final seenMs = prefs.getInt(_seenKey) ?? 0;
    final cutoff = DateTime.now().subtract(_lookback);
    final recentCut = DateTime.now().subtract(_justNow);
    final fresh = <AssetEntity>[];
    for (final a in byId.values) {
      if (_dismissed.contains(a.id)) continue;
      final when = _takenAt(a);
      if (when.isBefore(cutoff)) continue;
      final ms = when.millisecondsSinceEpoch;
      final isJustNow = !when.isBefore(recentCut);
      if (ms <= seenMs && !isJustNow) continue;
      fresh.add(a);
    }
    if (fresh.isEmpty) return const [];
    fresh.sort((a, b) => _takenAt(b).compareTo(_takenAt(a)));
    return [fresh.first];
  }

  static Future<void> markSeen(Iterable<AssetEntity> assets) async {
    var maxMs = 0;
    for (final a in assets) {
      _dismissed.add(a.id);
      final ms = _takenAt(a).millisecondsSinceEpoch;
      if (ms > maxMs) maxMs = ms;
    }
    if (maxMs <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final prev = prefs.getInt(_seenKey) ?? 0;
    if (maxMs > prev) await prefs.setInt(_seenKey, maxMs);
  }
}
