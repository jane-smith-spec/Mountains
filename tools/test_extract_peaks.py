#!/usr/bin/env python3
"""Tests for extract_peaks_osm.py — peak/landmark extraction from OSM."""

import os
import sqlite3
import tempfile
import textwrap
import unittest
from pathlib import Path

# Import the module under test
from extract_peaks_osm import (
    LandmarkRecord,
    PeakRecord,
    _check_landmark,
    _parse_bbox,
    _parse_elevation,
    _parse_xml,
    _write_database,
)


class TestParseElevation(unittest.TestCase):
    """Test the elevation string parser."""

    def test_simple_integer(self):
        self.assertEqual(_parse_elevation("4478"), 4478.0)

    def test_decimal(self):
        self.assertAlmostEqual(_parse_elevation("4478.5"), 4478.5)

    def test_with_m_suffix(self):
        self.assertEqual(_parse_elevation("4478 m"), 4478.0)

    def test_with_commas(self):
        self.assertEqual(_parse_elevation("4,478"), 4478.0)

    def test_feet_conversion(self):
        result = _parse_elevation("14692 ft")
        self.assertIsNotNone(result)
        self.assertAlmostEqual(result, 14692 * 0.3048, places=0)

    def test_empty_string(self):
        self.assertIsNone(_parse_elevation(""))

    def test_none_like(self):
        self.assertIsNone(_parse_elevation("   "))

    def test_semicolon_multiple_values(self):
        # Some OSM entries have "4478;4480" — take the first
        self.assertEqual(_parse_elevation("4478;4480"), 4478.0)

    def test_garbage(self):
        self.assertIsNone(_parse_elevation("unknown"))

    def test_negative_elevation(self):
        self.assertEqual(_parse_elevation("-10"), -10.0)


class TestCheckLandmark(unittest.TestCase):
    """Test landmark category detection from OSM tags."""

    def test_alpine_hut(self):
        landmarks = []
        tags = {"name": "Hörnli Hut", "tourism": "alpine_hut", "ele": "3260"}
        _check_landmark(tags, 123, 45.97, 7.65, landmarks)
        self.assertEqual(len(landmarks), 1)
        self.assertEqual(landmarks[0].category, "hut")
        self.assertEqual(landmarks[0].name, "Hörnli Hut")

    def test_mountain_pass(self):
        landmarks = []
        tags = {"name": "Col du Galibier", "mountain_pass": "yes", "ele": "2642"}
        _check_landmark(tags, 456, 45.06, 6.40, landmarks)
        self.assertEqual(len(landmarks), 1)
        self.assertEqual(landmarks[0].category, "pass")

    def test_natural_saddle(self):
        landmarks = []
        tags = {"name": "Jungfraujoch", "natural": "saddle", "ele": "3463"}
        _check_landmark(tags, 789, 46.54, 7.98, landmarks)
        self.assertEqual(len(landmarks), 1)
        self.assertEqual(landmarks[0].category, "pass")

    def test_glacier(self):
        landmarks = []
        tags = {"name": "Aletsch Glacier", "natural": "glacier"}
        _check_landmark(tags, 101, 46.45, 8.03, landmarks)
        self.assertEqual(len(landmarks), 1)
        self.assertEqual(landmarks[0].category, "glacier")
        self.assertEqual(landmarks[0].elevation_m, 0.0)  # No ele tag

    def test_town(self):
        landmarks = []
        tags = {"name": "Zermatt", "place": "village", "ele": "1620"}
        _check_landmark(tags, 202, 46.02, 7.75, landmarks)
        self.assertEqual(len(landmarks), 1)
        self.assertEqual(landmarks[0].category, "town")

    def test_unnamed_ignored(self):
        landmarks = []
        tags = {"tourism": "alpine_hut", "ele": "2000"}
        _check_landmark(tags, 303, 46.0, 7.0, landmarks)
        self.assertEqual(len(landmarks), 0)

    def test_unrecognized_tags_ignored(self):
        landmarks = []
        tags = {"name": "Random Shop", "shop": "convenience"}
        _check_landmark(tags, 404, 46.0, 7.0, landmarks)
        self.assertEqual(len(landmarks), 0)


class TestWriteDatabase(unittest.TestCase):
    """Test SQLite database writing."""

    def test_write_peaks_and_landmarks(self):
        peaks = [
            PeakRecord(osm_id=1, name="Matterhorn", lat=45.9763, lon=7.6586,
                       elevation_m=4478, prominence_m=1042),
            PeakRecord(osm_id=2, name="Mont Blanc", lat=45.8326, lon=6.8652,
                       elevation_m=4808, prominence_m=4695),
        ]
        landmarks = [
            LandmarkRecord(osm_id=10, name="Hörnli Hut", lat=45.97, lon=7.65,
                           elevation_m=3260, category="hut"),
        ]

        with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as f:
            db_path = f.name

        try:
            _write_database(db_path, peaks, landmarks)

            # Verify the database contents
            conn = sqlite3.connect(db_path)
            conn.row_factory = sqlite3.Row

            # Check peaks
            rows = conn.execute("SELECT * FROM peaks ORDER BY id").fetchall()
            self.assertEqual(len(rows), 2)
            self.assertEqual(rows[0]["name"], "Matterhorn")
            self.assertAlmostEqual(rows[0]["elevation_m"], 4478)
            self.assertAlmostEqual(rows[0]["prominence_m"], 1042)
            self.assertEqual(rows[1]["name"], "Mont Blanc")

            # Check landmarks
            rows = conn.execute("SELECT * FROM landmarks").fetchall()
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["name"], "Hörnli Hut")
            self.assertEqual(rows[0]["category"], "hut")

            conn.close()
        finally:
            os.unlink(db_path)

    def test_empty_database(self):
        with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as f:
            db_path = f.name

        try:
            _write_database(db_path, [], [])

            conn = sqlite3.connect(db_path)
            peak_count = conn.execute("SELECT COUNT(*) FROM peaks").fetchone()[0]
            lm_count = conn.execute("SELECT COUNT(*) FROM landmarks").fetchone()[0]
            self.assertEqual(peak_count, 0)
            self.assertEqual(lm_count, 0)
            conn.close()
        finally:
            os.unlink(db_path)

    def test_indexes_created(self):
        with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as f:
            db_path = f.name

        try:
            _write_database(db_path, [], [])

            conn = sqlite3.connect(db_path)
            indexes = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='index'"
            ).fetchall()
            index_names = {row[0] for row in indexes}
            self.assertIn("idx_peaks_lat", index_names)
            self.assertIn("idx_peaks_lon", index_names)
            self.assertIn("idx_landmarks_lat", index_names)
            self.assertIn("idx_landmarks_lon", index_names)
            conn.close()
        finally:
            os.unlink(db_path)


class TestXmlParser(unittest.TestCase):
    """Test the XML parser with a small synthetic OSM file."""

    def test_parse_peaks_from_xml(self):
        osm_xml = textwrap.dedent("""\
            <?xml version="1.0" encoding="UTF-8"?>
            <osm version="0.6">
              <node id="1" lat="45.9763" lon="7.6586">
                <tag k="natural" v="peak"/>
                <tag k="name" v="Matterhorn"/>
                <tag k="ele" v="4478"/>
              </node>
              <node id="2" lat="46.5580" lon="7.9912">
                <tag k="natural" v="peak"/>
                <tag k="name" v="Eiger"/>
                <tag k="ele" v="3967"/>
                <tag k="prominence" v="366"/>
              </node>
              <node id="3" lat="46.0200" lon="7.7490">
                <tag k="tourism" v="alpine_hut"/>
                <tag k="name" v="Test Hut"/>
                <tag k="ele" v="2800"/>
              </node>
              <node id="4" lat="46.0" lon="7.0">
                <tag k="natural" v="peak"/>
                <tag k="ele" v="1000"/>
              </node>
            </osm>
        """)

        with tempfile.NamedTemporaryFile(
            suffix=".osm", mode="w", delete=False, encoding="utf-8"
        ) as f:
            f.write(osm_xml)
            xml_path = f.name

        try:
            peaks, landmarks = _parse_xml(xml_path, bbox=None, include_landmarks=True)

            # Should find 2 peaks (node 4 is unnamed → skipped)
            self.assertEqual(len(peaks), 2)
            self.assertEqual(peaks[0].name, "Matterhorn")
            self.assertEqual(peaks[0].elevation_m, 4478.0)
            self.assertEqual(peaks[1].name, "Eiger")
            self.assertAlmostEqual(peaks[1].prominence_m, 366.0)

            # Should find 1 landmark
            self.assertEqual(len(landmarks), 1)
            self.assertEqual(landmarks[0].name, "Test Hut")
            self.assertEqual(landmarks[0].category, "hut")
        finally:
            os.unlink(xml_path)

    def test_bbox_filter(self):
        osm_xml = textwrap.dedent("""\
            <?xml version="1.0" encoding="UTF-8"?>
            <osm version="0.6">
              <node id="1" lat="45.97" lon="7.65">
                <tag k="natural" v="peak"/>
                <tag k="name" v="Inside"/>
                <tag k="ele" v="4000"/>
              </node>
              <node id="2" lat="50.00" lon="10.00">
                <tag k="natural" v="peak"/>
                <tag k="name" v="Outside"/>
                <tag k="ele" v="3000"/>
              </node>
            </osm>
        """)

        with tempfile.NamedTemporaryFile(
            suffix=".osm", mode="w", delete=False, encoding="utf-8"
        ) as f:
            f.write(osm_xml)
            xml_path = f.name

        try:
            peaks, _ = _parse_xml(
                xml_path,
                bbox=(45.0, 7.0, 47.0, 8.0),
                include_landmarks=False,
            )

            self.assertEqual(len(peaks), 1)
            self.assertEqual(peaks[0].name, "Inside")
        finally:
            os.unlink(xml_path)


class TestParseBbox(unittest.TestCase):
    def test_valid_bbox(self):
        result = _parse_bbox("45.5,5.5,48.0,11.0")
        self.assertEqual(result, (45.5, 5.5, 48.0, 11.0))

    def test_invalid_bbox(self):
        with self.assertRaises(Exception):
            _parse_bbox("45.5,5.5")


if __name__ == "__main__":
    unittest.main()
