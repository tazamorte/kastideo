import '../l10n.dart';
import 'text.dart';

/// Pays (ou langue) d'une catégorie ou d'un titre, repéré dans son nom (comme CountryDetector sur Mac) :
/// « FR| CINÉMA », « |PT| FILMES », « [IT] Film », « FRANCE HD », « VOSTFR »…
class Countries {
  Countries._();

  static const codes = {
    'FR', 'PT', 'BR', 'IT', 'ES', 'EN', 'UK', 'US', 'DE', 'AR', 'TR', 'PL', 'NL', 'BE', 'CH', 'CA', 'QC', 'IN', 'PK', 'RU', //
    'GR', 'RO', 'AL', 'MA', 'DZ', 'TN', 'LAT', 'EXYU', 'SE', 'NO', 'DK', 'FI', 'IR', 'KU', 'AF', 'MX', 'AT', 'HU', 'CZ', 'SK',
    'BG', 'HR', 'RS', 'IL', 'CN', 'JP', 'KR', 'PH', 'TH', 'VN', 'ID', 'MY', 'SA', 'AE', 'EG', 'LB', 'SY', 'IQ', 'BD', 'LK',
  };

  static const _aliases = {
    'FRANCE': 'FR', 'FRENCH': 'FR', 'FRANCAIS': 'FR', 'FRANCAISE': 'FR', 'VF': 'FR', 'VFF': 'FR', 'VFQ': 'QC', 'VOSTFR': 'FR',
    'PORTUGAL': 'PT', 'PORTUGUESE': 'PT', 'PORTUGUES': 'PT', 'PORTUGUESA': 'PT',
    'BRASIL': 'BR', 'BRAZIL': 'BR', 'BRAZILIAN': 'BR', 'BRASILEIRO': 'BR',
    'ITALIA': 'IT', 'ITALY': 'IT', 'ITALIAN': 'IT', 'ITALIANO': 'IT',
    'ESPANA': 'ES', 'SPAIN': 'ES', 'SPANISH': 'ES', 'ESPANOL': 'ES', 'CASTELLANO': 'ES', 'LATINO': 'LAT', 'LATAM': 'LAT',
    'ENGLISH': 'EN', 'GB': 'UK', 'USA': 'US', 'GERMANY': 'DE', 'DEUTSCH': 'DE', 'GERMAN': 'DE', 'DEUTSCHLAND': 'DE',
    'ARABIC': 'AR', 'ARAB': 'AR', 'ARABIA': 'AR', 'TURKEY': 'TR', 'TURKISH': 'TR', 'TURKIYE': 'TR', 'POLAND': 'PL', 'POLSKA': 'PL',
    'NETHERLANDS': 'NL', 'DUTCH': 'NL', 'NEDERLAND': 'NL', 'BELGIUM': 'BE', 'BELGIQUE': 'BE', 'SUISSE': 'CH', 'SWISS': 'CH',
    'CANADA': 'CA', 'QUEBEC': 'QC', 'AFRICA': 'AF', 'AFRIQUE': 'AF', 'INDIA': 'IN', 'HINDI': 'IN', 'PAKISTAN': 'PK',
    'RUSSIA': 'RU', 'RUSSIAN': 'RU', 'GREECE': 'GR', 'GREEK': 'GR', 'ROMANIA': 'RO', 'ALBANIA': 'AL', 'MAGHREB': 'MA',
    'MAROC': 'MA', 'MOROCCO': 'MA', 'ALGERIE': 'DZ', 'ALGERIA': 'DZ', 'TUNISIE': 'TN', 'TUNISIA': 'TN', 'KURDISH': 'KU',
    'IRAN': 'IR', 'PERSIAN': 'IR', 'SWEDEN': 'SE', 'NORWAY': 'NO', 'DENMARK': 'DK', 'FINLAND': 'FI', 'MEXICO': 'MX',
    'AUSTRIA': 'AT', 'HUNGARY': 'HU', 'CZECH': 'CZ', 'BULGARIA': 'BG', 'CROATIA': 'HR', 'SERBIA': 'RS', 'ISRAEL': 'IL',
    'CHINA': 'CN', 'CHINESE': 'CN', 'JAPAN': 'JP', 'JAPANESE': 'JP', 'KOREA': 'KR', 'KOREAN': 'KR',
  };

  static final _prefix = RegExp(r'^[\s|\[\(\{#*-]*([A-Z]{2,4})(?:[\s\]\)\}]*[|:\]\)\-–]|\s+[-–|:])');
  static final _bracketed = RegExp(r'[|\[\(]\s*([A-Z]{2,4})\s*[|\]\)]');

  /// Code du pays, ou null si le nom n'en indique pas.
  static String? of(String text) {
    final upper = text.searchKey.toUpperCase();
    final p = _prefix.firstMatch(upper);
    if (p != null) {
      final c = _normalize(p.group(1)!);
      if (c != null) return c;
    }
    for (final m in _bracketed.allMatches(upper)) {
      final c = _normalize(m.group(1)!);
      if (c != null) return c;
    }
    for (final word in upper.split(RegExp(r'[^A-Z]+'))) {
      if (word.length < 4 && word != 'VF' && word != 'VFF' && word != 'VFQ' && word != 'USA') continue;
      final c = _aliases[word];
      if (c != null) return c;
    }
    return null;
  }

  static String? _normalize(String token) {
    final alias = _aliases[token];
    if (alias != null) return alias;
    if (codes.contains(token)) return token;
    // « MLFR », « MLDE »… : version multilingue d'un pays.
    if (token.length == 4 && token.startsWith('ML')) return _normalize(token.substring(2));
    return null;
  }

  /// Nom du pays affiché dans les réglages.
  static String name(String code) {
    final fr = !L10n.english;
    const namesFr = {
      'FR': 'France', 'PT': 'Portugal', 'BR': 'Brésil', 'IT': 'Italie', 'ES': 'Espagne', 'EN': 'Anglais', 'UK': 'Royaume-Uni',
      'US': 'États-Unis', 'DE': 'Allemagne', 'AR': 'Arabe', 'TR': 'Turquie', 'PL': 'Pologne', 'NL': 'Pays-Bas', 'BE': 'Belgique',
      'CH': 'Suisse', 'CA': 'Canada', 'QC': 'Québec', 'IN': 'Inde', 'PK': 'Pakistan', 'RU': 'Russie', 'GR': 'Grèce',
      'RO': 'Roumanie', 'AL': 'Albanie', 'MA': 'Maroc', 'DZ': 'Algérie', 'TN': 'Tunisie', 'LAT': 'Amérique latine',
      'EXYU': 'Ex-Yougoslavie', 'AF': 'Afrique', 'MX': 'Mexique', 'IR': 'Iran', 'KU': 'Kurde', 'SE': 'Suède', 'NO': 'Norvège',
      'DK': 'Danemark', 'FI': 'Finlande', 'CN': 'Chine', 'JP': 'Japon', 'KR': 'Corée',
    };
    const namesEn = {
      'FR': 'France', 'PT': 'Portugal', 'BR': 'Brazil', 'IT': 'Italy', 'ES': 'Spain', 'EN': 'English', 'UK': 'United Kingdom',
      'US': 'United States', 'DE': 'Germany', 'AR': 'Arabic', 'TR': 'Turkey', 'PL': 'Poland', 'NL': 'Netherlands', 'BE': 'Belgium',
      'CH': 'Switzerland', 'CA': 'Canada', 'QC': 'Quebec', 'IN': 'India', 'PK': 'Pakistan', 'RU': 'Russia', 'GR': 'Greece',
      'RO': 'Romania', 'AL': 'Albania', 'MA': 'Morocco', 'DZ': 'Algeria', 'TN': 'Tunisia', 'LAT': 'Latin America',
      'EXYU': 'Ex-Yugoslavia', 'AF': 'Africa', 'MX': 'Mexico', 'IR': 'Iran', 'KU': 'Kurdish', 'SE': 'Sweden', 'NO': 'Norway',
      'DK': 'Denmark', 'FI': 'Finland', 'CN': 'China', 'JP': 'Japan', 'KR': 'Korea',
    };
    return (fr ? namesFr : namesEn)[code] ?? code;
  }
}
