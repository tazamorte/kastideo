import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kastideo/theme.dart';
import 'package:kastideo/ui/widgets.dart';

void main() {
  Widget pane({required double width, required ValueChanged<double> onChanged}) => MaterialApp(
        home: Scaffold(
          body: Row(children: [
            ResizablePane(
              width: width,
              min: 200,
              max: 500,
              defaultWidth: 260,
              onChanged: onChanged,
              child: const ColoredBox(key: Key('content'), color: Colors.red),
            ),
            const Expanded(child: SizedBox()),
          ]),
        ),
      );

  testWidgets('la barre latérale se règle en tirant son bord, dans ses limites', (tester) async {
    double? saved;
    await tester.pumpWidget(pane(width: 260, onChanged: (w) => saved = w));
    expect(tester.getSize(find.byKey(const Key('content'))).width, 260);

    final handle = tester.getCenter(find.byKey(const Key('content'))).translate(133, 0);
    await tester.dragFrom(handle, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(saved, closeTo(340, 1));

    await tester.dragFrom(handle, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(saved, 200);
  });

  test('texte lisible sur les couleurs d\'accent', () {
    for (final accent in AccentChoice.values) {
      for (final bg in [accent.dark, accent.light]) {
        final fg = onColor(bg);
        final l1 = bg.computeLuminance(), l2 = fg.computeLuminance();
        final ratio = (l1 > l2 ? l1 + 0.05 : l2 + 0.05) / (l1 > l2 ? l2 + 0.05 : l1 + 0.05);
        expect(ratio, greaterThan(3.0), reason: '$accent $bg');
      }
    }
  });
}
