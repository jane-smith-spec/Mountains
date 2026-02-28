/// Region data — country and state/province definitions for DEM downloads.
///
/// Organizes downloadable regions into a two-level hierarchy:
///   Country → State/Province
///
/// Users can download an entire country (broad) or pick individual
/// states/provinces (fine-grained) based on their storage preferences.
///
/// Each region is defined by a bounding box that maps directly to
/// 1°×1° DEM tiles via [TileIndex.tilesInBbox].
library;

import '../models/tile_index.dart';

// -----------------------------------------------------------------------
//  Data model
// -----------------------------------------------------------------------

/// A geographic region defined by its bounding box.
class RegionBbox {
  const RegionBbox({
    required this.minLat,
    required this.minLon,
    required this.maxLat,
    required this.maxLon,
  });

  final double minLat;
  final double minLon;
  final double maxLat;
  final double maxLon;

  /// All 1°×1° tiles covered by this bounding box.
  Set<TileIndex> get tiles {
    final result = <TileIndex>{};
    for (int lat = minLat.floor(); lat <= maxLat.floor(); lat++) {
      for (int lon = minLon.floor(); lon <= maxLon.floor(); lon++) {
        result.add(TileIndex(latDeg: lat, lonDeg: lon));
      }
    }
    return result;
  }

  /// Estimated download size in MB (full resolution, ~25 MB per tile).
  double get estimatedSizeMB => tiles.length * 25.0;
}

/// A state, province, or sub-national region within a country.
class StateRegion {
  const StateRegion({
    required this.name,
    required this.bbox,
    this.description,
  });

  final String name;
  final String? description;
  final RegionBbox bbox;
}

/// A country containing one or more state/province regions.
class Country {
  const Country({
    required this.name,
    required this.code,
    required this.emoji,
    required this.states,
  });

  final String name;

  /// ISO 3166-1 alpha-2 code.
  final String code;

  /// Flag emoji for display.
  final String emoji;

  /// Sub-regions (states, provinces, cantons, etc.).
  final List<StateRegion> states;

  /// Bounding box covering the entire country (union of all states).
  RegionBbox get bbox {
    double minLat = 90, minLon = 180, maxLat = -90, maxLon = -180;
    for (final s in states) {
      if (s.bbox.minLat < minLat) minLat = s.bbox.minLat;
      if (s.bbox.minLon < minLon) minLon = s.bbox.minLon;
      if (s.bbox.maxLat > maxLat) maxLat = s.bbox.maxLat;
      if (s.bbox.maxLon > maxLon) maxLon = s.bbox.maxLon;
    }
    return RegionBbox(
      minLat: minLat,
      minLon: minLon,
      maxLat: maxLat,
      maxLon: maxLon,
    );
  }

  /// All tiles for the entire country.
  Set<TileIndex> get tiles => bbox.tiles;
}

// -----------------------------------------------------------------------
//  Region catalog — Countries and their states/provinces
// -----------------------------------------------------------------------

/// All available countries, sorted roughly by expected demand.
final List<Country> kCountryCatalog = [
  _unitedStates,
  _switzerland,
  _austria,
  _italy,
  _france,
  _germany,
  _spain,
  _unitedKingdom,
  _norway,
  _canada,
  _japan,
  _newZealand,
  _nepal,
  _chile,
  _argentina,
  _peru,
  _mexico,
  _india,
];

// =======================================================================
//  United States
// =======================================================================

const _unitedStates = Country(
  name: 'United States',
  code: 'US',
  emoji: '\u{1F1FA}\u{1F1F8}',
  states: [
    // Western states — most mountainous
    StateRegion(
      name: 'Alaska',
      description: 'Denali, Brooks Range, Alaska Range',
      bbox: RegionBbox(minLat: 54.0, minLon: -170.0, maxLat: 71.5, maxLon: -130.0),
    ),
    StateRegion(
      name: 'Washington',
      description: 'Mt. Rainier, Cascades, Olympics',
      bbox: RegionBbox(minLat: 45.5, minLon: -124.8, maxLat: 49.0, maxLon: -116.9),
    ),
    StateRegion(
      name: 'Oregon',
      description: 'Mt. Hood, Three Sisters, Cascades',
      bbox: RegionBbox(minLat: 41.9, minLon: -124.6, maxLat: 46.3, maxLon: -116.5),
    ),
    StateRegion(
      name: 'California',
      description: 'Sierra Nevada, Mt. Whitney, Shasta',
      bbox: RegionBbox(minLat: 32.5, minLon: -124.5, maxLat: 42.0, maxLon: -114.1),
    ),
    StateRegion(
      name: 'Colorado',
      description: '14ers, Rocky Mountain NP, Front Range',
      bbox: RegionBbox(minLat: 36.9, minLon: -109.1, maxLat: 41.0, maxLon: -102.0),
    ),
    StateRegion(
      name: 'Montana',
      description: 'Glacier NP, Beartooths, Bob Marshall',
      bbox: RegionBbox(minLat: 44.3, minLon: -116.1, maxLat: 49.0, maxLon: -104.0),
    ),
    StateRegion(
      name: 'Wyoming',
      description: 'Grand Teton, Wind Rivers, Yellowstone',
      bbox: RegionBbox(minLat: 40.9, minLon: -111.1, maxLat: 45.0, maxLon: -104.0),
    ),
    StateRegion(
      name: 'Idaho',
      description: 'Sawtooths, Borah Peak, Lost River Range',
      bbox: RegionBbox(minLat: 42.0, minLon: -117.3, maxLat: 49.0, maxLon: -111.0),
    ),
    StateRegion(
      name: 'Utah',
      description: 'Wasatch Range, Uintas, Zion',
      bbox: RegionBbox(minLat: 36.9, minLon: -114.1, maxLat: 42.0, maxLon: -109.0),
    ),
    StateRegion(
      name: 'Nevada',
      description: 'Great Basin ranges, Wheeler Peak',
      bbox: RegionBbox(minLat: 35.0, minLon: -120.0, maxLat: 42.0, maxLon: -114.0),
    ),
    StateRegion(
      name: 'Arizona',
      description: 'Humphreys Peak, San Francisco Peaks',
      bbox: RegionBbox(minLat: 31.3, minLon: -114.8, maxLat: 37.0, maxLon: -109.0),
    ),
    StateRegion(
      name: 'New Mexico',
      description: 'Sangre de Cristo, Wheeler Peak, Sandias',
      bbox: RegionBbox(minLat: 31.3, minLon: -109.1, maxLat: 37.0, maxLon: -103.0),
    ),
    // Eastern states with notable peaks
    StateRegion(
      name: 'New Hampshire',
      description: 'Mt. Washington, White Mountains',
      bbox: RegionBbox(minLat: 42.7, minLon: -72.6, maxLat: 45.3, maxLon: -70.7),
    ),
    StateRegion(
      name: 'Vermont',
      description: 'Green Mountains, Mt. Mansfield',
      bbox: RegionBbox(minLat: 42.7, minLon: -73.5, maxLat: 45.0, maxLon: -71.5),
    ),
    StateRegion(
      name: 'Maine',
      description: 'Mt. Katahdin, Baxter State Park',
      bbox: RegionBbox(minLat: 43.0, minLon: -71.1, maxLat: 47.5, maxLon: -66.9),
    ),
    StateRegion(
      name: 'New York',
      description: 'Adirondacks, Catskills, Mt. Marcy',
      bbox: RegionBbox(minLat: 40.5, minLon: -79.8, maxLat: 45.0, maxLon: -71.8),
    ),
    StateRegion(
      name: 'North Carolina',
      description: 'Mt. Mitchell, Blue Ridge, Great Smokies',
      bbox: RegionBbox(minLat: 33.8, minLon: -84.3, maxLat: 36.6, maxLon: -75.5),
    ),
    StateRegion(
      name: 'Tennessee',
      description: 'Great Smoky Mountains, Clingmans Dome',
      bbox: RegionBbox(minLat: 34.9, minLon: -90.3, maxLat: 36.7, maxLon: -81.6),
    ),
    StateRegion(
      name: 'Virginia',
      description: 'Shenandoah, Blue Ridge, Mt. Rogers',
      bbox: RegionBbox(minLat: 36.5, minLon: -83.7, maxLat: 39.5, maxLon: -75.2),
    ),
    StateRegion(
      name: 'West Virginia',
      description: 'Spruce Knob, Allegheny Mountains',
      bbox: RegionBbox(minLat: 37.2, minLon: -82.7, maxLat: 40.6, maxLon: -77.7),
    ),
    StateRegion(
      name: 'Hawaii',
      description: 'Mauna Kea, Mauna Loa, Haleakala',
      bbox: RegionBbox(minLat: 18.9, minLon: -160.3, maxLat: 22.3, maxLon: -154.8),
    ),
  ],
);

// =======================================================================
//  Switzerland
// =======================================================================

const _switzerland = Country(
  name: 'Switzerland',
  code: 'CH',
  emoji: '\u{1F1E8}\u{1F1ED}',
  states: [
    StateRegion(
      name: 'Valais',
      description: 'Matterhorn, Monte Rosa, Dom',
      bbox: RegionBbox(minLat: 45.8, minLon: 6.7, maxLat: 46.7, maxLon: 8.5),
    ),
    StateRegion(
      name: 'Bern (Oberland)',
      description: 'Eiger, Jungfrau, Mönch, Finsteraarhorn',
      bbox: RegionBbox(minLat: 46.3, minLon: 7.0, maxLat: 47.4, maxLon: 8.5),
    ),
    StateRegion(
      name: 'Graubünden',
      description: 'Piz Bernina, Engadin, Davos',
      bbox: RegionBbox(minLat: 46.1, minLon: 8.6, maxLat: 47.1, maxLon: 10.5),
    ),
    StateRegion(
      name: 'Uri',
      description: 'Dammastock, Gotthard region',
      bbox: RegionBbox(minLat: 46.4, minLon: 8.3, maxLat: 47.0, maxLon: 8.9),
    ),
    StateRegion(
      name: 'Ticino',
      description: 'Adula Alps, southern valleys',
      bbox: RegionBbox(minLat: 45.8, minLon: 8.4, maxLat: 46.6, maxLon: 9.2),
    ),
    StateRegion(
      name: 'Glarus',
      description: 'Tödi, Glärnisch',
      bbox: RegionBbox(minLat: 46.7, minLon: 8.7, maxLat: 47.2, maxLon: 9.3),
    ),
    StateRegion(
      name: 'Lucerne & Central',
      description: 'Pilatus, Rigi, Titlis',
      bbox: RegionBbox(minLat: 46.7, minLon: 7.8, maxLat: 47.3, maxLon: 8.6),
    ),
    StateRegion(
      name: 'Vaud & Fribourg',
      description: 'Diablerets, Vanil Noir, Lake Geneva Alps',
      bbox: RegionBbox(minLat: 46.2, minLon: 6.1, maxLat: 47.0, maxLon: 7.3),
    ),
    StateRegion(
      name: 'Appenzell & St. Gallen',
      description: 'Säntis, Alpstein',
      bbox: RegionBbox(minLat: 47.0, minLon: 9.0, maxLat: 47.5, maxLon: 9.7),
    ),
  ],
);

// =======================================================================
//  Austria
// =======================================================================

const _austria = Country(
  name: 'Austria',
  code: 'AT',
  emoji: '\u{1F1E6}\u{1F1F9}',
  states: [
    StateRegion(
      name: 'Tyrol',
      description: 'Wildspitze, Stubai, Zillertal Alps',
      bbox: RegionBbox(minLat: 46.6, minLon: 10.1, maxLat: 47.7, maxLon: 12.7),
    ),
    StateRegion(
      name: 'Salzburg',
      description: 'Großglockner, Hohe Tauern, Berchtesgaden',
      bbox: RegionBbox(minLat: 46.8, minLon: 12.0, maxLat: 48.0, maxLon: 14.0),
    ),
    StateRegion(
      name: 'Carinthia',
      description: 'Großglockner south, Karawanks',
      bbox: RegionBbox(minLat: 46.3, minLon: 12.6, maxLat: 47.2, maxLon: 15.1),
    ),
    StateRegion(
      name: 'Vorarlberg',
      description: 'Arlberg, Silvretta, Rätikon',
      bbox: RegionBbox(minLat: 46.8, minLon: 9.5, maxLat: 47.6, maxLon: 10.3),
    ),
    StateRegion(
      name: 'Styria',
      description: 'Dachstein, Schladming, Gesäuse',
      bbox: RegionBbox(minLat: 46.6, minLon: 13.5, maxLat: 47.9, maxLon: 16.2),
    ),
    StateRegion(
      name: 'Upper Austria',
      description: 'Dachstein north, Salzkammergut',
      bbox: RegionBbox(minLat: 47.4, minLon: 13.0, maxLat: 48.8, maxLon: 15.0),
    ),
  ],
);

// =======================================================================
//  Italy
// =======================================================================

const _italy = Country(
  name: 'Italy',
  code: 'IT',
  emoji: '\u{1F1EE}\u{1F1F9}',
  states: [
    StateRegion(
      name: 'South Tyrol / Alto Adige',
      description: 'Dolomites, Ortler, Ötztal south',
      bbox: RegionBbox(minLat: 46.2, minLon: 10.3, maxLat: 47.1, maxLon: 12.5),
    ),
    StateRegion(
      name: 'Trentino',
      description: 'Brenta Dolomites, Adamello, Marmolada',
      bbox: RegionBbox(minLat: 45.7, minLon: 10.4, maxLat: 46.5, maxLon: 12.0),
    ),
    StateRegion(
      name: 'Veneto (Mountains)',
      description: 'Dolomiti Bellunesi, Cortina',
      bbox: RegionBbox(minLat: 45.8, minLon: 11.3, maxLat: 46.7, maxLon: 12.6),
    ),
    StateRegion(
      name: 'Aosta Valley',
      description: 'Mont Blanc, Gran Paradiso, Monte Rosa south',
      bbox: RegionBbox(minLat: 45.5, minLon: 6.8, maxLat: 46.0, maxLon: 7.9),
    ),
    StateRegion(
      name: 'Piedmont (Alps)',
      description: 'Monviso, Gran Paradiso south, Cottian Alps',
      bbox: RegionBbox(minLat: 44.0, minLon: 6.6, maxLat: 46.0, maxLon: 8.7),
    ),
    StateRegion(
      name: 'Lombardy (Alps)',
      description: 'Stelvio, Bernina south, Bergamo Alps',
      bbox: RegionBbox(minLat: 45.7, minLon: 8.5, maxLat: 46.7, maxLon: 10.6),
    ),
    StateRegion(
      name: 'Friuli Venezia Giulia',
      description: 'Carnic Alps, Julian Alps',
      bbox: RegionBbox(minLat: 45.6, minLon: 12.3, maxLat: 46.7, maxLon: 13.9),
    ),
    StateRegion(
      name: 'Abruzzo',
      description: 'Gran Sasso, Maiella, Apennines',
      bbox: RegionBbox(minLat: 41.7, minLon: 13.0, maxLat: 42.9, maxLon: 14.8),
    ),
    StateRegion(
      name: 'Sicily',
      description: 'Mt. Etna, Madonie, Nebrodi',
      bbox: RegionBbox(minLat: 36.6, minLon: 12.4, maxLat: 38.3, maxLon: 15.7),
    ),
    StateRegion(
      name: 'Sardinia',
      description: 'Gennargentu, Supramonte',
      bbox: RegionBbox(minLat: 38.8, minLon: 8.1, maxLat: 41.3, maxLon: 9.9),
    ),
  ],
);

// =======================================================================
//  France
// =======================================================================

const _france = Country(
  name: 'France',
  code: 'FR',
  emoji: '\u{1F1EB}\u{1F1F7}',
  states: [
    StateRegion(
      name: 'Haute-Savoie',
      description: 'Mont Blanc, Chamonix, Aravis',
      bbox: RegionBbox(minLat: 45.7, minLon: 5.8, maxLat: 46.4, maxLon: 7.0),
    ),
    StateRegion(
      name: 'Savoie',
      description: 'Vanoise, Beaufortain, Tarentaise',
      bbox: RegionBbox(minLat: 45.0, minLon: 5.6, maxLat: 45.8, maxLon: 7.2),
    ),
    StateRegion(
      name: 'Isère & Hautes-Alpes',
      description: 'Écrins, Belledonne, Oisans',
      bbox: RegionBbox(minLat: 44.5, minLon: 5.3, maxLat: 45.6, maxLon: 6.8),
    ),
    StateRegion(
      name: 'Alpes-Maritimes',
      description: 'Mercantour, Maritime Alps',
      bbox: RegionBbox(minLat: 43.5, minLon: 6.6, maxLat: 44.4, maxLon: 7.7),
    ),
    StateRegion(
      name: 'Pyrénées (West)',
      description: 'Pic du Midi d\'Ossau, Vignemale',
      bbox: RegionBbox(minLat: 42.6, minLon: -0.8, maxLat: 43.3, maxLon: 0.5),
    ),
    StateRegion(
      name: 'Pyrénées (Central & East)',
      description: 'Aneto, Monte Perdido, Pic du Canigou',
      bbox: RegionBbox(minLat: 42.3, minLon: 0.5, maxLat: 43.2, maxLon: 3.2),
    ),
    StateRegion(
      name: 'Massif Central',
      description: 'Puy de Sancy, Plomb du Cantal',
      bbox: RegionBbox(minLat: 44.5, minLon: 2.0, maxLat: 46.0, maxLon: 4.0),
    ),
    StateRegion(
      name: 'Vosges',
      description: 'Grand Ballon, Hohneck',
      bbox: RegionBbox(minLat: 47.7, minLon: 6.5, maxLat: 48.8, maxLon: 7.5),
    ),
    StateRegion(
      name: 'Jura',
      description: 'Crêt de la Neige, Mont d\'Or',
      bbox: RegionBbox(minLat: 46.0, minLon: 5.5, maxLat: 47.5, maxLon: 6.5),
    ),
    StateRegion(
      name: 'Corsica',
      description: 'Monte Cinto, GR20',
      bbox: RegionBbox(minLat: 41.4, minLon: 8.5, maxLat: 43.1, maxLon: 9.6),
    ),
  ],
);

// =======================================================================
//  Germany
// =======================================================================

const _germany = Country(
  name: 'Germany',
  code: 'DE',
  emoji: '\u{1F1E9}\u{1F1EA}',
  states: [
    StateRegion(
      name: 'Bavaria (Alps)',
      description: 'Zugspitze, Watzmann, Berchtesgaden',
      bbox: RegionBbox(minLat: 47.2, minLon: 10.0, maxLat: 47.7, maxLon: 13.2),
    ),
    StateRegion(
      name: 'Bavaria (Foothills)',
      description: 'Pre-Alps, Ammergau, Tegernsee',
      bbox: RegionBbox(minLat: 47.4, minLon: 10.5, maxLat: 48.3, maxLon: 13.0),
    ),
    StateRegion(
      name: 'Black Forest',
      description: 'Feldberg, Belchen, Schwarzwald',
      bbox: RegionBbox(minLat: 47.5, minLon: 7.5, maxLat: 48.5, maxLon: 8.5),
    ),
    StateRegion(
      name: 'Harz',
      description: 'Brocken, Wurmberg',
      bbox: RegionBbox(minLat: 51.5, minLon: 10.0, maxLat: 52.0, maxLon: 11.2),
    ),
    StateRegion(
      name: 'Saxon Switzerland',
      description: 'Elbsandsteingebirge, sandstone peaks',
      bbox: RegionBbox(minLat: 50.7, minLon: 13.8, maxLat: 51.2, maxLon: 14.4),
    ),
  ],
);

// =======================================================================
//  Spain
// =======================================================================

const _spain = Country(
  name: 'Spain',
  code: 'ES',
  emoji: '\u{1F1EA}\u{1F1F8}',
  states: [
    StateRegion(
      name: 'Aragón (Pyrenees)',
      description: 'Aneto, Monte Perdido, Ordesa',
      bbox: RegionBbox(minLat: 42.3, minLon: -0.8, maxLat: 42.9, maxLon: 1.0),
    ),
    StateRegion(
      name: 'Catalonia (Pyrenees)',
      description: 'Aigüestortes, Val d\'Aran',
      bbox: RegionBbox(minLat: 42.2, minLon: 0.7, maxLat: 42.9, maxLon: 3.3),
    ),
    StateRegion(
      name: 'Andalusia',
      description: 'Sierra Nevada, Mulhacén, Sierra de Grazalema',
      bbox: RegionBbox(minLat: 36.0, minLon: -5.6, maxLat: 38.8, maxLon: -1.6),
    ),
    StateRegion(
      name: 'Cantabria & Asturias',
      description: 'Picos de Europa, Torre de Cerredo',
      bbox: RegionBbox(minLat: 42.8, minLon: -6.0, maxLat: 43.7, maxLon: -3.2),
    ),
    StateRegion(
      name: 'Castilla y León',
      description: 'Sierra de Gredos, Picos south',
      bbox: RegionBbox(minLat: 40.0, minLon: -6.5, maxLat: 43.2, maxLon: -1.8),
    ),
    StateRegion(
      name: 'Canary Islands',
      description: 'Teide, Roque de los Muchachos',
      bbox: RegionBbox(minLat: 27.6, minLon: -18.2, maxLat: 29.5, maxLon: -13.3),
    ),
  ],
);

// =======================================================================
//  United Kingdom
// =======================================================================

const _unitedKingdom = Country(
  name: 'United Kingdom',
  code: 'GB',
  emoji: '\u{1F1EC}\u{1F1E7}',
  states: [
    StateRegion(
      name: 'Scottish Highlands',
      description: 'Ben Nevis, Cairngorms, Munros',
      bbox: RegionBbox(minLat: 56.0, minLon: -6.5, maxLat: 58.7, maxLon: -3.0),
    ),
    StateRegion(
      name: 'Scottish Southern Uplands',
      description: 'Merrick, Broad Law, Southern Munros',
      bbox: RegionBbox(minLat: 54.9, minLon: -5.5, maxLat: 56.3, maxLon: -2.0),
    ),
    StateRegion(
      name: 'Lake District',
      description: 'Scafell Pike, Helvellyn, Wainwrights',
      bbox: RegionBbox(minLat: 54.2, minLon: -3.5, maxLat: 54.7, maxLon: -2.7),
    ),
    StateRegion(
      name: 'Wales / Snowdonia',
      description: 'Snowdon, Cadair Idris, Brecon Beacons',
      bbox: RegionBbox(minLat: 51.4, minLon: -5.3, maxLat: 53.5, maxLon: -2.6),
    ),
    StateRegion(
      name: 'Peak District & Pennines',
      description: 'Kinder Scout, Cross Fell, Peak District',
      bbox: RegionBbox(minLat: 52.9, minLon: -2.5, maxLat: 55.0, maxLon: -1.4),
    ),
    StateRegion(
      name: 'Northern Ireland',
      description: 'Mourne Mountains, Slieve Donard',
      bbox: RegionBbox(minLat: 54.0, minLon: -8.2, maxLat: 55.4, maxLon: -5.4),
    ),
  ],
);

// =======================================================================
//  Norway
// =======================================================================

const _norway = Country(
  name: 'Norway',
  code: 'NO',
  emoji: '\u{1F1F3}\u{1F1F4}',
  states: [
    StateRegion(
      name: 'Jotunheimen',
      description: 'Galdhøpiggen, Glittertind — highest in N. Europe',
      bbox: RegionBbox(minLat: 61.2, minLon: 7.5, maxLat: 61.9, maxLon: 9.0),
    ),
    StateRegion(
      name: 'Rondane & Dovrefjell',
      description: 'Snøhetta, Rondslottet, muskox country',
      bbox: RegionBbox(minLat: 61.5, minLon: 9.0, maxLat: 62.5, maxLon: 10.5),
    ),
    StateRegion(
      name: 'Lofoten & Northern Norway',
      description: 'Arctic peaks, midnight sun mountains',
      bbox: RegionBbox(minLat: 67.5, minLon: 13.0, maxLat: 69.5, maxLon: 17.0),
    ),
    StateRegion(
      name: 'Hardangervidda & Fjords',
      description: 'Trolltunga, Hardanger plateau',
      bbox: RegionBbox(minLat: 59.5, minLon: 5.5, maxLat: 61.0, maxLon: 8.5),
    ),
    StateRegion(
      name: 'Romsdal & Sunnmøre',
      description: 'Romsdalshorn, Trollveggen, Sunnmøre Alps',
      bbox: RegionBbox(minLat: 62.0, minLon: 6.0, maxLat: 62.8, maxLon: 8.0),
    ),
  ],
);

// =======================================================================
//  Canada
// =======================================================================

const _canada = Country(
  name: 'Canada',
  code: 'CA',
  emoji: '\u{1F1E8}\u{1F1E6}',
  states: [
    StateRegion(
      name: 'British Columbia',
      description: 'Coast Range, Rockies west, Mt. Robson',
      bbox: RegionBbox(minLat: 48.3, minLon: -139.1, maxLat: 60.0, maxLon: -114.0),
    ),
    StateRegion(
      name: 'Alberta',
      description: 'Canadian Rockies, Banff, Jasper, Columbia Icefield',
      bbox: RegionBbox(minLat: 49.0, minLon: -120.0, maxLat: 60.0, maxLon: -110.0),
    ),
    StateRegion(
      name: 'Yukon',
      description: 'Mt. Logan, St. Elias Range, Kluane',
      bbox: RegionBbox(minLat: 60.0, minLon: -141.0, maxLat: 69.7, maxLon: -124.0),
    ),
    StateRegion(
      name: 'Quebec (Laurentians & Gaspésie)',
      description: 'Mont Jacques-Cartier, Chic-Chocs',
      bbox: RegionBbox(minLat: 45.0, minLon: -79.8, maxLat: 49.5, maxLon: -64.0),
    ),
  ],
);

// =======================================================================
//  Japan
// =======================================================================

const _japan = Country(
  name: 'Japan',
  code: 'JP',
  emoji: '\u{1F1EF}\u{1F1F5}',
  states: [
    StateRegion(
      name: 'Japanese Alps (Chūbu)',
      description: 'Mt. Hotaka, Mt. Yari, Kamikōchi',
      bbox: RegionBbox(minLat: 35.5, minLon: 137.0, maxLat: 37.0, maxLon: 138.5),
    ),
    StateRegion(
      name: 'Mt. Fuji Region',
      description: 'Fuji-san, Tanzawa, Hakone',
      bbox: RegionBbox(minLat: 35.0, minLon: 138.3, maxLat: 35.8, maxLon: 139.3),
    ),
    StateRegion(
      name: 'Hokkaido',
      description: 'Daisetsuzan, Mt. Asahi, Mt. Yōtei',
      bbox: RegionBbox(minLat: 41.3, minLon: 139.3, maxLat: 45.6, maxLon: 145.8),
    ),
    StateRegion(
      name: 'Tōhoku',
      description: 'Gassan, Zaō, Iwaki, Hayachine',
      bbox: RegionBbox(minLat: 37.0, minLon: 139.0, maxLat: 41.5, maxLon: 142.1),
    ),
  ],
);

// =======================================================================
//  New Zealand
// =======================================================================

const _newZealand = Country(
  name: 'New Zealand',
  code: 'NZ',
  emoji: '\u{1F1F3}\u{1F1FF}',
  states: [
    StateRegion(
      name: 'Southern Alps',
      description: 'Aoraki/Mt. Cook, Mt. Tasman, Fox Glacier',
      bbox: RegionBbox(minLat: -44.5, minLon: 168.0, maxLat: -42.5, maxLon: 171.5),
    ),
    StateRegion(
      name: 'Fiordland',
      description: 'Milford Sound, Darran Mountains',
      bbox: RegionBbox(minLat: -46.5, minLon: 166.0, maxLat: -44.5, maxLon: 168.5),
    ),
    StateRegion(
      name: 'North Island Volcanoes',
      description: 'Tongariro, Ruapehu, Taranaki',
      bbox: RegionBbox(minLat: -39.7, minLon: 174.8, maxLat: -38.5, maxLon: 176.3),
    ),
  ],
);

// =======================================================================
//  Nepal
// =======================================================================

const _nepal = Country(
  name: 'Nepal',
  code: 'NP',
  emoji: '\u{1F1F3}\u{1F1F5}',
  states: [
    StateRegion(
      name: 'Everest / Khumbu',
      description: 'Sagarmatha, Lhotse, Nuptse, Cho Oyu',
      bbox: RegionBbox(minLat: 27.5, minLon: 86.3, maxLat: 28.2, maxLon: 87.2),
    ),
    StateRegion(
      name: 'Annapurna',
      description: 'Annapurna Circuit, Machhapuchhre, Dhaulagiri',
      bbox: RegionBbox(minLat: 28.2, minLon: 83.0, maxLat: 29.0, maxLon: 84.5),
    ),
    StateRegion(
      name: 'Langtang & Ganesh',
      description: 'Langtang Lirung, Ganesh Himal',
      bbox: RegionBbox(minLat: 27.9, minLon: 85.0, maxLat: 28.7, maxLon: 86.0),
    ),
    StateRegion(
      name: 'Kangchenjunga',
      description: 'Third-highest peak, eastern Nepal',
      bbox: RegionBbox(minLat: 27.2, minLon: 87.5, maxLat: 27.9, maxLon: 88.2),
    ),
  ],
);

// =======================================================================
//  Chile
// =======================================================================

const _chile = Country(
  name: 'Chile',
  code: 'CL',
  emoji: '\u{1F1E8}\u{1F1F1}',
  states: [
    StateRegion(
      name: 'Central Andes',
      description: 'Aconcagua region (from Chile side), Maipo',
      bbox: RegionBbox(minLat: -34.5, minLon: -71.0, maxLat: -32.0, maxLon: -69.5),
    ),
    StateRegion(
      name: 'Lake District',
      description: 'Osorno, Calbuco, Villarrica volcanoes',
      bbox: RegionBbox(minLat: -42.0, minLon: -72.5, maxLat: -38.5, maxLon: -71.0),
    ),
    StateRegion(
      name: 'Patagonia',
      description: 'Torres del Paine, Darwin Range',
      bbox: RegionBbox(minLat: -55.0, minLon: -75.5, maxLat: -48.0, maxLon: -70.0),
    ),
    StateRegion(
      name: 'Atacama Volcanoes',
      description: 'Ojos del Salado, Llullaillaco',
      bbox: RegionBbox(minLat: -28.0, minLon: -70.0, maxLat: -22.0, maxLon: -67.5),
    ),
  ],
);

// =======================================================================
//  Argentina
// =======================================================================

const _argentina = Country(
  name: 'Argentina',
  code: 'AR',
  emoji: '\u{1F1E6}\u{1F1F7}',
  states: [
    StateRegion(
      name: 'Mendoza',
      description: 'Aconcagua (6,961m), highest in Americas',
      bbox: RegionBbox(minLat: -35.5, minLon: -70.5, maxLat: -32.0, maxLon: -67.0),
    ),
    StateRegion(
      name: 'Patagonia (Fitz Roy)',
      description: 'Monte Fitz Roy, Cerro Torre, El Chaltén',
      bbox: RegionBbox(minLat: -50.5, minLon: -73.5, maxLat: -48.5, maxLon: -71.0),
    ),
    StateRegion(
      name: 'Tierra del Fuego',
      description: 'Martial Mountains, Ushuaia peaks',
      bbox: RegionBbox(minLat: -55.0, minLon: -69.5, maxLat: -53.5, maxLon: -65.0),
    ),
    StateRegion(
      name: 'Northwest (Puna)',
      description: 'Llullaillaco, high Andean desert',
      bbox: RegionBbox(minLat: -27.0, minLon: -68.5, maxLat: -22.0, maxLon: -65.0),
    ),
  ],
);

// =======================================================================
//  Peru
// =======================================================================

const _peru = Country(
  name: 'Peru',
  code: 'PE',
  emoji: '\u{1F1F5}\u{1F1EA}',
  states: [
    StateRegion(
      name: 'Cordillera Blanca',
      description: 'Huascarán (6,768m), Alpamayo',
      bbox: RegionBbox(minLat: -9.8, minLon: -78.0, maxLat: -8.5, maxLon: -77.0),
    ),
    StateRegion(
      name: 'Cordillera Huayhuash',
      description: 'Yerupajá, one of Peru\'s great treks',
      bbox: RegionBbox(minLat: -10.5, minLon: -77.2, maxLat: -10.0, maxLon: -76.6),
    ),
    StateRegion(
      name: 'Cusco & Vilcabamba',
      description: 'Salkantay, Ausangate, Inca trails',
      bbox: RegionBbox(minLat: -14.0, minLon: -73.0, maxLat: -12.8, maxLon: -71.0),
    ),
    StateRegion(
      name: 'Arequipa & Volcanoes',
      description: 'El Misti, Chachani, Coropuna',
      bbox: RegionBbox(minLat: -16.5, minLon: -73.0, maxLat: -15.0, maxLon: -71.0),
    ),
  ],
);

// =======================================================================
//  Mexico
// =======================================================================

const _mexico = Country(
  name: 'Mexico',
  code: 'MX',
  emoji: '\u{1F1F2}\u{1F1FD}',
  states: [
    StateRegion(
      name: 'Trans-Mexican Volcanic Belt',
      description: 'Pico de Orizaba, Popocatépetl, Iztaccíhuatl',
      bbox: RegionBbox(minLat: 18.5, minLon: -100.0, maxLat: 20.0, maxLon: -96.5),
    ),
    StateRegion(
      name: 'Sierra Madre Occidental',
      description: 'Copper Canyon, Barranca del Cobre',
      bbox: RegionBbox(minLat: 23.0, minLon: -108.5, maxLat: 29.0, maxLon: -104.0),
    ),
    StateRegion(
      name: 'Sierra Norte de Puebla',
      description: 'Cofre de Perote, Sierra Negra',
      bbox: RegionBbox(minLat: 19.2, minLon: -98.0, maxLat: 20.5, maxLon: -96.5),
    ),
  ],
);

// =======================================================================
//  India
// =======================================================================

const _india = Country(
  name: 'India',
  code: 'IN',
  emoji: '\u{1F1EE}\u{1F1F3}',
  states: [
    StateRegion(
      name: 'Himachal Pradesh',
      description: 'Kullu, Spiti, Kinnaur — accessible Himalayas',
      bbox: RegionBbox(minLat: 30.3, minLon: 75.5, maxLat: 33.3, maxLon: 79.0),
    ),
    StateRegion(
      name: 'Uttarakhand',
      description: 'Nanda Devi, Valley of Flowers, Gangotri',
      bbox: RegionBbox(minLat: 28.7, minLon: 77.5, maxLat: 31.5, maxLon: 81.0),
    ),
    StateRegion(
      name: 'Ladakh',
      description: 'Stok Kangri, Karakoram south, Zanskar',
      bbox: RegionBbox(minLat: 32.0, minLon: 75.5, maxLat: 36.0, maxLon: 78.5),
    ),
    StateRegion(
      name: 'Sikkim',
      description: 'Kangchenjunga south, Goechala trek',
      bbox: RegionBbox(minLat: 27.0, minLon: 88.0, maxLat: 28.2, maxLon: 89.0),
    ),
  ],
);
