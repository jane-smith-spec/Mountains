#!/usr/bin/env python3
"""Tests for prepare_dem_tiles.py — DEM tile preparation pipeline."""

import os
import sqlite3
import struct
import tempfile
import unittest
from pathlib import Path

from prepare_dem_tiles import (
    FULL_GRID_SIZE,
    RESOLUTIONS,
    TileCoord,
    _parse_hgt_filename,
    cmd_convert,
    cmd_pack,
)


class TestTileCoord(unittest.TestCase):
    """Test tile coordinate naming and enumeration."""

    def test_hgt_filename_north_east(self):
        tile = TileCoord(lat=46, lon=7)
        self.assertEqual(tile.hgt_filename, "N46E007.hgt")

    def test_hgt_filename_south_west(self):
        tile = TileCoord(lat=-12, lon=-77)
        self.assertEqual(tile.hgt_filename, "S12W077.hgt")

    def test_hgt_filename_zero(self):
        tile = TileCoord(lat=0, lon=0)
        self.assertEqual(tile.hgt_filename, "N00E000.hgt")

    def test_copernicus_name(self):
        tile = TileCoord(lat=46, lon=7)
        name = tile.copernicus_name
        self.assertIn("N46", name)
        self.assertIn("E007", name)
        self.assertIn("DEM", name)

    def test_tiles_in_bbox(self):
        tiles = TileCoord.tiles_in_bbox(45.5, 6.5, 47.0, 8.0)

        # Should cover lat 45–47, lon 6–8
        expected_count = 3 * 3  # 3 lat steps × 3 lon steps
        self.assertEqual(len(tiles), expected_count)

        # Check that corners are present
        lats = {t.lat for t in tiles}
        lons = {t.lon for t in tiles}
        self.assertIn(45, lats)
        self.assertIn(47, lats)
        self.assertIn(6, lons)
        self.assertIn(8, lons)

    def test_tiles_in_bbox_single_tile(self):
        tiles = TileCoord.tiles_in_bbox(46.2, 7.3, 46.8, 7.9)
        self.assertEqual(len(tiles), 1)
        self.assertEqual(tiles[0].lat, 46)
        self.assertEqual(tiles[0].lon, 7)


class TestParseHgtFilename(unittest.TestCase):
    """Test filename → TileCoord parsing."""

    def test_north_east(self):
        tile = _parse_hgt_filename("N46E007.hgt")
        self.assertIsNotNone(tile)
        self.assertEqual(tile.lat, 46)
        self.assertEqual(tile.lon, 7)

    def test_south_west(self):
        tile = _parse_hgt_filename("S12W077.hgt")
        self.assertIsNotNone(tile)
        self.assertEqual(tile.lat, -12)
        self.assertEqual(tile.lon, -77)

    def test_invalid_filename(self):
        self.assertIsNone(_parse_hgt_filename("invalid.hgt"))
        self.assertIsNone(_parse_hgt_filename("N46E07.hgt"))
        self.assertIsNone(_parse_hgt_filename("readme.txt"))


class TestConvert(unittest.TestCase):
    """Test the tile downsampling conversion."""

    def _create_fake_tile(self, directory: Path, filename: str, grid_size: int):
        """Create a fake .hgt tile with sequential elevation values."""
        path = directory / filename
        # Write big-endian Int16 data
        data = bytearray()
        for i in range(grid_size * grid_size):
            # Elevation cycles through 0–1000
            elev = i % 1000
            data.extend(struct.pack(">h", elev))
        path.write_bytes(bytes(data))
        return path

    def test_downsample_creates_medium_and_low(self):
        """Test that convert creates medium and low resolution tiles."""
        try:
            import numpy as np
        except ImportError:
            self.skipTest("numpy not installed")

        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir = Path(tmpdir)

            # Create a small fake full-resolution tile
            # Use actual FULL_GRID_SIZE for realistic test
            full_dir = tmpdir / "full"
            full_dir.mkdir()

            # Create a smaller test tile (using actual grid size is too slow
            # for tests, so we'll test the logic with the real function
            # but check that output files are created)
            self._create_fake_tile(full_dir, "N46E007.hgt", FULL_GRID_SIZE)

            # Run conversion
            import argparse
            args = argparse.Namespace(
                input=str(full_dir),
                output=str(tmpdir),
            )
            cmd_convert(args)

            # Check that medium and low directories were created
            medium_file = tmpdir / "medium" / "N46E007.hgt"
            low_file = tmpdir / "low" / "N46E007.hgt"

            self.assertTrue(medium_file.exists(), "Medium tile should be created")
            self.assertTrue(low_file.exists(), "Low tile should be created")

            # Check sizes
            medium_expected = RESOLUTIONS["medium"] ** 2 * 2
            low_expected = RESOLUTIONS["low"] ** 2 * 2

            self.assertEqual(medium_file.stat().st_size, medium_expected)
            self.assertEqual(low_file.stat().st_size, low_expected)


class TestPack(unittest.TestCase):
    """Test packing tiles into SQLite."""

    def _create_fake_tile(self, directory: Path, filename: str, size_bytes: int):
        path = directory / filename
        path.write_bytes(b"\x00" * size_bytes)
        return path

    def test_pack_creates_database(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir = Path(tmpdir)

            # Create fake multi-resolution structure
            for res_name, grid_size in RESOLUTIONS.items():
                res_dir = tmpdir / res_name
                res_dir.mkdir()
                tile_bytes = grid_size * grid_size * 2
                self._create_fake_tile(res_dir, "N46E007.hgt", tile_bytes)
                self._create_fake_tile(res_dir, "N46E008.hgt", tile_bytes)

            db_path = str(tmpdir / "test.db")

            import argparse
            args = argparse.Namespace(
                input=str(tmpdir),
                output=db_path,
            )
            cmd_pack(args)

            # Verify database
            self.assertTrue(os.path.exists(db_path))

            conn = sqlite3.connect(db_path)
            conn.row_factory = sqlite3.Row

            # Check tile count (2 tiles × 3 resolutions = 6)
            count = conn.execute("SELECT COUNT(*) FROM tiles").fetchone()[0]
            self.assertEqual(count, 6)

            # Check metadata
            version = conn.execute(
                "SELECT value FROM metadata WHERE key='format_version'"
            ).fetchone()[0]
            self.assertEqual(version, "1")

            # Check a specific tile
            row = conn.execute(
                "SELECT * FROM tiles WHERE filename='N46E007.hgt' "
                "AND resolution='full'"
            ).fetchone()
            self.assertIsNotNone(row)
            self.assertEqual(row["lat_sw"], 46)
            self.assertEqual(row["lon_sw"], 7)
            self.assertEqual(row["grid_size"], FULL_GRID_SIZE)

            conn.close()

    def test_pack_empty_directory(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = os.path.join(tmpdir, "empty.db")

            import argparse
            args = argparse.Namespace(
                input=tmpdir,
                output=db_path,
            )
            cmd_pack(args)

            # Should create a valid (empty) database
            conn = sqlite3.connect(db_path)
            count = conn.execute("SELECT COUNT(*) FROM tiles").fetchone()[0]
            self.assertEqual(count, 0)
            conn.close()


class TestResolutions(unittest.TestCase):
    """Test that resolution constants are consistent."""

    def test_full_resolution(self):
        self.assertEqual(RESOLUTIONS["full"], 3601)

    def test_medium_resolution(self):
        self.assertEqual(RESOLUTIONS["medium"], 1201)

    def test_low_resolution(self):
        self.assertEqual(RESOLUTIONS["low"], 401)

    def test_grid_sizes_are_odd(self):
        """Grid sizes should be odd (includes both edges of the 1° tile)."""
        for name, size in RESOLUTIONS.items():
            self.assertEqual(size % 2, 1, f"{name} grid size {size} should be odd")

    def test_grid_sizes_divide_3600(self):
        """Each resolution should evenly sample the 1° range.
        3600 / (gridSize - 1) should be an integer."""
        for name, size in RESOLUTIONS.items():
            step = 3600 / (size - 1)
            self.assertAlmostEqual(
                step, round(step), places=6,
                msg=f"{name}: 3600/{size-1} = {step} should be integer",
            )


if __name__ == "__main__":
    unittest.main()
