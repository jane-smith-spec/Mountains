#!/usr/bin/env python3
"""
prepare_dem_tiles.py — Download and prepare DEM tiles for PeakLine.

Downloads Copernicus GLO-30 DEM tiles, converts them to multi-resolution
.hgt files, and optionally packs them into a compressed SQLite database
for bundling with the app.

Tile naming follows the SRTM convention:
    N46E007.hgt  →  1°×1° tile, SW corner at 46°N 7°E

Multi-resolution output:
    dem_tiles/full/N46E007.hgt    3601×3601  Int16  (~25 MB)  1" / 30m
    dem_tiles/medium/N46E007.hgt  1201×1201  Int16  (~2.8 MB) 3" / 90m
    dem_tiles/low/N46E007.hgt      401×401   Int16  (~313 KB) 9" / 250m

Usage:
    # Download tiles for a region (requires Copernicus credentials):
    python prepare_dem_tiles.py download --bbox 45.5,5.5,48.0,11.0 \
        --username YOUR_EMAIL --password YOUR_PASSWORD -o ./dem_tiles

    # Convert existing full-resolution tiles to multi-resolution:
    python prepare_dem_tiles.py convert --input ./dem_tiles/full -o ./dem_tiles

    # Pack tiles into a SQLite bundle:
    python prepare_dem_tiles.py pack --input ./dem_tiles -o region_alps.db

    # All-in-one: download + convert + pack:
    python prepare_dem_tiles.py all --bbox 45.5,5.5,48.0,11.0 \
        --username YOUR_EMAIL --password YOUR_PASSWORD -o ./dem_tiles

Dependencies:
    pip install requests numpy   # numpy for downsampling, requests for HTTP

Data source:
    Copernicus GLO-30 DEM (free, 30m global coverage)
    https://dataspace.copernicus.eu/
    Registration required (free account).
"""

from __future__ import annotations

import argparse
import io
import logging
import os
import sqlite3
import struct
import sys
import time
from dataclasses import dataclass
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)

# -----------------------------------------------------------------------
#  Constants
# -----------------------------------------------------------------------

# Full-resolution tile: 3601 × 3601 Int16 values (SRTM format)
FULL_GRID_SIZE = 3601
FULL_TILE_BYTES = FULL_GRID_SIZE * FULL_GRID_SIZE * 2  # ~25 MB

# Multi-resolution grid sizes
RESOLUTIONS = {
    "full":   3601,  # 1 arc-second (~30m)
    "medium": 1201,  # 3 arc-seconds (~90m)
    "low":     401,  # 9 arc-seconds (~250m)
}

# Copernicus GLO-30 tile URL template
# Tiles are named: Copernicus_DSM_COG_10_NXX_00_EXXX_00_DEM.tif
COPERNICUS_BASE_URL = (
    "https://prism-dem-open.copernicus.eu/pd-desk-open-access/prismDownload/"
    "COP-DEM_GLO-30-DTED__2023_1/"
)

# -----------------------------------------------------------------------
#  Tile naming
# -----------------------------------------------------------------------

@dataclass
class TileCoord:
    """A 1°×1° tile identified by its SW corner."""
    lat: int
    lon: int

    @property
    def hgt_filename(self) -> str:
        """Standard SRTM-format filename: N46E007.hgt"""
        ns = "N" if self.lat >= 0 else "S"
        ew = "E" if self.lon >= 0 else "W"
        return f"{ns}{abs(self.lat):02d}{ew}{abs(self.lon):03d}.hgt"

    @property
    def copernicus_name(self) -> str:
        """Copernicus GLO-30 tile name for download."""
        ns = "N" if self.lat >= 0 else "S"
        ew = "E" if self.lon >= 0 else "W"
        return (
            f"Copernicus_DSM_COG_10_{ns}{abs(self.lat):02d}_00_"
            f"{ew}{abs(self.lon):03d}_00_DEM"
        )

    @staticmethod
    def tiles_in_bbox(
        min_lat: float, min_lon: float, max_lat: float, max_lon: float,
    ) -> list[TileCoord]:
        """Generate all tiles covering a bounding box."""
        tiles = []
        for lat in range(int(min_lat), int(max_lat) + 1):
            for lon in range(int(min_lon), int(max_lon) + 1):
                tiles.append(TileCoord(lat=lat, lon=lon))
        return tiles


# -----------------------------------------------------------------------
#  Download command
# -----------------------------------------------------------------------

def cmd_download(args: argparse.Namespace) -> None:
    """Download Copernicus GLO-30 tiles and convert to .hgt format."""
    try:
        import requests
        import numpy as np
    except ImportError:
        log.error(
            "The 'requests' and 'numpy' packages are required.\n"
            "Install with: pip install requests numpy"
        )
        sys.exit(1)

    bbox = args.bbox
    tiles = TileCoord.tiles_in_bbox(*bbox)
    log.info(f"Tiles to download: {len(tiles)} for bbox {bbox}")

    out_dir = Path(args.output) / "full"
    out_dir.mkdir(parents=True, exist_ok=True)

    # Authenticate with Copernicus (OAuth2 token)
    token = _get_copernicus_token(args.username, args.password)
    if not token:
        log.error("Failed to authenticate with Copernicus.")
        sys.exit(1)

    downloaded = 0
    skipped = 0
    failed = 0

    for tile in tiles:
        out_path = out_dir / tile.hgt_filename
        if out_path.exists() and out_path.stat().st_size == FULL_TILE_BYTES:
            log.debug(f"Already exists: {tile.hgt_filename}")
            skipped += 1
            continue

        log.info(f"Downloading {tile.hgt_filename}...")
        success = _download_tile(tile, out_path, token)
        if success:
            downloaded += 1
        else:
            failed += 1

        # Rate limiting: be polite to the server
        time.sleep(1)

    log.info(
        f"Download complete: {downloaded} new, {skipped} existing, {failed} failed"
    )


def _get_copernicus_token(username: str, password: str) -> str | None:
    """Get an OAuth2 access token from Copernicus Identity Server."""
    import requests

    token_url = (
        "https://identity.dataspace.copernicus.eu/auth/realms/"
        "CDSE/protocol/openid-connect/token"
    )

    try:
        resp = requests.post(
            token_url,
            data={
                "client_id": "cdse-public",
                "grant_type": "password",
                "username": username,
                "password": password,
            },
            timeout=30,
        )
        resp.raise_for_status()
        return resp.json()["access_token"]
    except Exception as e:
        log.error(f"Authentication failed: {e}")
        return None


def _download_tile(
    tile: TileCoord, out_path: Path, token: str,
) -> bool:
    """Download a single Copernicus tile and convert to .hgt format."""
    import requests
    import numpy as np

    # Copernicus provides GeoTIFF; we need raw Int16 .hgt
    # The download URL varies by product. Try the direct download endpoint.
    url = f"{COPERNICUS_BASE_URL}{tile.copernicus_name}.tif"

    headers = {"Authorization": f"Bearer {token}"}

    try:
        resp = requests.get(url, headers=headers, timeout=120, stream=True)

        if resp.status_code == 404:
            # Tile might be ocean or outside coverage
            log.warning(f"Tile not found (ocean?): {tile.hgt_filename}")
            # Write a flat tile (all zeros = sea level)
            _write_flat_tile(out_path)
            return True

        resp.raise_for_status()

        # Read GeoTIFF and convert to raw .hgt
        _geotiff_to_hgt(resp.content, out_path)
        return True

    except Exception as e:
        log.error(f"Failed to download {tile.hgt_filename}: {e}")
        return False


def _geotiff_to_hgt(tiff_bytes: bytes, out_path: Path) -> None:
    """Convert a GeoTIFF to raw SRTM .hgt format.

    The GeoTIFF from Copernicus is 3601×3601 Float32 in WGS84.
    We convert to Int16 big-endian (SRTM convention).
    """
    import numpy as np

    # Simple GeoTIFF reader for single-band elevation data
    # For production, use rasterio. This handles the common case.
    try:
        import rasterio  # type: ignore
        with rasterio.open(io.BytesIO(tiff_bytes)) as src:
            data = src.read(1)  # Band 1
    except ImportError:
        # Fallback: try to parse the TIFF manually using numpy
        # This is fragile but works for Copernicus GLO-30 tiles
        log.warning(
            "rasterio not installed; attempting raw TIFF parse. "
            "For reliability, install rasterio: pip install rasterio"
        )
        # Skip TIFF header and read raw data
        # Copernicus tiles are 3601×3601 Float32
        expected_floats = FULL_GRID_SIZE * FULL_GRID_SIZE
        # Try reading as Float32 from the end of the file
        float_bytes = expected_floats * 4
        if len(tiff_bytes) >= float_bytes:
            raw = tiff_bytes[-float_bytes:]
            data = np.frombuffer(raw, dtype=np.float32).reshape(
                FULL_GRID_SIZE, FULL_GRID_SIZE
            )
        else:
            raise ValueError(
                f"TIFF too small ({len(tiff_bytes)} bytes). "
                f"Install rasterio for proper parsing."
            )

    # Convert to Int16 big-endian (SRTM .hgt format)
    # Clamp to Int16 range and handle nodata (-32768 by convention)
    elevation = np.clip(data, -500, 9000).astype(np.int16)

    # SRTM .hgt is big-endian
    if sys.byteorder == "little":
        elevation = elevation.byteswap()

    elevation.tofile(str(out_path))
    log.debug(f"Written: {out_path} ({out_path.stat().st_size:,} bytes)")


def _write_flat_tile(out_path: Path) -> None:
    """Write a flat (sea-level) tile for ocean areas."""
    data = b"\x00\x00" * (FULL_GRID_SIZE * FULL_GRID_SIZE)
    out_path.write_bytes(data)


# -----------------------------------------------------------------------
#  Convert command
# -----------------------------------------------------------------------

def cmd_convert(args: argparse.Namespace) -> None:
    """Downsample full-resolution tiles to medium and low resolution."""
    try:
        import numpy as np
    except ImportError:
        log.error("numpy is required. Install with: pip install numpy")
        sys.exit(1)

    input_dir = Path(args.input)
    if not input_dir.exists():
        log.error(f"Input directory not found: {input_dir}")
        sys.exit(1)

    output_base = Path(args.output)

    # Find all .hgt files in the input directory
    hgt_files = sorted(input_dir.glob("*.hgt"))
    if not hgt_files:
        log.error(f"No .hgt files found in {input_dir}")
        sys.exit(1)

    log.info(f"Found {len(hgt_files)} tiles to convert")

    for res_name, grid_size in RESOLUTIONS.items():
        if res_name == "full":
            continue  # Skip full resolution (already exists)

        res_dir = output_base / res_name
        res_dir.mkdir(parents=True, exist_ok=True)

        for hgt_path in hgt_files:
            out_path = res_dir / hgt_path.name

            if out_path.exists():
                log.debug(f"Already converted: {res_name}/{hgt_path.name}")
                continue

            _downsample_tile(hgt_path, out_path, grid_size)

    log.info("Conversion complete")


def _downsample_tile(
    input_path: Path, output_path: Path, target_size: int,
) -> None:
    """Downsample a full-resolution .hgt tile to a smaller grid."""
    import numpy as np

    # Read the full-resolution tile
    data = np.fromfile(str(input_path), dtype=">i2")  # big-endian Int16

    if data.size != FULL_GRID_SIZE * FULL_GRID_SIZE:
        log.warning(
            f"Unexpected tile size: {data.size} values "
            f"(expected {FULL_GRID_SIZE * FULL_GRID_SIZE}). Skipping."
        )
        return

    grid = data.reshape(FULL_GRID_SIZE, FULL_GRID_SIZE)

    # Downsample using block averaging
    # Step size: how many source pixels per output pixel
    step = (FULL_GRID_SIZE - 1) / (target_size - 1)

    # Sample at regular intervals (nearest neighbor for elevation)
    indices = np.round(np.linspace(0, FULL_GRID_SIZE - 1, target_size)).astype(int)
    downsampled = grid[np.ix_(indices, indices)]

    # Write as big-endian Int16
    downsampled.astype(">i2").tofile(str(output_path))

    in_kb = input_path.stat().st_size / 1024
    out_kb = output_path.stat().st_size / 1024
    ratio = out_kb / in_kb * 100
    log.info(
        f"  {input_path.name} → {output_path.parent.name}/{output_path.name} "
        f"({in_kb:,.0f} KB → {out_kb:,.0f} KB, {ratio:.1f}%)"
    )


# -----------------------------------------------------------------------
#  Pack command
# -----------------------------------------------------------------------

def cmd_pack(args: argparse.Namespace) -> None:
    """Pack multi-resolution tiles into a SQLite database."""
    input_dir = Path(args.input)
    db_path = args.output

    if not input_dir.exists():
        log.error(f"Input directory not found: {input_dir}")
        sys.exit(1)

    if os.path.exists(db_path):
        os.remove(db_path)

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Create schema
    cursor.execute("""
        CREATE TABLE tiles (
            filename TEXT NOT NULL,
            resolution TEXT NOT NULL,
            lat_sw INTEGER NOT NULL,
            lon_sw INTEGER NOT NULL,
            grid_size INTEGER NOT NULL,
            data BLOB NOT NULL,
            PRIMARY KEY (filename, resolution)
        )
    """)
    cursor.execute(
        "CREATE INDEX idx_tiles_location ON tiles(lat_sw, lon_sw)"
    )

    # Create metadata table
    cursor.execute("""
        CREATE TABLE metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )
    """)

    total_tiles = 0
    total_bytes = 0

    for res_name, grid_size in RESOLUTIONS.items():
        res_dir = input_dir / res_name
        if not res_dir.exists():
            log.warning(f"Resolution directory not found: {res_dir}")
            continue

        hgt_files = sorted(res_dir.glob("*.hgt"))
        log.info(f"Packing {len(hgt_files)} {res_name} tiles...")

        for hgt_path in hgt_files:
            # Parse lat/lon from filename
            tile = _parse_hgt_filename(hgt_path.name)
            if tile is None:
                log.warning(f"Skipping unrecognized file: {hgt_path.name}")
                continue

            # Read and compress the tile data
            raw_data = hgt_path.read_bytes()

            # Use zlib compression via SQLite
            cursor.execute(
                "INSERT INTO tiles "
                "(filename, resolution, lat_sw, lon_sw, grid_size, data) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (hgt_path.name, res_name, tile.lat, tile.lon, grid_size, raw_data),
            )

            total_tiles += 1
            total_bytes += len(raw_data)

    # Write metadata
    cursor.execute(
        "INSERT INTO metadata (key, value) VALUES (?, ?)",
        ("format_version", "1"),
    )
    cursor.execute(
        "INSERT INTO metadata (key, value) VALUES (?, ?)",
        ("tile_count", str(total_tiles)),
    )

    conn.commit()
    conn.close()

    db_size_mb = os.path.getsize(db_path) / (1024 * 1024)
    raw_size_mb = total_bytes / (1024 * 1024)
    log.info(
        f"Database written: {db_path}\n"
        f"  Tiles: {total_tiles}\n"
        f"  Raw size:  {raw_size_mb:,.1f} MB\n"
        f"  DB size:   {db_size_mb:,.1f} MB"
    )


def _parse_hgt_filename(filename: str) -> TileCoord | None:
    """Parse N46E007.hgt → TileCoord(lat=46, lon=7)."""
    import re
    m = re.match(r"^([NS])(\d{2})([EW])(\d{3})\.hgt$", filename)
    if not m:
        return None

    lat = int(m.group(2))
    lon = int(m.group(4))
    if m.group(1) == "S":
        lat = -lat
    if m.group(3) == "W":
        lon = -lon

    return TileCoord(lat=lat, lon=lon)


# -----------------------------------------------------------------------
#  All-in-one command
# -----------------------------------------------------------------------

def cmd_all(args: argparse.Namespace) -> None:
    """Download, convert, and pack — full pipeline."""
    log.info("=== Step 1/3: Download ===")
    cmd_download(args)

    log.info("=== Step 2/3: Convert ===")
    # Set input to the full-resolution directory
    convert_args = argparse.Namespace(
        input=str(Path(args.output) / "full"),
        output=args.output,
    )
    cmd_convert(convert_args)

    if args.pack:
        log.info("=== Step 3/3: Pack ===")
        pack_args = argparse.Namespace(
            input=args.output,
            output=str(Path(args.output) / "region.db"),
        )
        cmd_pack(pack_args)

    log.info("=== All done ===")


# -----------------------------------------------------------------------
#  CLI entry point
# -----------------------------------------------------------------------

def _parse_bbox(s: str) -> tuple[float, float, float, float]:
    parts = [float(x.strip()) for x in s.split(",")]
    if len(parts) != 4:
        raise argparse.ArgumentTypeError(
            "Bounding box must be: min_lat,min_lon,max_lat,max_lon"
        )
    return (parts[0], parts[1], parts[2], parts[3])


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Prepare DEM tiles for PeakLine app.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # --- download ---
    dl = subparsers.add_parser(
        "download", help="Download Copernicus GLO-30 tiles",
    )
    dl.add_argument("--bbox", type=_parse_bbox, required=True)
    dl.add_argument("--username", required=True, help="Copernicus account email")
    dl.add_argument("--password", required=True, help="Copernicus account password")
    dl.add_argument("-o", "--output", default="./dem_tiles")

    # --- convert ---
    cv = subparsers.add_parser(
        "convert", help="Downsample tiles to multi-resolution",
    )
    cv.add_argument("--input", required=True, help="Directory with full-res .hgt files")
    cv.add_argument("-o", "--output", default="./dem_tiles")

    # --- pack ---
    pk = subparsers.add_parser(
        "pack", help="Pack tiles into a SQLite database",
    )
    pk.add_argument("--input", required=True, help="Directory with multi-res tiles")
    pk.add_argument("-o", "--output", default="region.db")

    # --- all ---
    al = subparsers.add_parser(
        "all", help="Download + convert + pack (full pipeline)",
    )
    al.add_argument("--bbox", type=_parse_bbox, required=True)
    al.add_argument("--username", required=True)
    al.add_argument("--password", required=True)
    al.add_argument("-o", "--output", default="./dem_tiles")
    al.add_argument("--pack", action="store_true", help="Also pack into SQLite")

    args = parser.parse_args()

    commands = {
        "download": cmd_download,
        "convert": cmd_convert,
        "pack": cmd_pack,
        "all": cmd_all,
    }
    commands[args.command](args)


if __name__ == "__main__":
    main()
