import 'package:flutter_test/flutter_test.dart';
import 'package:kastideo/core/countries.dart';

void main() {
  test('Pays repérés dans les noms de catégories', () {
    expect(Countries.of('FR| CINÉMA'), 'FR');
    expect(Countries.of('|PT| FILMES'), 'PT');
    expect(Countries.of('PT - FILMES 2024'), 'PT');
    expect(Countries.of('[IT] Film'), 'IT');
    expect(Countries.of('FRANCE HD'), 'FR');
    expect(Countries.of('Films VOSTFR'), 'FR');
    expect(Countries.of('ITALIA'), 'IT');
    expect(Countries.of('BRASIL | NOVELAS'), 'BR');
    expect(Countries.of('EN: Movies 4K'), 'EN');
    expect(Countries.of('|DE| Dark'), 'DE');
    expect(Countries.of('MLFR| Les Revenants'), 'FR');
    expect(Countries.of('|MLFR| Les Revenants'), 'FR');
    expect(Countries.of('MLXX| Test'), isNull);
    expect(Countries.of('Action'), isNull);
    expect(Countries.of('Nouveautés'), isNull);
    expect(Countries.of('SPORT'), isNull);
    expect(Countries.of('MOVIES IN 4K'), isNull);
    expect(Countries.of('TV SHOWS'), isNull);
  });
}
