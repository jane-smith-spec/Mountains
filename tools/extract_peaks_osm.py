#!/usr/bin/env python3
"""
extract_peaks_osm.py — Extract mountain peaks and landmarks from OpenStreetMap.

Reads an OSM PBF or XML extract and produces a SQLite database matching
the schema expected by PeakLine's PeakRepository:

    peaks(id, name, lat, lon, elevation_m, prominence_m)
    landmarks(id, name, lat, lon, elevation_m, category)

Usage:
    # From a PBF extract (e.g., from download.geofabrik.de):
    python extract_peaks_osm.py alps-latest.osm.pbf -o peaks.db

    # From an OSM XML file:
    python extract_peaks_osm.py switzerland.osm -o peaks.db

    # Filter to a bounding box:
    python extract_peaks_osm.py alps-latest.osm.pbf -o peaks.db \
        --bbox 45.5,5.5,48.0,11.0

    # Include landmarks (huts, lakes, passes):
    python extract_peaks_osm.py alps-latest.osm.pbf -o peaks.db --landmarks

Dependencies:
    pip install osmium   # For PBF files (fast C++ parser)
    # OR: no dependencies needed for XML files (uses stdlib xml.etree)

The output database can be placed in the Flutter app's assets directory
or loaded at runtime by PeakRepository.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sqlite3
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)

# -----------------------------------------------------------------------
#  Data models
# -----------------------------------------------------------------------

@dataclass
class PeakRecord:
    osm_id: int
    name: str
    lat: float
    lon: float
    elevation_m: float
    prominence_m: float | None = None


@dataclass
class LandmarkRecord:
    osm_id: int
    name: str
    lat: float
    lon: float
    elevation_m: float
    category: str  # hut, lake, pass, glacier, town, other


# OSM tags → our landmark categories
LANDMARK_TAG_MAP: dict[str, str] = {
    # Mountain huts and shelters
    "alpine_hut": "hut",
    "wilderness_hut": "hut",
    "shelter": "hut",
    # Mountain passes
    "saddle": "pass",
    "mountain_pass": "pass",
    # Lakes
    "water": "lake",
    "lake": "lake",
    # Glaciers
    "glacier": "glacier",
    # Towns and villages
    "village": "town",
    "town": "town",
    "city": "town",
    "hamlet": "town",
}

# -----------------------------------------------------------------------
#  PBF parser (using osmium)
# -----------------------------------------------------------------------

def _parse_pbf(
    filepath: str,
    bbox: tuple[float, float, float, float] | None,
    include_landmarks: bool,
) -> tuple[list[PeakRecord], list[LandmarkRecord]]:
    """Parse a PBF file using the osmium library."""
    try:
        import osmium  # type: ignore
    except ImportError:
        log.error(
            "The 'osmium' package is required for PBF files.\n"
            "Install it with: pip install osmium"
        )
        sys.exit(1)

    peaks: list[PeakRecord] = []
    landmarks: list[LandmarkRecord] = []

    class PeakHandler(osmium.SimpleHandler):
        def node(self, n):
            tags = {t.k: t.v for t in n.tags}

            # Bounding box filter
            if bbox:
                min_lat, min_lon, max_lat, max_lon = bbox
                if not (min_lat <= n.location.lat <= max_lat and
                        min_lon <= n.location.lon <= max_lon):
                    return

            # Check for peaks
            natural = tags.get("natural", "")
            if natural == "peak":
                name = tags.get("name", "")
                if not name:
                    return  # Skip unnamed peaks

                ele_str = tags.get("ele", "")
                elevation = _parse_elevation(ele_str)
                if elevation is None:
                    return  # Skip peaks without elevation data

                prominence = None
                prom_str = tags.get("prominence", "")
                if prom_str:
                    prominence = _parse_elevation(prom_str)

                peaks.append(PeakRecord(
                    osm_id=n.id,
                    name=name,
                    lat=n.location.lat,
                    lon=n.location.lon,
                    elevation_m=elevation,
                    prominence_m=prominence,
                ))

            # Check for landmarks
            if include_landmarks:
                _check_landmark(tags, n.id, n.location.lat, n.location.lon, landmarks)

    handler = PeakHandler()
    handler.apply_file(filepath, locations=True)

    return peaks, landmarks


# -----------------------------------------------------------------------
#  XML parser (stdlib, no dependencies)
# -----------------------------------------------------------------------

def _parse_xml(
    filepath: str,
    bbox: tuple[float, float, float, float] | None,
    include_landmarks: bool,
) -> tuple[list[PeakRecord], list[LandmarkRecord]]:
    """Parse an OSM XML file using iterative parsing (memory-efficient)."""
    peaks: list[PeakRecord] = []
    landmarks: list[LandmarkRecord] = []

    log.info("Parsing XML file (this may take a while for large files)...")

    # Iterative parsing to handle large files
    context = ET.iterparse(filepath, events=("end",))

    for event, elem in context:
        if elem.tag != "node":
            continue

        lat_str = elem.get("lat")
        lon_str = elem.get("lon")
        osm_id_str = elem.get("id")

        if not (lat_str and lon_str and osm_id_str):
            elem.clear()
            continue

        lat = float(lat_str)
        lon = float(lon_str)
        osm_id = int(osm_id_str)

        # Bounding box filter
        if bbox:
            min_lat, min_lon, max_lat, max_lon = bbox
            if not (min_lat <= lat <= max_lat and min_lon <= lon <= max_lon):
                elem.clear()
                continue

        # Read tags
        tags: dict[str, str] = {}
        for tag_elem in elem.findall("tag"):
            k = tag_elem.get("k", "")
            v = tag_elem.get("v", "")
            if k:
                tags[k] = v

        # Check for peaks
        if tags.get("natural") == "peak":
            name = tags.get("name", "")
            if name:
                elevation = _parse_elevation(tags.get("ele", ""))
                if elevation is not None:
                    prominence = _parse_elevation(tags.get("prominence", ""))
                    peaks.append(PeakRecord(
                        osm_id=osm_id,
                        name=name,
                        lat=lat,
                        lon=lon,
                        elevation_m=elevation,
                        prominence_m=prominence,
                    ))

        # Check for landmarks
        if include_landmarks:
            _check_landmark(tags, osm_id, lat, lon, landmarks)

        # Free memory
        elem.clear()

    return peaks, landmarks


# -----------------------------------------------------------------------
#  Shared helpers
# -----------------------------------------------------------------------

def _parse_elevation(ele_str: str) -> float | None:
    """Parse an elevation string, handling common formats.

    OSM elevation tags are messy. Common formats:
        "4478"          → 4478.0
        "4478 m"        → 4478.0
        "4,478"         → 4478.0
        "14,692 ft"     → 4478.0 (converted)
        "4478.5"        → 4478.5
        ""              → None
    """
    if not ele_str or not ele_str.strip():
        return None

    s = ele_str.strip().lower()

    # Check for feet
    is_feet = False
    if "ft" in s or "feet" in s:
        is_feet = True
        s = s.replace("ft", "").replace("feet", "").strip()

    # Remove "m" suffix
    s = s.replace("m", "").strip()

    # Remove commas (thousand separators)
    s = s.replace(",", "")

    # Remove anything after semicolon (multiple values)
    if ";" in s:
        s = s.split(";")[0].strip()

    try:
        value = float(s)
        if is_feet:
            value *= 0.3048  # feet to meters
        return value
    except ValueError:
        return None


def _check_landmark(
    tags: dict[str, str],
    osm_id: int,
    lat: float,
    lon: float,
    landmarks: list[LandmarkRecord],
) -> None:
    """Check if a node's tags match any landmark category."""
    name = tags.get("name", "")
    if not name:
        return

    category = None

    # Check tourism tag (huts, shelters)
    tourism = tags.get("tourism", "")
    if tourism in LANDMARK_TAG_MAP:
        category = LANDMARK_TAG_MAP[tourism]

    # Check natural tag (saddles, glaciers, water)
    natural = tags.get("natural", "")
    if natural in LANDMARK_TAG_MAP:
        category = LANDMARK_TAG_MAP[natural]

    # Check place tag (towns, villages)
    place = tags.get("place", "")
    if place in LANDMARK_TAG_MAP:
        category = LANDMARK_TAG_MAP[place]

    # Check mountain_pass tag
    if tags.get("mountain_pass") == "yes":
        category = "pass"

    if category is None:
        return

    # Get elevation (optional for landmarks)
    elevation = _parse_elevation(tags.get("ele", ""))
    if elevation is None:
        elevation = 0.0  # Unknown elevation

    landmarks.append(LandmarkRecord(
        osm_id=osm_id,
        name=name,
        lat=lat,
        lon=lon,
        elevation_m=elevation,
        category=category,
    ))


# -----------------------------------------------------------------------
#  SQLite writer
# -----------------------------------------------------------------------

def _write_database(
    db_path: str,
    peaks: list[PeakRecord],
    landmarks: list[LandmarkRecord],
) -> None:
    """Write peaks and landmarks to a SQLite database."""
    # Remove existing database if present
    if os.path.exists(db_path):
        os.remove(db_path)

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Create schema (matches PeakRepository expectations)
    cursor.execute("""
        CREATE TABLE peaks (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            lat REAL NOT NULL,
            lon REAL NOT NULL,
            elevation_m REAL NOT NULL,
            prominence_m REAL
        )
    """)

    cursor.execute("""
        CREATE TABLE landmarks (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            lat REAL NOT NULL,
            lon REAL NOT NULL,
            elevation_m REAL NOT NULL,
            category TEXT NOT NULL
        )
    """)

    # Create spatial indexes
    cursor.execute("CREATE INDEX idx_peaks_lat ON peaks(lat)")
    cursor.execute("CREATE INDEX idx_peaks_lon ON peaks(lon)")
    cursor.execute("CREATE INDEX idx_landmarks_lat ON landmarks(lat)")
    cursor.execute("CREATE INDEX idx_landmarks_lon ON landmarks(lon)")

    # Insert peaks
    cursor.executemany(
        "INSERT INTO peaks (id, name, lat, lon, elevation_m, prominence_m) "
        "VALUES (?, ?, ?, ?, ?, ?)",
        [
            (p.osm_id, p.name, p.lat, p.lon, p.elevation_m, p.prominence_m)
            for p in peaks
        ],
    )

    # Insert landmarks
    if landmarks:
        cursor.executemany(
            "INSERT INTO landmarks (id, name, lat, lon, elevation_m, category) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            [
                (lm.osm_id, lm.name, lm.lat, lm.lon, lm.elevation_m, lm.category)
                for lm in landmarks
            ],
        )

    conn.commit()

    # Report stats
    cursor.execute("SELECT COUNT(*) FROM peaks")
    peak_count = cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(*) FROM landmarks")
    landmark_count = cursor.fetchone()[0]

    conn.close()

    file_size_kb = os.path.getsize(db_path) / 1024
    log.info(
        f"Database written: {db_path}\n"
        f"  Peaks:     {peak_count:,}\n"
        f"  Landmarks: {landmark_count:,}\n"
        f"  File size: {file_size_kb:,.1f} KB"
    )


# -----------------------------------------------------------------------
#  CLI entry point
# -----------------------------------------------------------------------

def _parse_bbox(s: str) -> tuple[float, float, float, float]:
    """Parse a bounding box string: 'min_lat,min_lon,max_lat,max_lon'."""
    parts = [float(x.strip()) for x in s.split(",")]
    if len(parts) != 4:
        raise argparse.ArgumentTypeError(
            "Bounding box must be: min_lat,min_lon,max_lat,max_lon"
        )
    return (parts[0], parts[1], parts[2], parts[3])


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract mountain peaks and landmarks from OSM data.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s alps-latest.osm.pbf -o peaks.db
  %(prog)s switzerland.osm -o peaks.db --bbox 45.5,5.5,48.0,11.0
  %(prog)s alps-latest.osm.pbf -o peaks.db --landmarks
        """,
    )
    parser.add_argument(
        "input",
        help="Input OSM file (.osm XML or .osm.pbf)",
    )
    parser.add_argument(
        "-o", "--output",
        default="peaks.db",
        help="Output SQLite database path (default: peaks.db)",
    )
    parser.add_argument(
        "--bbox",
        type=_parse_bbox,
        help="Bounding box filter: min_lat,min_lon,max_lat,max_lon",
    )
    parser.add_argument(
        "--landmarks",
        action="store_true",
        help="Also extract landmarks (huts, lakes, passes, etc.)",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Verbose output",
    )

    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    input_path = args.input
    if not os.path.exists(input_path):
        log.error(f"Input file not found: {input_path}")
        sys.exit(1)

    # Choose parser based on file extension
    if input_path.endswith(".pbf"):
        log.info(f"Parsing PBF file: {input_path}")
        peaks, landmarks = _parse_pbf(input_path, args.bbox, args.landmarks)
    elif input_path.endswith(".osm") or input_path.endswith(".xml"):
        log.info(f"Parsing XML file: {input_path}")
        peaks, landmarks = _parse_xml(input_path, args.bbox, args.landmarks)
    else:
        log.error(
            f"Unsupported file format: {input_path}\n"
            "Expected .osm.pbf or .osm/.xml"
        )
        sys.exit(1)

    log.info(f"Found {len(peaks):,} peaks, {len(landmarks):,} landmarks")

    # Deduplicate by OSM ID
    seen_ids: set[int] = set()
    unique_peaks = []
    for p in peaks:
        if p.osm_id not in seen_ids:
            seen_ids.add(p.osm_id)
            unique_peaks.append(p)

    if len(unique_peaks) < len(peaks):
        log.info(f"Deduplicated: {len(peaks)} → {len(unique_peaks)} peaks")
        peaks = unique_peaks

    # Write database
    _write_database(args.output, peaks, landmarks)


if __name__ == "__main__":
    main()
