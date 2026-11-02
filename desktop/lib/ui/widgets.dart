import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/settings.dart';
import '../l10n.dart';

import '../core/text.dart';
import '../theme.dart';

/// Construit un widget différent au survol de la souris ou quand il a le focus (flèches du clavier, télécommande).
/// OK / Entrée / Espace déclenchent [onTap] ; un appui long ou la touche Menu déclenchent [onMenu].
class Hover extends StatefulWidget {
  const Hover({super.key, required this.builder, this.onTap, this.onMenu, this.cursor = SystemMouseCursors.click, this.autofocus = false});
  final Widget Function(BuildContext context, bool hovering) builder;
  final VoidCallback? onTap;
  final void Function(MenuPoint point)? onMenu;
  final MouseCursor cursor;
  final bool autofocus;

  @override
  State<Hover> createState() => _HoverState();
}

class _HoverState extends State<Hover> {
  bool _hovering = false;
  bool _focused = false;

  Offset _center() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) return box.localToGlobal(box.size.center(Offset.zero));
    return Offset.zero;
  }

  @override
  Widget build(BuildContext context) {
    final tappable = widget.onTap != null;
    if (!tappable) {
      // Sans action : simple effet de survol, pas de focus.
      return MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPressStart: widget.onMenu == null ? null : (d) => widget.onMenu!(MenuPoint(d.globalPosition)),
          child: widget.builder(context, _hovering),
        ),
      );
    }
    return FocusableActionDetector(
      enabled: true,
      autofocus: widget.autofocus,
      mouseCursor: tappable ? widget.cursor : MouseCursor.defer,
      onShowHoverHighlight: (v) => setState(() => _hovering = v),
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap?.call();
          return null;
        }),
      },
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.contextMenu): _MenuIntent(),
      },
      child: Actions(
        actions: {
          _MenuIntent: CallbackAction<_MenuIntent>(onInvoke: (_) {
            widget.onMenu?.call(MenuPoint(_center()));
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onLongPressStart: widget.onMenu == null ? null : (d) => widget.onMenu!(MenuPoint(d.globalPosition)),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: _focused ? Border.all(color: KPalette.accent, width: 2.5) : null,
            ),
            child: widget.builder(context, _hovering || _focused),
          ),
        ),
      ),
    );
  }
}

class _MenuIntent extends Intent {
  const _MenuIntent();
}

/// Position d'un menu contextuel (clic droit, appui long, touche Menu de la télécommande).
class MenuPoint {
  const MenuPoint(this.globalPosition);
  final Offset globalPosition;
}

/// Ajoute à son contenu le menu contextuel : clic droit à la souris, appui long au doigt, touche Menu à la télécommande.
class MenuTap extends StatelessWidget {
  const MenuTap({super.key, required this.onMenu, required this.child});
  final void Function(MenuPoint point) onMenu;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.contextMenu): () {
          final box = context.findRenderObject();
          if (box is RenderBox && box.hasSize) onMenu(MenuPoint(box.localToGlobal(box.size.center(Offset.zero))));
        },
      },
      child: GestureDetector(
        onSecondaryTapUp: (d) => onMenu(MenuPoint(d.globalPosition)),
        onLongPressStart: (d) => onMenu(MenuPoint(d.globalPosition)),
        child: child,
      ),
    );
  }
}

/// Barre latérale fixe sur grand écran ; sur téléphone, elle devient un tiroir ouvert par le bouton ☰.
class SidebarShell extends StatefulWidget {
  const SidebarShell({super.key, required this.sidebar, required this.child, this.title = ''});
  final Widget sidebar;
  final Widget child;
  final String title;

  /// Largeur à partir de laquelle la barre latérale reste affichée.
  static const wide = 900.0;

  @override
  State<SidebarShell> createState() => _SidebarShellState();
}

class _SidebarShellState extends State<SidebarShell> {
  final _key = GlobalKey<ScaffoldState>();
  NavigationModel? _nav;

  void _closeDrawer() {
    if (_key.currentState?.isDrawerOpen ?? false) _key.currentState?.closeDrawer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nav = context.navigation;
    if (!identical(nav, _nav)) {
      _nav?.removeListener(_closeDrawer);
      _nav = nav..addListener(_closeDrawer);
    }
  }

  @override
  void dispose() {
    _nav?.removeListener(_closeDrawer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= SidebarShell.wide) {
      final settings = context.settings;
      return ListenableBuilder(
        listenable: settings,
        builder: (context, _) => Row(children: [
          ResizablePane(
            width: settings.sidebarWidth,
            min: 200,
            max: (width * 0.35).clamp(240.0, 520.0),
            defaultWidth: AppSettings.sidebarWidthDefault,
            onChanged: (w) => settings.setDouble('layout.sidebarWidth', w),
            child: widget.sidebar,
          ),
          Expanded(child: widget.child),
        ]),
      );
    }
    return Scaffold(
      key: _key,
      backgroundColor: Colors.transparent,
      drawer: Drawer(width: 280, backgroundColor: KPalette.sidebar, child: SafeArea(child: widget.sidebar)),
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SizedBox(
            height: 44,
            child: Row(children: [
              IconButton(
                tooltip: tr('Menu'),
                icon: Icon(Icons.menu_rounded, color: KPalette.ink),
                onPressed: () => _key.currentState?.openDrawer(),
              ),
              Expanded(child: Text(widget.title, style: kText(15, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
          ),
          Expanded(child: widget.child),
        ]),
      ),
    );
  }
}

/// Panneau dont on règle la largeur en tirant son bord droit (double-clic : largeur d'origine).
class ResizablePane extends StatefulWidget {
  const ResizablePane({
    super.key,
    required this.width,
    required this.min,
    required this.max,
    required this.defaultWidth,
    required this.onChanged,
    required this.child,
  });
  final double width;
  final double min;
  final double max;
  final double defaultWidth;
  final ValueChanged<double> onChanged;
  final Widget child;

  @override
  State<ResizablePane> createState() => _ResizablePaneState();
}

class _ResizablePaneState extends State<ResizablePane> {
  double? _dragging;
  bool _hovering = false;

  double _clamp(double w) => w.clamp(widget.min, math.max(widget.min, widget.max));

  void _end() {
    final w = _dragging;
    setState(() => _dragging = null);
    if (w != null && w != widget.width) widget.onChanged(w);
  }

  @override
  Widget build(BuildContext context) {
    final width = _clamp(_dragging ?? widget.width);
    final active = _hovering || _dragging != null;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: width, child: widget.child),
      Tooltip(
        message: tr('Tirer pour élargir ou réduire · double-clic : largeur d\'origine'),
        waitDuration: const Duration(seconds: 1),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: (_) => setState(() => _dragging = width),
            onHorizontalDragUpdate: (d) => setState(() => _dragging = _clamp((_dragging ?? width) + d.delta.dx)),
            onHorizontalDragEnd: (_) => _end(),
            onHorizontalDragCancel: _end,
            onDoubleTap: () => widget.onChanged(widget.defaultWidth),
            child: SizedBox(
              width: 6,
              child: Center(
                child: Container(width: active ? 3 : 1, color: active ? KPalette.accent : KPalette.separator),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Logo de chaîne (image du fournisseur, sinon initiales sur fond dégradé).
class LogoView extends StatelessWidget {
  const LogoView({super.key, required this.url, required this.name, this.size = 36});
  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = _Initials(name: name, size: size);
    final radius = BorderRadius.circular(size * 0.22);
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: size,
        height: size,
        color: KPalette.ink.withValues(alpha: 0.06),
        child: url == null
            ? fallback
            : url!.startsWith('file:')
                ? Image.file(File.fromUri(Uri.parse(url!)), width: size, height: size, fit: BoxFit.contain, errorBuilder: (_, _, _) => fallback)
                : Image.network(
                url!,
                width: size,
                height: size,
                fit: BoxFit.contain,
                cacheWidth: (size * 2).round(),
                filterQuality: FilterQuality.medium,
                headers: const {'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20'},
                errorBuilder: (_, _, _) => fallback,
                loadingBuilder: (context, child, progress) => progress == null ? child : fallback,
              ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.name, required this.size});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hue = (name.hashCode % 360).abs().toDouble();
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [HSLColor.fromAHSL(1, hue, 0.45, 0.32).toColor(), HSLColor.fromAHSL(1, (hue + 40) % 360, 0.5, 0.22).toColor()],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Text(initials(name), style: kRounded(size * 0.36, FontWeight.w800)),
    );
  }
}

/// Fond dégradé de l'accueil (mêmes dégradés que la version Mac).
class KastideoBackground extends StatelessWidget {
  const KastideoBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [KPalette.night, Color.fromRGBO(87, 26, 140, 0.9), KPalette.night],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.bottomRight,
            radius: 1.1,
            colors: [KPalette.magenta.withValues(alpha: 0.45), Colors.transparent],
          ),
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 0.8,
            colors: [KPalette.orange.withValues(alpha: 0.18), Colors.transparent],
          ),
        ),
      ),
    ]);
  }
}

/// Affiche (film, série) : image du fournisseur ou de TMDB, sinon dégradé avec le titre.
class PosterImage extends StatelessWidget {
  const PosterImage({super.key, required this.url, required this.name, required this.width, required this.height, this.fit = BoxFit.cover});
  final String? url;
  final String name;
  final double width;
  final double height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: width,
      height: height,
      padding: EdgeInsets.all(width * 0.08),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF383838), Color(0xFF1C1C1C)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
      ),
      child: width < 60
          ? Text(initials(name), style: kRounded(width * 0.32, FontWeight.w800, color: Colors.white70))
          : Text(cleanTitle(name).title,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: kRounded(width * 0.11, FontWeight.w800, color: Colors.white70)),
    );
    if (url == null) return fallback;
    return Image.network(
      url!,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: (width * 2).round(),
      filterQuality: FilterQuality.medium,
      headers: const {'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20'},
      errorBuilder: (_, _, _) => fallback,
      frameBuilder: (context, child, frame, sync) => frame == null && !sync ? fallback : child,
    );
  }
}

/// Défilement à la souris : les rangées horizontales se font aussi glisser avec la souris.
class KastideoScrollBehavior extends MaterialScrollBehavior {
  const KastideoScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices =>
      {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus};
}

/// Ligne horizontale qui défile aussi avec la molette verticale (pastilles de filtres).
class WheelRow extends StatefulWidget {
  const WheelRow({super.key, required this.children});
  final List<Widget> children;

  @override
  State<WheelRow> createState() => _WheelRowState();
}

class _WheelRowState extends State<WheelRow> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerSignal: (event) {
          if (event is! PointerScrollEvent || !_controller.hasClients) return;
          final delta = event.scrollDelta.dy.abs() > event.scrollDelta.dx.abs() ? event.scrollDelta.dy : event.scrollDelta.dx;
          final position = _controller.position;
          _controller.jumpTo((position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent));
        },
        child: SingleChildScrollView(controller: _controller, scrollDirection: Axis.horizontal, child: Row(children: widget.children)),
      );
}

/// Liste de choix adaptée au tactile : un champ qui ouvre une fenêtre avec recherche et lignes à toucher
/// (remplace le menu déroulant, difficile à utiliser avec une longue liste de catégories sur tablette).
class PickerField<T> extends StatelessWidget {
  const PickerField({super.key, required this.value, required this.options, required this.onChanged, this.title});
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final label = options.where((o) => o.$1 == value).map((o) => o.$2).firstOrNull ?? '';
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final result = await showKDialog<(T,)>(
          context: context,
          builder: (_) => _PickerDialog<T>(title: title, value: value, options: options),
        );
        if (result != null) onChanged(result.$1);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: KPalette.secondaryText.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Expanded(child: Text(label, style: kText(13), overflow: TextOverflow.ellipsis)),
          const Icon(Icons.arrow_drop_down_rounded),
        ]),
      ),
    );
  }
}

class _PickerDialog<T> extends StatefulWidget {
  const _PickerDialog({required this.title, required this.value, required this.options});
  final String? title;
  final T value;
  final List<(T, String)> options;

  @override
  State<_PickerDialog<T>> createState() => _PickerDialogState<T>();
}

class _PickerDialogState<T> extends State<_PickerDialog<T>> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final key = _filter.searchKey;
    final shown = key.isEmpty ? widget.options : widget.options.where((o) => o.$2.searchKey.contains(key)).toList();
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: widget.title == null ? null : Text(widget.title!),
      content: SizedBox(
        width: 420,
        height: (size.height * 0.6).clamp(240.0, 560.0),
        child: Column(children: [
          if (widget.options.length > 8)
            TextField(
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: tr('Rechercher'), isDense: true),
              onChanged: (v) => setState(() => _filter = v),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (context, i) {
                final (v, l) = shown[i];
                final selected = v == widget.value;
                return ListTile(
                  dense: true,
                  selected: selected,
                  title: Text(l, style: kText(14), maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: selected ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.pop(context, (v,)),
                );
              },
            ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annuler')))],
    );
  }
}
