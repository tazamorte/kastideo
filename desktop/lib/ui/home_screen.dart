import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../core/text.dart';
import '../l10n.dart';
import '../core/device.dart';
import '../theme.dart';
import '../version.dart';
import 'cinema_view.dart';
import 'help_dialog.dart';
import 'log_dialog.dart';
import 'multiview_view.dart';
import 'settings_dialog.dart';
import 'support_button.dart';
import 'widgets.dart';

/// Écran d'accueil : reproduction de l'accueil de la version Mac (en-tête, recherche, trois grands pavés,
/// accès rapides, filigrane du logo, numéro de version).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _query = TextEditingController();
  List<MediaItem> _results = [];
  Timer? _debounce;

  @override
  void dispose() {
    _query.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      final key = text.searchKey;
      final library = context.library;
      final found = <MediaItem>[];
      if (key.isNotEmpty) {
        for (final kind in [MediaKind.live, MediaKind.movie, MediaKind.series]) {
          var perKind = 0;
          for (final item in library.items(kind)) {
            if (item.searchKey.contains(key)) {
              found.add(item);
              if (++perKind >= 25) break;
            }
          }
        }
        // Vidéothèque (dossiers, serveurs).
        var inLibrary = 0;
        for (final item in library.libraryItems()) {
          if (item.searchKey.contains(key)) {
            found.add(item);
            if (++inLibrary >= 25) break;
          }
        }
      }
      setState(() => _results = found);
    });
  }

  @override
  Widget build(BuildContext context) => DarkZone(child: Builder(builder: _buildDark));

  Widget _buildDark(BuildContext context) {
    final library = context.library;
    final playback = context.playback;
    return Scaffold(
      body: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        _compact = size.width < 720;
        final tileHeight = _compact ? 164.0 : math.min(math.max(size.height * 0.30, 210.0), 380.0);
        return Stack(children: [
          const Positioned.fill(child: KastideoBackground()),
          _watermark(size),
          ListenableBuilder(
            listenable: Listenable.merge([library, playback, context.watch]),
            builder: (context, _) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: size.height),
                child: Center(
                  child: ConstrainedBox(
                    // Large écran : l'accueil suit la fenêtre au lieu de rester bloqué à 1180 points.
                    constraints: BoxConstraints(maxWidth: math.max(1180, size.width * 0.86)),
                    child: Padding(
                      padding: _compact ? const EdgeInsets.fromLTRB(16, 12, 16, 40) : const EdgeInsets.fromLTRB(32, 20, 32, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _header(context),
                          const SizedBox(height: 26),
                          _searchField(),
                          const SizedBox(height: 26),
                          if (_query.text.searchKey.isEmpty) ...[
                            if (playback.current != null) ...[_nowPlaying(context), const SizedBox(height: 26)],
                            if (library.sources.isEmpty) ...[_welcome(context), const SizedBox(height: 26)],
                            _bigTiles(context, tileHeight),
                            const SizedBox(height: 26),
                            _quickButtons(context),
                            _resumeRail(context),
                            if (library.lastError != null) ...[
                              const SizedBox(height: 18),
                              Text(library.lastError!, style: kTextD(13, color: KPalette.orange)),
                            ],
                          ] else
                            _searchResults(context),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 10,
            bottom: 10,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const SupportButton(onDark: true),
              const SizedBox(width: 12),
              Text('Kastideo $kVersion · ${Device.isAndroid ? (Device.isTv ? 'Android TV' : 'Android') : tr('Aperçu Windows / Linux')}',
                  style: kTextD(11, color: Colors.white.withValues(alpha: 0.35))),
            ]),
          ),
        ]);
      }),
    );
  }

  /// Logo de l'application en très grand, derrière le contenu.
  Widget _watermark(Size size) {
    final side = math.min(math.max(size.height * 0.95, 520.0), 1100.0);
    return Positioned(
      left: size.width - side * 0.28 - side / 2,
      top: size.height * 0.52 - side / 2,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: -8 * math.pi / 180,
          child: Opacity(
            opacity: 0.38,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(side * 0.2237),
                boxShadow: [BoxShadow(color: KPalette.magenta.withValues(alpha: 0.6), blurRadius: 160)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(side * 0.2237),
                child: Image.asset('assets/images/icon.png', width: side, height: side, filterQuality: FilterQuality.high),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _compact = false;

  Widget _header(BuildContext context) {
    final icon = _compact ? 56.0 : 92.0;
    return Row(children: [
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20.6),
          boxShadow: [
            BoxShadow(color: KPalette.magenta.withValues(alpha: 0.7), blurRadius: 36),
            BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 3)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20.6),
          child: Image.asset('assets/images/icon.png', width: icon, height: icon),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Kastideo', style: kRoundedD(_compact ? 30 : 46, FontWeight.w900)),
          const SizedBox(height: 2),
          Text(tr('Vos chaînes, vos films et vos séries au même endroit'),
              maxLines: _compact ? 2 : 3,
              overflow: TextOverflow.ellipsis,
              style: kTextD(14, color: Colors.white.withValues(alpha: 0.7))),
        ]),
      ),
      if (context.library.isBusy)
        const Padding(
          padding: EdgeInsets.only(right: 12),
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      _toolbarButton(Icons.help_outline_rounded, '${tr('Aide')} (F1)', () => showHelpDialog(context, page: 'bienvenue')),
      _toolbarButton(Icons.receipt_long_outlined, tr('Journal de lecture'), () => showLogDialog(context)),
      _toolbarButton(Icons.settings_rounded, '${tr('Réglages')} (Ctrl+,)', () => showSettingsDialog(context)),
    ]);
  }

  Widget _toolbarButton(IconData icon, String label, VoidCallback onTap) => Tooltip(
        message: label,
        child: IconButton(onPressed: onTap, icon: Icon(icon, color: Colors.white.withValues(alpha: 0.85))),
      );

  Widget _searchField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(children: [
        Icon(Icons.search_rounded, color: Colors.white.withValues(alpha: 0.6)),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _query,
            onChanged: (t) {
              setState(() {});
              _search(t);
            },
            style: kTextD(18),
            cursorColor: Colors.white,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: tr('Rechercher une chaîne, un film ou une série'),
              hintStyle: kTextD(18, color: Colors.white.withValues(alpha: 0.45)),
            ),
          ),
        ),
        if (_query.text.isNotEmpty)
          IconButton(
            onPressed: () {
              _query.clear();
              setState(() => _results = []);
            },
            icon: Icon(Icons.cancel_rounded, color: Colors.white.withValues(alpha: 0.6), size: 20),
          ),
      ]),
    );
  }

  Widget _nowPlaying(BuildContext context) {
    final playback = context.playback;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        const Icon(Icons.play_circle_fill_rounded, color: KPalette.orange, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('En cours de lecture'), style: kTextD(12, color: Colors.white.withValues(alpha: 0.65))),
            Text(playback.current!.name, style: kTextD(15, weight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: KPalette.magenta),
          onPressed: () {
            final kind = playback.current!.kind == MediaKind.episode ? MediaKind.series : playback.current!.kind;
            context.navigation
              ..go(screenFor(kind))
              ..openPlayer();
          },
          child: Text(tr('Retourner à la lecture')),
        ),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: playback.stop, child: Text(tr('Arrêter'))),
      ]),
    );
  }

  Widget _welcome(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        const Icon(Icons.settings_input_antenna_rounded, color: KPalette.orange, size: 30),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Aucune source'), style: kTextD(16, weight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(tr('Ajoutez votre abonnement IPTV (Xtream Codes ou playlist M3U) pour commencer.'),
                style: kTextD(13, color: Colors.white.withValues(alpha: 0.7))),
          ]),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: KPalette.magenta),
          onPressed: () => showSettingsDialog(context, tab: SettingsTab.sources, startAdding: true),
          child: Text(tr('Ajouter une source')),
        ),
      ]),
    );
  }

  String _count(MediaKind kind, String one, String many) {
    final n = context.library.count(kind);
    if (n == 0) return context.library.isBusy ? tr('Chargement…') : '';
    return '${_formatNumber(n)} ${tr(n == 1 ? one : many)}';
  }

  String _libraryCount() {
    final library = context.library;
    final n = library.libraryItems().length;
    if (n == 0) return library.loadingSources.isNotEmpty ? tr('Chargement…') : tr('Dossiers et serveurs');
    return '${_formatNumber(n)} ${tr(n == 1 ? 'vidéo' : 'vidéos')}';
  }

  static String _formatNumber(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  Widget _bigTiles(BuildContext context, double height) {
    final navigation = context.navigation;
    final tiles = <Widget>[
      Expanded(
        child: HomeBigTile(
          title: tr('Direct'),
          icon: Icons.sensors_rounded,
          subtitle: _count(MediaKind.live, 'chaîne', 'chaînes'),
          colors: const [KPalette.magenta, KPalette.orange],
          height: height,
          onTap: () => navigation.go(Screen.live),
        ),
      ),
      const SizedBox(width: 18),
      Expanded(
        child: HomeBigTile(
          title: tr('Films'),
          icon: Icons.movie_outlined,
          subtitle: _count(MediaKind.movie, 'film', 'films'),
          colors: const [KPalette.violet, KPalette.magenta],
          height: height,
          onTap: () => navigation.go(Screen.movies),
        ),
      ),
      const SizedBox(width: 18),
      Expanded(
        child: HomeBigTile(
          title: tr('Séries'),
          icon: Icons.video_library_outlined,
          subtitle: _count(MediaKind.series, 'série', 'séries'),
          colors: const [KPalette.indigo, KPalette.violet],
          height: height,
          onTap: () => navigation.go(Screen.series),
        ),
      ),
      // Vidéothèque : seulement avec des dossiers ou un serveur Jellyfin, Emby, Plex.
      if (context.library.hasLibrary) ...[
        const SizedBox(width: 18),
        Expanded(
          child: HomeBigTile(
            title: tr('Mes vidéos'),
            icon: Icons.perm_media_outlined,
            subtitle: _libraryCount(),
            colors: const [KPalette.orange, KPalette.violet],
            height: height,
            onTap: () => navigation.go(Screen.library),
          ),
        ),
      ],
    ];
    return _tileGrid(tiles);
  }

  /// Tuiles en une rangée, ou en grille 2 colonnes sur petit écran.
  Widget _tileGrid(List<Widget> items) {
    final tiles = items.whereType<Expanded>().toList();
    if (!_compact) return Row(children: items);
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 12));
      rows.add(Row(children: [
        tiles[i],
        const SizedBox(width: 12),
        i + 1 < tiles.length ? tiles[i + 1] : const Expanded(child: SizedBox()),
      ]));
    }
    return Column(children: rows);
  }

  Widget _quickButtons(BuildContext context) {
    final library = context.library;
    final navigation = context.navigation;
    final buttons = [
      HomeSmallButton(title: tr('Favoris'), icon: Icons.star_rounded, badge: library.favoriteIds.length,
          onTap: () => navigation.show(MediaKind.live, const FavoriteItems())),
      HomeSmallButton(title: tr('Récents'), icon: Icons.history_rounded, badge: library.recentIds.length,
          onTap: () => navigation.show(MediaKind.live, const RecentItems())),
      HomeSmallButton(title: tr('Guide TV'), icon: Icons.calendar_month_rounded, badge: 0, onTap: () => navigation.go(Screen.guide)),
      HomeSmallButton(title: tr('MultiVue'), icon: Icons.grid_view_rounded, badge: context.multiview.channels.length, onTap: () => openMultiView(context)),
      HomeSmallButton(title: 'YouTube', icon: Icons.smart_display_rounded, badge: 0, onTap: () => navigation.go(Screen.youtube)),
      HomeSmallButton(
          title: tr('Enregistrements'),
          icon: Icons.radio_button_checked_rounded,
          badge: context.downloads.pendingCount + context.recordings.schedules.where((s) => s.status.name == 'scheduled').length,
          onTap: () => navigation.go(Screen.recordings)),
    ];
    return LayoutBuilder(builder: (context, c) {
      final columns = math.max(1, math.min(5, (c.maxWidth / 200).floor()));
      final width = (c.maxWidth - (columns - 1) * 14) / columns;
      return Wrap(spacing: 14, runSpacing: 14, children: [for (final b in buttons) SizedBox(width: width, child: b)]);
    });
  }

  /// « Reprendre la lecture » : films et épisodes entamés.
  Widget _resumeRail(BuildContext context) {
    final watch = context.watch;
    final started = context.library.recents.where((i) => i.kind != MediaKind.live && watch.fraction(i.id) != null).take(14).toList();
    if (started.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Reprendre la lecture'), style: kTextD(18, weight: FontWeight.w600)),
        const SizedBox(height: 10),
        SizedBox(
          height: kPosterWidth * 1.5 + 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: started.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) => MediaCard(item: started[i]),
          ),
        ),
      ]),
    );
  }

  Widget _searchResults(BuildContext context) {
    if (_results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(child: Text(tr('Aucun résultat'), style: kTextD(15, color: Colors.white.withValues(alpha: 0.6)))),
      );
    }
    return Column(children: [
      for (final item in _results)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Hover(
            onTap: () => openItem(context, item),
            builder: (context, hovering) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: hovering ? 0.16 : 0.07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                LogoView(url: item.logo, name: item.name, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.name, style: kTextD(14), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(item.group, style: kTextD(12, color: Colors.white.withValues(alpha: 0.6)), maxLines: 1),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.4)),
              ]),
            ),
          ),
        ),
    ]);
  }
}

/// Grand pavé (Direct, Films, Séries).
class HomeBigTile extends StatelessWidget {
  const HomeBigTile({
    super.key,
    required this.title,
    required this.icon,
    required this.subtitle,
    required this.colors,
    required this.height,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final String subtitle;
  final List<Color> colors;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hover(
      onTap: onTap,
      builder: (context, hovering) => AnimatedScale(
        scale: hovering ? 1.025 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              colors: [for (final c in colors) c.withValues(alpha: 0.88)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: hovering ? 0.7 : 0.15),
              width: hovering ? 2.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: hovering ? 0.5 : 0.3),
                blurRadius: hovering ? 36 : 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Stack(children: [
              Positioned(
                top: 14,
                right: 10,
                child: Icon(icon, size: 120, color: Colors.white.withValues(alpha: 0.18)),
              ),
              Positioned(
                left: 22,
                bottom: 22,
                right: 22,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, size: 30, color: Colors.white),
                  const SizedBox(height: 4),
                  Text(title, style: kRoundedD(32, FontWeight.w800)),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 18,
                    child: Text(subtitle, style: kTextD(14, color: Colors.white.withValues(alpha: 0.8))),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Petit bouton d'accès rapide.
class HomeSmallButton extends StatelessWidget {
  const HomeSmallButton({super.key, required this.title, required this.icon, required this.badge, required this.onTap});
  final String title;
  final IconData icon;
  final int badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Hover(
        onTap: onTap,
        builder: (context, hovering) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: hovering ? 0.2 : 0.11),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: hovering ? 0.4 : 0.12)),
          ),
          child: Row(children: [
            SizedBox(width: 26, child: Icon(icon, color: KPalette.orange, size: 22)),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: kTextD(15, weight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                child: Text('$badge', style: kTextD(12, weight: FontWeight.w600)),
              ),
          ]),
        ),
      ),
    );
  }
}
