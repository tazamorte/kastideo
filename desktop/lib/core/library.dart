import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'details.dart';
import 'epg.dart';
import 'replay.dart';
import 'local_media.dart';
import 'log.dart';
import 'm3u.dart';
import 'media_servers.dart';
import 'countries.dart';
import 'models.dart';
import 'secrets.dart';
import 'settings.dart';
import 'text.dart';
import 'themes.dart';
import 'xtream.dart';
import '../l10n.dart';

/// Fiche trouvée sur TMDB pour un fichier local (affiche, résumé, année, genres).
typedef LocalFiche = ({String? logo, String? info, int? year, List<String> genres});

/// Bibliothèque : sources, contenus (mis en cache sur disque), favoris, récents et catégories personnalisées.
class LibraryStore extends ChangeNotifier {
  final List<Source> sources = [];
  final Map<String, List<MediaItem>> _contentBySource = {};
  final Map<MediaKind, List<MediaItem>> _byKind = {};
  final Map<MediaKind, List<String>> _categories = {};
  final Map<MediaKind, List<String>> _allCategories = {};
  final Map<String, List<MediaItem>> _byCategory = {};
  final Map<String, MediaItem> _byId = {};

  /// Épisodes lus (absents de l'index principal), pour les récents et les favoris.
  final Map<String, MediaItem> _extras = {};
  final Map<MediaKind, CategoryPrefs> _categoryPrefs = {};
  List<String> favoriteIds = [];
  List<String> recentIds = [];
  bool isBusy = false;
  String? lastError;

  /// Réglages de l'application (replay).
  AppSettings? settings;

  /// Contenus adultes (« |XX| », catégorie adulte) : masqués partout tant que l'option est désactivée.
  bool showAdult = false;

  /// Corrections des chaînes (par identifiant de chaîne).
  final Map<String, ChannelEdit> channelEdits = {};

  /// Chaîne telle que fournie par la source (sans correction).
  MediaItem? originalItem(String id) {
    for (final list in _contentBySource.values) {
      for (final i in list) {
        if (i.id == id) return i;
      }
    }
    return null;
  }

  void setChannelEdit(String id, ChannelEdit? edit) {
    if (edit == null || edit.isEmpty) {
      channelEdits.remove(id);
    } else {
      channelEdits[id] = edit;
    }
    _prefs.setString('channelEdits.v1', jsonEncode({for (final e in channelEdits.entries) e.key: e.value.toJson()}));
    _rebuild();
  }

  /// Change à chaque reconstruction de l'index (le guide TV recalcule alors ses chaînes).
  int liveGeneration = 0;

  /// Appelé après l'actualisation réussie d'une source (rechargement de son guide TV).
  void Function(Source source)? onSourceRefreshed;
  void Function(String sourceId)? onSourceRemoved;

  /// Positions de lecture reçues d'un serveur (Jellyfin, Emby, Plex) : reprises dans la mémoire de reprise.
  void Function(Map<String, (double, double)> progress)? onUserData;

  /// Contenu d'une source chargé (fiches TMDB automatiques des fichiers locaux).
  void Function(Source source)? onContentLoaded;

  /// Épisodes des séries trouvées dans les dossiers locaux (identifiant de la série → épisodes).
  final Map<String, List<MediaItem>> _localEpisodes = {};

  Timer? _rescan;

  @override
  void dispose() {
    _rescan?.cancel();
    super.dispose();
  }

  /// Clients des serveurs multimédias (un par source).
  final Map<String, MediaServerClient> _servers = {};

  late SharedPreferences _prefs;
  final _secrets = Secrets.shared;
  late Directory _cacheDir;

  static const categoryKinds = [MediaKind.live, MediaKind.movie, MediaKind.series];

  /// Tests : charge des sources et leur contenu sans passer par le réseau ni le disque.
  @visibleForTesting
  Future<void> debugLoad(List<Source> list, Map<String, List<MediaItem>> content) async {
    _prefs = await SharedPreferences.getInstance();
    sources
      ..clear()
      ..addAll(list);
    _contentBySource
      ..clear()
      ..addAll(content);
    activeSourceId = _prefs.getString('catalog.source');
    dedupe = _prefs.getBool('catalog.dedupe') ?? true;
    _rebuild();
  }

  Future<void> start({bool autoRefresh = true}) async {
    _prefs = await SharedPreferences.getInstance();
    final support = await getApplicationSupportDirectory();
    _cacheDir = Directory('${support.path}${Platform.pathSeparator}library');
    await _cacheDir.create(recursive: true);
    final raw = _prefs.getString('sources.v1');
    if (raw != null) {
      for (final e in (jsonDecode(raw) as List)) {
        sources.add(Source.fromJson(Map<String, dynamic>.from(e as Map)));
      }
    }
    showAdult = _prefs.getBool('adult.show') ?? false;
    _loadCountries();
    activeSourceId = _prefs.getString('catalog.source');
    dedupe = _prefs.getBool('catalog.dedupe') ?? true;
    final edits = _prefs.getString('channelEdits.v1');
    if (edits != null) {
      try {
        (jsonDecode(edits) as Map).forEach((k, v) => channelEdits[k as String] = ChannelEdit.fromJson(Map<String, dynamic>.from(v as Map)));
      } catch (_) {}
    }
    favoriteIds = _prefs.getStringList('favorites.v1') ?? [];
    recentIds = _prefs.getStringList('recents.v1') ?? [];
    for (final kind in categoryKinds) {
      final json = _prefs.getString('categories.${kind.name}.v1');
      if (json != null) _categoryPrefs[kind] = CategoryPrefs.fromJson(jsonDecode(json) as Map<String, dynamic>);
    }
    final extras = _prefs.getString('recentItems.v1');
    if (extras != null) {
      for (final e in (jsonDecode(extras) as List)) {
        final item = MediaItem.fromJson(Map<String, dynamic>.from(e as Map));
        _extras[item.id] = item;
      }
    }
    // Démarrage rapide : contenu en cache, puis actualisation si plus de 6 h.
    for (final source in sources) {
      final file = _cacheFile(source.id);
      if (await file.exists()) {
        try {
          _contentBySource[source.id] = await _loadCache(file.path);
        } catch (e) {
          PlaybackLog.shared.note('Cache de « ${source.name} » illisible : $e');
        }
      }
    }
    _rebuild();
    bool isStale(Source s) {
      if (!s.enabled) return false;
      if (_contentBySource[s.id] == null) return true;
      final age = s.lastRefresh == null ? const Duration(days: 365) : DateTime.now().difference(s.lastRefresh!);
      // Dossiers : examinés à chaque lancement (rapide) ; serveurs : toutes les heures (positions de lecture).
      return switch (s.kind) {
        SourceKind.folder => true,
        SourceKind.jellyfin || SourceKind.emby || SourceKind.plex => age > const Duration(hours: 1),
        _ => autoRefresh && age > const Duration(hours: 6),
      };
    }

    final stale = sources.where(isStale).toList();
    if (stale.isNotEmpty) {
      unawaited(() async {
        for (final s in stale) {
          await refresh(s);
        }
      }());
    }
    // Nouveaux fichiers et positions de lecture des serveurs : examen régulier en arrière-plan.
    _rescan = Timer.periodic(const Duration(minutes: 20), (_) async {
      if (isBusy) return;
      for (final s in sources.where((s) => s.enabled && (s.kind == SourceKind.folder || s.kind.isMediaServer)).toList()) {
        await refresh(s);
      }
    });
    if (!_ready.isCompleted) _ready.complete();
  }

  final _ready = Completer<void>();

  /// Terminé quand les sources et le contenu en cache sont chargés.
  Future<void> get whenReady => _ready.future;

  File _cacheFile(String id) => File('${_cacheDir.path}${Platform.pathSeparator}$id.json');

  /// Lecture du cache dans un autre fil. Fonction statique : la fermeture n'emporte que le chemin (une fermeture créée
  /// dans une méthode asynchrone peut emporter son contexte, que l'autre fil refuse).
  static Future<List<MediaItem>> _loadCache(String path) => Isolate.run(() => _decodeCache(path));

  static Future<void> _writeCache(String path, List<Map<String, dynamic>> encoded) =>
      Isolate.run(() => File(path).writeAsStringSync(jsonEncode(encoded)));

  static List<MediaItem> _decodeCache(String path) {
    final list = jsonDecode(File(path).readAsStringSync()) as List;
    return [for (final e in list) MediaItem.fromJson(Map<String, dynamic>.from(e as Map))];
  }

  // MARK: Accès

  int count(MediaKind kind) => _byKind[kind]?.length ?? 0;

  // MARK: Vidéothèque (dossiers, Jellyfin, Emby, Plex)

  final Map<String, List<MediaItem>> _library = {};

  /// Sources en cours de chargement.
  final Set<String> loadingSources = {};

  /// Erreur du dernier chargement de chaque source (diagnostic) : message court et détail (réponse du serveur).
  final Map<String, (String, String?)> sourceErrors = {};

  /// Sources de la vidéothèque (actives).
  List<Source> get librarySources => sources.where((s) => s.enabled && !s.kind.isIptv).toList();
  bool get hasLibrary => sources.any((s) => !s.kind.isIptv);

  /// Films, séries et vidéos de la vidéothèque (d'une source, ou de toutes).
  List<MediaItem> libraryItems({String? sourceId}) =>
      sourceId != null ? (_library[sourceId] ?? const []) : [for (final list in _library.values) ...list];

  bool isLibraryItem(MediaItem item) => !(sourceOf(item)?.kind.isIptv ?? true);

  /// Série d'un épisode (vidéothèque ou IPTV).
  MediaItem? seriesOf(MediaItem episode) {
    for (final s in libraryItems(sourceId: episode.sourceId)) {
      if (s.kind == MediaKind.series && s.seriesId == episode.seriesId) return s;
    }
    return items(MediaKind.series).where((s) => s.name == episode.group).firstOrNull;
  }
  List<MediaItem> items(MediaKind kind) => _byKind[kind] ?? const [];

  /// Catégories visibles, dans l'ordre choisi (noms d'origine).
  List<String> categories(MediaKind kind) => _categories[kind] ?? const [];

  /// Toutes les catégories, masquées comprises (gestionnaire de catégories).
  List<String> allCategories(MediaKind kind) => _allCategories[kind] ?? const [];
  List<MediaItem> itemsInCategory(MediaKind kind, String category) => _byCategory['${kind.index}|$category'] ?? const [];
  String categoryName(MediaKind kind, String name) => prefs(kind).displayName(name);
  MediaItem? item(String id) => _byId[id] ?? _extras[id];
  bool isFavorite(String id) => favoriteIds.contains(id);
  List<MediaItem> get favorites => [for (final id in favoriteIds) ?item(id)];
  List<MediaItem> get recents => [for (final id in recentIds) ?item(id)];

  /// Contenus récents d'une section (épisodes compris pour les séries).
  List<MediaItem> recentsOf(MediaKind kind) =>
      recents.where((i) => i.kind == kind || (kind == MediaKind.series && i.kind == MediaKind.episode)).toList();
  List<MediaItem> favoritesOf(MediaKind kind) =>
      favorites.where((i) => i.kind == kind || (kind == MediaKind.series && i.kind == MediaKind.episode)).toList();

  // MARK: Pays et langues (rangées Cinéma et bandeau)

  /// Pays choisis (vide : tous) et catégories sans pays reconnu gardées ou non.
  Set<String> countries = {};
  bool countryNeutral = true;

  /// Source affichée (identifiant) ; null : toutes les sources activées.
  String? activeSourceId;

  /// Plusieurs comptes IPTV : un film ou une série présent dans plusieurs comptes n'est listé qu'une fois (« Toutes les sources »).
  bool dedupe = true;
  final Map<String, String> _dedupeOwner = {};

  /// Comptes IPTV activés, proposés dans le sélecteur de source (au moins deux). Dossiers et serveurs restent toujours visibles.
  List<Source> get selectableSources => sources.where((s) => s.enabled && s.kind.isIptv).toList();

  Source? get activeSource => activeSourceId == null ? null : selectableSources.where((s) => s.id == activeSourceId).firstOrNull;

  void setActiveSource(String? id) {
    activeSourceId = id;
    if (id == null) {
      _prefs.remove('catalog.source');
    } else {
      _prefs.setString('catalog.source', id);
    }
    _rebuild();
  }

  void setDedupe(bool value) {
    dedupe = value;
    _prefs.setBool('catalog.dedupe', value);
    _rebuild();
  }

  /// Contenus renvoyés par le fournisseur pour une source (avant masquages et fusion des doublons).
  ({int live, int movies, int series}) rawCounts(Source source) {
    var live = 0, movies = 0, series = 0;
    for (final i in _contentBySource[source.id] ?? const <MediaItem>[]) {
      switch (i.kind) {
        case MediaKind.live:
          live++;
        case MediaKind.movie:
          movies++;
        case MediaKind.series:
          series++;
        case MediaKind.episode:
          break;
      }
    }
    return (live: live, movies: movies, series: series);
  }

  /// Change quand le choix des pays change (le bandeau se recompose).
  int countriesGeneration = 0;
  final Map<String, String?> _categoryCountry = {};

  void _loadCountries() {
    countries = (_prefs.getStringList('catalog.countries') ?? const []).toSet();
    countryNeutral = _prefs.getBool('catalog.countries.neutral') ?? true;
  }

  void setCountries(Set<String> value, {bool? neutral}) {
    countries = value;
    if (neutral != null) countryNeutral = neutral;
    _prefs.setStringList('catalog.countries', value.toList()..sort());
    _prefs.setBool('catalog.countries.neutral', countryNeutral);
    countriesGeneration++;
    liveGeneration++;
    notifyListeners();
  }

  String? countryOfCategory(String name) => _categoryCountry.putIfAbsent(name, () => Countries.of(name));

  /// Pays d'un contenu : celui de sa catégorie, sinon celui de son nom.
  String? countryOf(MediaItem item) => countryOfCategory(item.group) ?? Countries.of(item.name);

  bool _countryAllowed(String? code) => countries.isEmpty || (code == null ? countryNeutral : countries.contains(code));
  // Les films et séries de « Mes vidéos » ne sont jamais filtrés par pays.
  bool inCountries(MediaItem item) => countries.isEmpty || isLibraryItemId(item) || _countryAllowed(countryOf(item));
  bool categoryInCountries(String name) => countries.isEmpty || _libraryGroups.contains(name) || _countryAllowed(countryOfCategory(name));
  bool isLibraryItemId(MediaItem item) => !(sources.where((s) => s.id == item.sourceId).firstOrNull?.kind.isIptv ?? true);

  // MARK: Pays des listes (interface Classique)

  /// Pays affiché dans les listes, la recherche et les catégories de la barre latérale (null : tous).
  String? get listCountry => _prefs.getString('catalog.listCountry');

  void setListCountry(String? code) {
    if (code == null) {
      _prefs.remove('catalog.listCountry');
    } else {
      _prefs.setString('catalog.listCountry', code);
    }
    notifyListeners();
  }

  final Map<String, String?> _itemCountry = {};

  /// Pays d'un contenu, gardé en mémoire (listes de plusieurs dizaines de milliers de titres).
  String? cachedCountryOf(MediaItem item) => _itemCountry.putIfAbsent(item.id, () => countryOf(item));

  bool inListCountry(MediaItem item) {
    final code = listCountry;
    return code == null || cachedCountryOf(item) == code;
  }

  int _listCountriesGeneration = -1;
  final Map<MediaKind, List<(String, int)>> _listCountries = {};

  /// Pays repérés dans les contenus d'une section (catégorie ou nom), du plus fréquent au moins fréquent.
  List<(String, int)> listCountries(MediaKind kind) {
    if (_listCountriesGeneration != liveGeneration) {
      _listCountries.clear();
      _listCountriesGeneration = liveGeneration;
    }
    return _listCountries.putIfAbsent(kind, () {
      final counts = <String, int>{};
      for (final item in items(kind)) {
        final code = cachedCountryOf(item);
        if (code != null) counts[code] = (counts[code] ?? 0) + 1;
      }
      return counts.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2));
    });
  }

  /// Contenus d'une catégorie limités au pays des listes.
  List<MediaItem> itemsInCategoryForList(MediaKind kind, String category) {
    final all = itemsInCategory(kind, category);
    return listCountry == null ? all : all.where(inListCountry).toList();
  }

  // MARK: Origine des films et séries (Tout / IPTV / Mes vidéos)

  /// Films et séries affichés dans Films et Séries : tout, l'IPTV seul (par défaut) ou « Mes vidéos » seules.
  CatalogOrigin get catalogOrigin => CatalogOrigin.values.where((o) => o.name == _prefs.getString('catalog.origin')).firstOrNull ?? CatalogOrigin.iptv;
  final Set<String> _libraryGroups = {};

  void setCatalogOrigin(CatalogOrigin value) {
    _prefs.setString('catalog.origin', value.name);
    countriesGeneration++;
    _rebuild();
  }

  /// Pays repérés dans les catégories (nombre de contenus), du plus fréquent au moins fréquent.
  List<(String, int)> detectedCountries() {
    final counts = <String, int>{};
    for (final kind in categoryKinds) {
      for (final name in allCategories(kind)) {
        final code = countryOfCategory(name);
        if (code != null) counts[code] = (counts[code] ?? 0) + itemsInCategory(kind, name).length;
      }
    }
    return counts.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2));
  }

  /// Derniers ajouts du fournisseur (Xtream), du plus récent au plus ancien, dans les pays choisis.
  List<MediaItem> latest(MediaKind kind, {int limit = 40}) {
    final withDate = items(kind).where((i) => i.added != null && inCountries(i)).toList()..sort((a, b) => b.added!.compareTo(a.added!));
    return withDate.take(limit).toList();
  }

  void toggleFavorite(String id) {
    if (!favoriteIds.remove(id)) favoriteIds.insert(0, id);
    _prefs.setStringList('favorites.v1', favoriteIds);
    _saveExtras();
    notifyListeners();
  }

  void noteRecent(MediaItem item) {
    recentIds
      ..remove(item.id)
      ..insert(0, item.id);
    if (recentIds.length > 60) recentIds = recentIds.sublist(0, 60);
    if (_byId[item.id] == null) _extras[item.id] = item;
    _prefs.setStringList('recents.v1', recentIds);
    _saveExtras();
    notifyListeners();
  }

  /// Retire des contenus des récents (mode « Modifier » des récents, clic droit).
  void removeRecents(Iterable<String> ids) {
    final remove = ids.toSet();
    recentIds = recentIds.where((id) => !remove.contains(id)).toList();
    _prefs.setStringList('recents.v1', recentIds);
    _saveExtras();
    notifyListeners();
  }

  void clearRecents() {
    recentIds = [];
    _prefs.setStringList('recents.v1', recentIds);
    _saveExtras();
    notifyListeners();
  }

  void _saveExtras() {
    final keep = {...recentIds, ...favoriteIds};
    _extras.removeWhere((k, _) => !keep.contains(k));
    _prefs.setString('recentItems.v1', jsonEncode([for (final i in _extras.values) i.toJson()]));
  }

  // MARK: Catégories

  CategoryPrefs prefs(MediaKind kind) => _categoryPrefs[kind] ?? CategoryPrefs();

  void updateCategories(MediaKind kind, void Function(CategoryPrefs prefs) change) {
    final p = _categoryPrefs[kind] ?? CategoryPrefs();
    change(p);
    _categoryPrefs[kind] = p;
    _prefs.setString('categories.${kind.name}.v1', jsonEncode(p.toJson()));
    _rebuild();
  }

  /// Enregistre l'ordre des contenus d'une catégorie (noms d'origine, identifiants dans l'ordre voulu).
  void setItemOrder(MediaKind kind, String category, List<String> ids) =>
      updateCategories(kind, (p) => p.itemOrder[category] = ids);

  /// Remet une catégorie dans l'ordre du fournisseur.
  void resetItemOrder(MediaKind kind, String category) => updateCategories(kind, (p) => p.itemOrder.remove(category));

  /// Déplace un contenu vers une autre catégorie, ou une liste personnelle (nom libre). `null` : retour à l'origine.
  void moveItem(MediaKind kind, MediaItem item, String? category, {String? from}) => updateCategories(kind, (p) {
        if (category == null) {
          p.moves.remove(item.id);
        } else {
          p.moves[item.id] = category;
        }
        if (from != null) p.itemOrder[from]?.remove(item.id);
      });

  void _rebuild() {
    _byKind.clear();
    _categories.clear();
    _allCategories.clear();
    _byCategory.clear();
    _byId.clear();
    _localEpisodes.clear();
    _library.clear();
    _libraryGroups.clear();
    _itemCountry.clear();
    final origin = catalogOrigin;
    final providerOrder = <MediaKind, List<String>>{};
    _dedupeOwner.clear();
    if (activeSourceId != null && activeSource == null) activeSourceId = null;
    final merge = dedupe && activeSourceId == null && sources.where((s) => s.enabled && s.kind.isIptv).length > 1;
    for (final source in sources.where((s) => s.enabled && (activeSourceId == null || !s.kind.isIptv || s.id == activeSourceId))) {
      final iptv = source.kind.isIptv;
      for (final original in _contentBySource[source.id] ?? const <MediaItem>[]) {
        // Épisodes des dossiers locaux : rangés sous leur série (fiche de la série), pas dans les listes.
        if (original.kind == MediaKind.episode) {
          (_localEpisodes[original.seriesId ?? ''] ??= []).add(original);
          _byId[original.id] = original;
          continue;
        }
        // Dossiers et serveurs de la maison : toujours dans « Mes vidéos » ; dans Films et Séries selon le filtre.
        if (!iptv) {
          _byId[original.id] = original;
          (_library[source.id] ??= []).add(original);
          if (origin == CatalogOrigin.iptv) continue;
          _libraryGroups.add(original.group);
        } else if (origin == CatalogOrigin.library && original.kind != MediaKind.live) {
          _byId[original.id] = original;
          continue;
        }
        final edit = original.kind == MediaKind.live ? channelEdits[original.id] : null;
        var item = edit == null ? original : edit.apply(original);
        final prefs = _categoryPrefs[item.kind];
        final moved = prefs?.moves[item.id];
        if (moved != null && moved.isNotEmpty && moved != item.group) item = item.copyWith(group: moved);
        // Deux comptes du même fournisseur : un film ou une série déjà fourni par un autre compte n'est listé qu'une fois.
        if (merge && iptv && (item.kind == MediaKind.movie || item.kind == MediaKind.series)) {
          final dk = '${item.kind.index}|${titleKey(item.name)}|${item.year ?? ''}';
          final owner = _dedupeOwner[dk];
          if (owner == null) {
            _dedupeOwner[dk] = source.id;
          } else if (owner != source.id) {
            _byId[item.id] = item;
            continue;
          }
        }
        final key = '${item.kind.index}|${item.group}';
        final list = _byCategory[key];
        if (list == null) {
          _byCategory[key] = [item];
          (providerOrder[item.kind] ??= []).add(item.group);
        } else {
          list.add(item);
        }
        _byId[item.id] = item;
        if (!showAdult && item.kind != MediaKind.episode && ThemeClassifier.isAdult(item.name, group: item.group)) continue;
        // Une catégorie masquée l'est partout (listes, recherche, accueil), comme sur Mac.
        if (prefs != null && prefs.isHidden(item.group)) continue;
        (_byKind[item.kind] ??= []).add(item);
      }
    }
    // Ordre personnalisé des contenus de chaque catégorie (mode « Arranger »).
    _categoryPrefs.forEach((kind, p) {
      p.itemOrder.forEach((category, ids) {
        final list = _byCategory['${kind.index}|$category'];
        if (list == null || ids.isEmpty) return;
        final byId = {for (final i in list) i.id: i};
        final ordered = <MediaItem>[for (final id in ids) ?byId.remove(id)];
        final rest = list.where((i) => byId.containsKey(i.id)).toList();
        list
          ..clear()
          ..addAll(ordered)
          ..addAll(rest);
      });
    });
    providerOrder.forEach((kind, names) {
      final prefs = _categoryPrefs[kind] ?? CategoryPrefs();
      final ordered = prefs.apply(names);
      _allCategories[kind] = ordered;
      _categories[kind] = ordered
          .where((n) => !prefs.isHidden(n) && (showAdult || !ThemeClassifier.isAdult('', group: n)))
          .toList();
    });
    liveGeneration++;
    notifyListeners();
  }

  void setShowAdult(bool value) {
    showAdult = value;
    _prefs.setBool('adult.show', value);
    _rebuild();
  }

  // MARK: Sources

  Future<void> _saveSources() => _prefs.setString('sources.v1', jsonEncode([for (final s in sources) s.toJson()]));

  Future<String?> password(String sourceId) => _secrets.read('password.$sourceId');

  /// Client Xtream d'une source (fiches, épisodes).
  Future<XtreamClient?> xtreamClient(String sourceId) async {
    final source = sources.where((s) => s.id == sourceId).firstOrNull;
    if (source == null || source.kind != SourceKind.xtream) return null;
    final pass = await password(sourceId) ?? '';
    return XtreamClient(XtreamCredentials(Uri.parse(source.address), source.username ?? '', pass), sourceId);
  }

  /// Toutes les chaînes d'une source (masquées comprises), pour filtrer son guide TV.
  List<MediaItem> allLiveItems(String sourceId) =>
      [
        for (final i in _contentBySource[sourceId] ?? const <MediaItem>[])
          if (i.kind == MediaKind.live) channelEdits[i.id]?.apply(i) ?? i,
      ];

  // MARK: Replay

  /// Jours de replay de la chaîne (0 : aucun, ou fonction désactivée).
  int replayDays(MediaItem channel) {
    if (!(settings?.replayEnabled ?? true) || channel.kind != MediaKind.live) return 0;
    return channel.archiveDays ?? 0;
  }

  /// Ce programme peut-il être revu ? Déjà commencé, et assez récent pour l'archive de la chaîne.
  bool canReplay(MediaItem channel, int startS, {int? nowS}) {
    final days = replayDays(channel);
    final now = nowS ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return days > 0 && startS <= now && startS >= now - days * 86400 + 600;
  }

  /// Programmes passés à garder dans le guide : (chaînes à archive en minuscules, date limite en secondes).
  (Set<String>, int)? replayRetention(String sourceId) {
    if (!(settings?.replayEnabled ?? true)) return null;
    final channels = <String>{};
    var longest = 0;
    for (final i in allLiveItems(sourceId)) {
      final d = i.archiveDays ?? 0;
      if (d > 0 && (i.epgId ?? '').isNotEmpty) {
        channels.add(i.epgId!.toLowerCase().trim());
        if (d > longest) longest = d;
      }
    }
    if (channels.isEmpty) return null;
    final days = longest < settings!.replayGuideDays
        ? longest
        : settings!.replayGuideDays;
    return (
      channels,
      DateTime.now().millisecondsSinceEpoch ~/ 1000 - days * 86400,
    );
  }

  /// Élément lisible pour revoir un programme depuis l'archive du fournisseur.
  MediaItem? makeReplay(MediaItem channel, Programme programme) {
    final live = channel.stream;
    if (live == null) return null;
    final clock = sources
        .where((s) => s.id == channel.sourceId)
        .firstOrNull
        ?.clock;
    final offset = settings?.replayOffset ?? 0;
    final url = ReplayUrl.make(
      live,
      startS: programme.startS,
      stopS: programme.stopS,
      clock: clock,
      extraOffsetMinutes: offset,
    );
    if (url == null) return null;
    final item = MediaItem(
      id: '${ReplayUrl.idPrefix}${channel.id}|${programme.startS}',
      sourceId: channel.sourceId,
      kind: MediaKind.movie,
      name: '${programme.title} — ${channel.name}',
      group: channel.name,
      logo: channel.logo,
      stream: url,
      epgId: channel.epgId,
      info: programme.desc,
    );
    replayChannels[item.id] = channel;
    PlaybackLog.shared.note(
      'Replay « ${programme.title} » sur ${channel.name} : début ${programme.start}, décalage manuel $offset min, '
      'horloge serveur : ${clock == null ? 'inconnue' : '${clock.timezone ?? '?'} / ${clock.offset == null ? '?' : '${clock.offset! ~/ 60} min'}'}',
      topic: LogTopic.playback,
      detail: LogDetail.detailed,
    );
    return item;
  }

  /// Chaîne d'origine des replays ouverts (retour au direct).
  final Map<String, MediaItem> replayChannels = {};

  /// Adresse du guide TV d'une source : choisie par l'utilisateur, indiquée par le fournisseur, ou xmltv.php (Xtream).
  Future<String?> guideUrlFor(Source source) async {
    if (source.epgUrl?.isNotEmpty ?? false) return source.epgUrl;
    if (source.guideUrl?.isNotEmpty ?? false) return source.guideUrl;
    final client = await xtreamClient(source.id);
    return client?.xmltvUrl;
  }

  /// Ajoute une source Xtream (le mot de passe va dans le coffre du système).
  Future<Source> addXtream(
      {required String name,
      required String server,
      required String username,
      required String password,
      String? epgUrl,
      bool refreshNow = true}) async {
    final normalized = XtreamCredentials.normalizeServer(server);
    if (normalized == null) throw XtreamException('Adresse du serveur invalide.');
    final source = Source(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? normalized.host : name.trim(),
      kind: SourceKind.xtream,
      address: normalized.toString(),
      username: username.trim(),
      epgUrl: (epgUrl?.trim().isEmpty ?? true) ? null : epgUrl!.trim(),
    );
    await _secrets.write('password.${source.id}', password);
    sources.add(source);
    await _saveSources();
    notifyListeners();
    if (refreshNow) await refresh(source);
    return source;
  }

  /// Ajoute une playlist M3U (URL ou fichier). Une URL « get.php » devient une source Xtream, plus rapide.
  Future<Source> addM3U({required String name, required String address, String? epgUrl, bool refreshNow = true}) async {
    final xtream = XtreamCredentials.fromPlaylistUrl(address);
    if (xtream != null) {
      return addXtream(
          name: name,
          server: xtream.server.toString(),
          username: xtream.username,
          password: xtream.password,
          epgUrl: epgUrl,
          refreshNow: refreshNow);
    }
    final isFile = !address.trim().toLowerCase().startsWith('http');
    final source = Source(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Playlist' : name.trim(),
      kind: isFile ? SourceKind.m3uFile : SourceKind.m3uUrl,
      address: address.trim(),
      epgUrl: (epgUrl?.trim().isEmpty ?? true) ? null : epgUrl!.trim(),
    );
    sources.add(source);
    await _saveSources();
    notifyListeners();
    if (refreshNow) await refresh(source);
    return source;
  }

  /// Modifie une source (nom, adresse, identifiant, mot de passe, guide TV). Le contenu est rechargé si l'accès a changé.
  /// [password] null : mot de passe inchangé. Ses favoris, récents et corrections de chaînes sont gardés (même identifiant).
  Future<void> updateSource(Source source,
      {required String name,
      required String address,
      String? username,
      String? password,
      String? epgUrl,
      String? token,
      bool enabled = true}) async {
    var newAddress = address.trim();
    if (source.kind == SourceKind.xtream) {
      final normalized = XtreamCredentials.normalizeServer(newAddress);
      if (normalized == null) throw XtreamException('Adresse du serveur invalide.');
      newAddress = normalized.toString();
    } else if (source.kind.isMediaServer) {
      newAddress = MediaServerClient.normalizeFor(source.kind, newAddress);
    }
    final oldSession = ServerSession.decode(await _secrets.read('session.${source.id}'));
    final accessChanged = newAddress != source.address ||
        (username != null && username.trim() != (source.username ?? '')) ||
        (password != null && password != (await this.password(source.id) ?? '')) ||
        (token != null && token.trim().isNotEmpty && token.trim() != oldSession?.token);
    final guideChanged = (epgUrl?.trim() ?? '') != (source.epgUrl ?? '');
    source
      ..name = name.trim().isEmpty ? source.name : name.trim()
      ..address = newAddress
      ..enabled = enabled
      ..epgUrl = (epgUrl?.trim().isEmpty ?? true) ? null : epgUrl!.trim();
    if (username != null) source.username = username.trim().isEmpty ? null : username.trim();
    if (password != null) await _secrets.write('password.${source.id}', password);
    if (source.kind.isMediaServer && accessChanged) {
      _servers.remove(source.id);
      if (source.kind == SourceKind.plex) {
        if (token != null && token.trim().isNotEmpty) await _secrets.write('session.${source.id}', ServerSession(token.trim()).encode());
      } else {
        // Nouvelle connexion avec les nouveaux identifiants (vérifiée tout de suite).
        final session = await _signIn(source.kind, newAddress, source.username ?? '', password ?? await this.password(source.id) ?? '');
        await _secrets.write('session.${source.id}', session.encode());
      }
    }
    await _saveSources();
    _rebuild();
    if (accessChanged) await refresh(source);
    if (guideChanged && !accessChanged) onSourceRefreshed?.call(source);
  }

  Future<void> removeSource(Source source) async {
    sources.removeWhere((s) => s.id == source.id);
    _contentBySource.remove(source.id);
    await _secrets.delete('password.${source.id}');
    await _secrets.delete('session.${source.id}');
    _servers.remove(source.id);
    final file = _cacheFile(source.id);
    if (await file.exists()) await file.delete();
    await _saveSources();
    _rebuild();
    onSourceRemoved?.call(source.id);
  }

  Future<void> refreshAll() async {
    for (final source in List.of(sources.where((s) => s.enabled))) {
      await refresh(source);
    }
  }

  Future<void> refresh(Source source) async {
    var refreshed = false;
    isBusy = true;
    loadingSources.add(source.id);
    lastError = null;
    notifyListeners();
    try {
      final id = source.id;
      SourceContent content;
      switch (source.kind) {
        case SourceKind.xtream:
          final pass = await password(id) ?? '';
          final server = source.address;
          final user = source.username ?? '';
          content = await Isolate.run(() async {
            final client = XtreamClient(XtreamCredentials(Uri.parse(server), user, pass), id);
            return client.fetchLibrary();
          });
        case SourceKind.m3uUrl:
          final url = source.address;
          content = await Isolate.run(() async => M3UParser.parse(await httpGetText(Uri.parse(url)), id));
        case SourceKind.m3uFile:
          final path = source.address;
          content = await Isolate.run(() => M3UParser.parse(File(path).readAsStringSync(), id));
        case SourceKind.folder:
          final roots = folderPaths(source);
          final missing = roots.where((r) => !Directory(r).existsSync()).toList();
          if (missing.length == roots.length) {
            throw MediaServerException('Dossier introuvable (${missing.join(', ')}) : disque débranché ou partage réseau non connecté ?');
          }
          final (movies, series, videos) = (tr('Films'), tr('Séries'), tr('Vidéos'));
          content = await Isolate.run(() => scanFolders(roots, id, moviesLabel: movies, seriesLabel: series, videosLabel: videos));
          // Affiches et résumés déjà trouvés (TMDB) gardés d'un examen à l'autre.
          final known = {for (final i in _contentBySource[id] ?? const <MediaItem>[]) i.id: i};
          content = SourceContent([
            for (final i in content.items)
              if (known[i.id] case final k? when k.logo != null || k.info != null || k.genres.isNotEmpty)
            i.copyWith(logo: k.logo, info: k.info, year: k.year, genres: k.genres)
          else
            i,
          ]);
        case SourceKind.jellyfin:
        case SourceKind.emby:
        case SourceKind.plex:
          final client = await serverClient(source, forceSignIn: false);
          if (client == null) throw MediaServerException('Connexion au serveur impossible.');
          try {
            content = await client.fetchLibrary();
          } on MediaServerException catch (e) {
            // Jeton expiré (Jellyfin / Emby) : nouvelle connexion avec le mot de passe.
            if (!e.message.contains('Accès refusé') || source.kind == SourceKind.plex) rethrow;
            final again = await serverClient(source, forceSignIn: true);
            if (again == null) rethrow;
            content = await again.fetchLibrary();
          }
      }
      var items = content.items;
      // Une section qui revient vide (serveur qui hoquette) ne doit pas effacer celle déjà connue.
      final previous = _contentBySource[id];
      if (previous != null && previous.isNotEmpty) {
        final kept = <MediaItem>[];
        for (final kind in categoryKinds) {
          final before = previous.where((i) => i.kind == kind).length;
          final now = items.where((i) => i.kind == kind).length;
          if (now == 0 && before > 0) {
            kept.addAll(previous.where((i) => i.kind == kind));
            PlaybackLog.shared.note('Source « ${source.name} » : section ${kind.name} vide à l\'actualisation, la précédente est conservée');
          }
        }
        if (kept.isNotEmpty) items = [...items, ...kept];
      }
      _contentBySource[id] = items;
      if (content.progress.isNotEmpty) onUserData?.call(content.progress);
      source.lastRefresh = DateTime.now();
      source.guideUrl = content.epgUrl;
      source.clock = content.clock ?? source.clock;
      refreshed = true;
      sourceErrors.remove(source.id);
      await _saveSources();
      final path = _cacheFile(id).path;
      final encoded = [for (final i in items) i.toJson()];
      await _writeCache(path, encoded);
      final live = items.where((i) => i.kind == MediaKind.live).toList();
      final withId = live.where((i) => (i.epgId ?? '').isNotEmpty).length;
      final guideAddress = source.epgUrl?.isNotEmpty ?? false
          ? 'choisie dans la source'
          : ((content.epgUrl ?? '').isNotEmpty ? 'fournie par le fournisseur' : 'inconnue');
      PlaybackLog.shared.note(source.kind.isIptv
          ? 'Source « ${source.name} » chargée : ${live.length} chaînes ($withId avec un identifiant de guide), '
              '${items.where((i) => i.kind == MediaKind.movie).length} films, ${items.where((i) => i.kind == MediaKind.series).length} séries'
              ' — adresse du guide : $guideAddress'
          : 'Source « ${source.name} » chargée : ${items.length} éléments', topic: LogTopic.sources);
    } catch (e) {
      lastError = '${source.name} : $e';
      sourceErrors[source.id] = ('$e', e is MediaServerException ? e.detail : null);
      PlaybackLog.shared.error('Source « ${source.name} » : $e', topic: LogTopic.sources);
    } finally {
      loadingSources.remove(source.id);
      isBusy = loadingSources.isNotEmpty;
      _rebuild();
    }
    if (refreshed) {
      if (source.kind.isIptv) onSourceRefreshed?.call(source);
      onContentLoaded?.call(source);
    }
  }

  // MARK: Dossiers locaux et serveurs multimédias

  /// Dossiers d'une source « Dossiers » (un par ligne).
  static List<String> folderPaths(Source source) =>
      source.address.split('\n').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

  Future<Source> addFolders({required String name, required List<String> paths}) async {
    final clean = paths.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (clean.isEmpty) throw MediaServerException('Choisissez au moins un dossier.');
    final source = Source(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? clean.first.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).last : name.trim(),
      kind: SourceKind.folder,
      address: clean.join('\n'),
    );
    sources.add(source);
    await _saveSources();
    notifyListeners();
    await refresh(source);
    return source;
  }

  /// Ajoute un serveur Jellyfin, Emby ou Plex. Jellyfin / Emby : identifiant et mot de passe (ou clé d'API) ;
  /// Plex : jeton (connexion plex.tv ou jeton saisi).
  Future<Source> addMediaServer({
    required SourceKind kind,
    required String name,
    required String address,
    String username = '',
    String password = '',
    String? token,
  }) async {
    final server = MediaServerClient.normalizeFor(kind, address);
    final source = Source(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? (Uri.tryParse(server)?.host ?? kind.label) : name.trim(),
      kind: kind,
      address: server,
      username: username.trim().isEmpty ? null : username.trim(),
    );
    // Vérification avant l'ajout : une erreur d'identifiant est signalée tout de suite.
    final ServerSession session;
    if (kind == SourceKind.plex) {
      // Sans jeton : serveur ouvert au réseau local (Plex > Réseau > « Adresses autorisées sans authentification »).
      final t = (token ?? password).trim();
      session = ServerSession(t);
      await PlexClient(server, source.id, token: t).identity();
    } else {
      session = await _signIn(kind, server, username, password);
      await _secrets.write('password.${source.id}', password);
    }
    await _secrets.write('session.${source.id}', session.encode());
    sources.add(source);
    await _saveSources();
    notifyListeners();
    await refresh(source);
    return source;
  }

  static Future<ServerSession> _signIn(SourceKind kind, String server, String username, String password) async {
    try {
      return await JellyfinClient.signIn(server, username, password, emby: kind == SourceKind.emby);
    } on MediaServerException {
      // Une clé d'API (Tableau de bord > Clés API) peut remplacer le mot de passe.
      if (password.length >= 24 && !password.contains(' ')) {
        try {
          return await JellyfinClient.withApiKey(server, password, username);
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Client du serveur d'une source (session gardée dans le coffre du système).
  Future<MediaServerClient?> serverClient(Source source, {bool forceSignIn = false}) async {
    if (!source.kind.isMediaServer) return null;
    final cached = _servers[source.id];
    if (!forceSignIn && cached != null) {
      return cached
        ..label = source.name
        ..videosLabel = tr('Vidéos');
    }
    var session = ServerSession.decode(await _secrets.read('session.${source.id}'));
    if (source.kind != SourceKind.plex && (session == null || forceSignIn)) {
      final password = await this.password(source.id) ?? '';
      session = await _signIn(source.kind, source.address, source.username ?? '', password);
      await _secrets.write('session.${source.id}', session.encode());
    }
    if (session == null) return null;
    final client = source.kind == SourceKind.plex
        ? PlexClient(source.address, source.id, token: session.token)
        : JellyfinClient(source.address, source.id, session: session, emby: source.kind == SourceKind.emby);
    client
      ..label = source.name
      ..videosLabel = tr('Vidéos');
    _servers[source.id] = client;
    return client;
  }

  Source? sourceOf(MediaItem item) => sources.where((s) => s.id == item.sourceId).firstOrNull;

  /// Saisons d'une série venue d'un dossier local ou d'un serveur (null : série IPTV, chargée par la fiche).
  Future<List<SeriesSeason>?> seasonsFor(MediaItem series) async {
    final source = sourceOf(series);
    if (source == null) return null;
    if (source.kind == SourceKind.folder) {
      final episodes = _localEpisodes[series.seriesId ?? series.id] ?? const <MediaItem>[];
      final bySeason = <int, List<MediaItem>>{};
      for (final e in episodes) {
        (bySeason[e.season ?? 1] ??= []).add(e);
      }
      return [
        for (final n in (bySeason.keys.toList()..sort()))
          SeriesSeason(n, bySeason[n]!..sort((a, b) => (a.number ?? 0).compareTo(b.number ?? 0))),
      ];
    }
    final client = await serverClient(source);
    if (client == null) return null;
    final (seasons, progress) = switch (client) {
      JellyfinClient c => await c.episodes(series),
      PlexClient c => await c.episodes(series),
      _ => (<SeriesSeason>[], <String, (double, double)>{}),
    };
    if (progress.isNotEmpty) onUserData?.call(progress);
    for (final s in seasons) {
      for (final e in s.episodes) {
        _extras[e.id] = e;
      }
    }
    return seasons;
  }

  /// Fiche fournie par un serveur multimédia (résumé, distribution, image de fond…).
  Future<MediaDetails?> serverDetails(MediaItem item) async {
    final source = sourceOf(item);
    if (source == null || !source.kind.isMediaServer) return null;
    final client = await serverClient(source);
    return client?.details(item);
  }

  /// Fichier local d'une source « Dossiers » : ses sous-titres voisins sont chargés à la lecture.
  bool isLocalFile(MediaItem item) => sourceOf(item)?.kind == SourceKind.folder;

  /// Affiches et résumés trouvés sur TMDB pour les fichiers locaux (gardés dans le cache de la source).
  Future<void> applyEnrichment(String sourceId, Map<String, LocalFiche> found) async {
    final list = _contentBySource[sourceId];
    if (list == null || found.isEmpty) return;
    _contentBySource[sourceId] = [
      for (final i in list)
        if (found[i.id] case final f?)
          i.copyWith(logo: f.logo ?? i.logo, info: f.info ?? i.info, year: f.year ?? i.year, genres: f.genres.isEmpty ? i.genres : f.genres)
        else
          i,
    ];
    final path = _cacheFile(sourceId).path;
    final encoded = [for (final i in _contentBySource[sourceId]!) i.toJson()];
    await _writeCache(path, encoded);
    _rebuild();
  }

  /// Efface les fiches TMDB (affiche, résumé, année, genres) de fichiers : retour à la recherche automatique.
  Future<void> clearEnrichment(String sourceId, Set<String> ids) async {
    final list = _contentBySource[sourceId];
    if (list == null) return;
    _contentBySource[sourceId] = [for (final i in list) ids.contains(i.id) ? i.withoutFiche() : i];
    await _writeCache(_cacheFile(sourceId).path, [for (final i in _contentBySource[sourceId]!) i.toJson()]);
    _rebuild();
  }

  /// Contenus d'une source (fiches automatiques).
  List<MediaItem> contentOf(String sourceId) => _contentBySource[sourceId] ?? const [];


  // MARK: Exportation / importation (format commun avec la version Mac)

  /// Identifiant relatif : « numéro de source|reste de l'identifiant ».
  String? _relative(String id, Map<String, int> index) {
    final sep = id.indexOf(':');
    if (sep <= 0) return null;
    final n = index[id.substring(0, sep)];
    return n == null ? null : '$n|${id.substring(sep + 1)}';
  }

  /// Réglages de catégories pour l'export : les identifiants de contenus deviennent relatifs aux sources.
  Map<String, dynamic> _prefsForExport(CategoryPrefs p, Map<String, int> index) {
    final json = p.toJson();
    if (p.itemOrder.isNotEmpty) {
      json['itemOrder'] = {
        for (final e in p.itemOrder.entries) e.key: [for (final id in e.value) ?_relative(id, index)],
      };
    }
    if (p.moves.isNotEmpty) {
      json['moves'] = {
        for (final e in p.moves.entries)
          ?_relative(e.key, index): e.value,
      };
    }
    return json;
  }

  Future<Map<String, dynamic>> makeExport({required bool includePasswords, required AppSettings settings, required String app}) async {
    final index = <String, int>{};
    final exported = <Map<String, dynamic>>[];
    for (final s in sources) {
      if (s.kind == SourceKind.m3uFile) continue;
      index[s.id] = exported.length;
      exported.add({
        'name': s.name,
        'kind': s.kind.name,
        'address': s.address,
        'username': ?s.username,
        if (includePasswords && (s.kind == SourceKind.xtream || s.kind == SourceKind.jellyfin || s.kind == SourceKind.emby))
          'password': ?await password(s.id),
        if (includePasswords && s.kind == SourceKind.plex) 'token': ?ServerSession.decode(await _secrets.read('session.${s.id}'))?.token,
        'epgUrl': ?s.epgUrl,
        'enabled': s.enabled,
      });
    }
    final settingsMap = <String, String>{
      for (final kind in categoryKinds)
        'interface.${kind.name}': ?settings.rawSetting('interface.${kind.name}'),
      'adult.show': showAdult ? '1' : '0',
      if (countries.isNotEmpty) 'catalog.countries': (countries.toList()..sort()).join(','),
      'catalog.countries.neutral': countryNeutral ? '1' : '0',
      ...settings.exportedHero(),
      ...settings.exportedAppearance(),
      if (includePasswords && settings.usesTMDB) 'tmdbKey': settings.tmdbKey,
    };
    final fiches = <String, dynamic>{};
    for (final e in (await FicheEdits.load()).entries) {
      final rel = _relative(e.key, index);
      if (rel != null) fiches[rel] = e.value.toJson();
    }
    return {
      'format': 'kastideo-export',
      'version': 1,
      'exportedAt': '${DateTime.now().toUtc().toIso8601String().split('.').first}Z',
      'app': app,
      'sources': exported,
      'favorites': [for (final id in favoriteIds) ?_relative(id, index)],
      'recents': [for (final id in recentIds) ?_relative(id, index)],
      'categories': {
        for (final kind in categoryKinds)
          if (_categoryPrefs[kind] case final p?) kind.name: _prefsForExport(p, index),
      },
      'settings': settingsMap,
      if (fiches.isNotEmpty) 'fiches': fiches,
    };
  }

  /// Ajoute les sources absentes, les favoris, les récents, les catégories et les réglages. Rien n'est supprimé.
  Future<String> importConfig(Map<String, dynamic> data, AppSettings settings) async {
    if (data['format'] != 'kastideo-export') throw XtreamException('Ce fichier n\'est pas une configuration Kastideo.');
    var added = 0, skipped = 0, favs = 0, cats = 0;
    final newIds = <int, String>{};
    final list = (data['sources'] as List? ?? const []).whereType<Map>().toList();
    final toRefresh = <Source>[];
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      final kind = SourceKind.values.where((k) => k.name == e['kind'] && k != SourceKind.m3uFile).firstOrNull;
      final address = e['address'] as String?;
      if (kind == null || address == null) continue;
      final normalized = kind == SourceKind.xtream
          ? XtreamCredentials.normalizeServer(address)?.toString() ?? address
          : kind.isMediaServer
              ? MediaServerClient.normalizeFor(kind, address)
              : address;
      final existing = sources
          .where((s) => s.kind == kind && s.address == normalized && (kind != SourceKind.xtream || s.username == e['username']))
          .firstOrNull;
      if (existing != null) {
        newIds[i] = existing.id;
        skipped++;
        continue;
      }
      if (!kind.isIptv) {
        // Dossiers et serveurs : ajoutés tels quels, la connexion se fait au chargement.
        final source = Source(
          id: '${DateTime.now().microsecondsSinceEpoch}$i',
          name: e['name'] as String? ?? kind.label,
          kind: kind,
          address: normalized,
          username: e['username'] as String?,
        );
        if (e['password'] case final String p) await _secrets.write('password.${source.id}', p);
        if (e['token'] case final String t) await _secrets.write('session.${source.id}', ServerSession(t).encode());
        source.enabled = e['enabled'] as bool? ?? true;
        sources.add(source);
        newIds[i] = source.id;
        toRefresh.add(source);
        added++;
        continue;
      }
      final source = kind == SourceKind.xtream
          ? await addXtream(
              name: e['name'] as String? ?? '',
              server: address,
              username: e['username'] as String? ?? '',
              password: e['password'] as String? ?? '',
              epgUrl: e['epgUrl'] as String?,
              refreshNow: false)
          : await addM3U(name: e['name'] as String? ?? '', address: address, epgUrl: e['epgUrl'] as String?, refreshNow: false);
      source.enabled = e['enabled'] as bool? ?? true;
      newIds[i] = source.id;
      toRefresh.add(source);
      added++;
    }
    await _saveSources();
    String? absolute(dynamic rel) {
      if (rel is! String) return null;
      final sep = rel.indexOf('|');
      if (sep <= 0) return null;
      final id = newIds[int.tryParse(rel.substring(0, sep)) ?? -1];
      return id == null ? null : '$id:${rel.substring(sep + 1)}';
    }

    for (final id in (data['favorites'] as List? ?? const []).map(absolute).whereType<String>()) {
      if (!favoriteIds.contains(id)) {
        favoriteIds.add(id);
        favs++;
      }
    }
    for (final id in (data['recents'] as List? ?? const []).map(absolute).whereType<String>()) {
      if (!recentIds.contains(id)) recentIds.add(id);
    }
    if (recentIds.length > 60) recentIds = recentIds.sublist(0, 60);
    _prefs.setStringList('favorites.v1', favoriteIds);
    _prefs.setStringList('recents.v1', recentIds);
    if (data['fiches'] is Map) {
      final edits = await FicheEdits.load();
      for (final e in (data['fiches'] as Map).entries) {
        final id = absolute(e.key);
        if (id != null && e.value is Map && !edits.containsKey(id)) edits[id] = FicheEdit.fromJson(e.value as Map);
      }
      await FicheEdits.save(edits);
    }
    final categories = data['categories'];
    if (categories is Map) {
      for (final kind in categoryKinds) {
        final c = categories[kind.name];
        if (c is Map) {
          final raw = Map<String, dynamic>.from(c);
          if (raw['itemOrder'] is Map) {
            raw['itemOrder'] = {
              for (final e in (raw['itemOrder'] as Map).entries)
                e.key: [for (final r in e.value as List) ?absolute(r)],
            };
          }
          if (raw['moves'] is Map) {
            raw['moves'] = {
              for (final e in (raw['moves'] as Map).entries)
                ?absolute(e.key): e.value,
            };
          }
          final imported = CategoryPrefs.fromJson(raw);
          _categoryPrefs[kind] = imported;
          _prefs.setString('categories.${kind.name}.v1', jsonEncode(imported.toJson()));
          cats++;
        }
      }
    }
    final s = data['settings'];
    if (s is Map) {
      for (final kind in categoryKinds) {
        final v = s['interface.${kind.name}'];
        final style = InterfaceStyle.values.where((x) => x.name == v).firstOrNull;
        if (style != null) settings.setInterface(kind, style);
      }
      final adult = s['adult.show'];
      if (adult is String) {
        showAdult = adult == '1' || adult == 'true';
        _prefs.setBool('adult.show', showAdult);
      }
      settings.importHero(Map<String, dynamic>.from(s));
      if (s['catalog.countries'] case final String c) {
        countries = c.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
        _prefs.setStringList('catalog.countries', countries.toList());
      }
      if (s['catalog.countries.neutral'] case final String n) {
        countryNeutral = n == '1' || n == 'true';
        _prefs.setBool('catalog.countries.neutral', countryNeutral);
      }
      settings.importAppearance(Map<String, dynamic>.from(s));
      final key = s['tmdbKey'];
      if (key is String && key.isNotEmpty && !settings.usesTMDB) await settings.setTMDBKey(key);
    }
    _rebuild();
    for (final source in toRefresh) {
      await refresh(source);
    }
    return 'Importation terminée : $added source(s) ajoutée(s), $skipped déjà présente(s), $favs favori(s), '
        'catégories de $cats section(s).';
  }
}
