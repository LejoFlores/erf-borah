#!/usr/bin/env python3
"""Turn the SCHNAPS Dry Creek terrain (Copernicus GLO-30 on the SCHNAPS d01/d02/d03 grids) into a WPS
static dataset, so ERF's 250 m and 50 m levels see the same terrain as SCHNAPS instead of WPS's
~1 km default topography.

Writes <out>/index and one big-endian int16 tile on a regular lat-lon grid of --res degrees over the
d02 footprint, taking each point from the finest SCHNAPS domain that covers it (bilinear on that
domain's own stereographic grid). Then add the GEOGRID.TBL entry printed at the end and run WPS with
ERF_GEOGRES=schnaps_topo+default (run/wps_real.slurm).

  python schnaps_topo_to_wps.py --domains <schnaps-borah>/setup/drycreek/domains --out $ERF_GEOG_DIR/schnaps_topo
"""
import argparse, os
import numpy as np, netCDF4 as nc
from pyproj import Proj

FILES = ["drycreek_50m_d03_50m.nc", "drycreek_50m_d02_250m.nc", "drycreek_50m_d01_1000m.nc"]  # finest first


def bilinear(x, y, X, Y, Z):
    """Bilinear interpolation of Z(Y, X) (1-D increasing X, Y) at points x, y; NaN outside."""
    i = np.searchsorted(X, x) - 1; j = np.searchsorted(Y, y) - 1
    ok = (i >= 0) & (i < len(X) - 1) & (j >= 0) & (j < len(Y) - 1)
    i = np.clip(i, 0, len(X) - 2); j = np.clip(j, 0, len(Y) - 2)
    fx = (x - X[i]) / (X[i + 1] - X[i]); fy = (y - Y[j]) / (Y[j + 1] - Y[j])
    z = (Z[j, i] * (1 - fx) * (1 - fy) + Z[j, i + 1] * fx * (1 - fy)
         + Z[j + 1, i] * (1 - fx) * fy + Z[j + 1, i + 1] * fx * fy)
    return np.where(ok, z, np.nan)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--domains", required=True); p.add_argument("--out", required=True)
    p.add_argument("--res", type=float, default=0.0003, help="degrees (0.0003 = 33 m N-S, 24 m E-W)")
    a = p.parse_args()

    doms = []
    for f in FILES:
        d = nc.Dataset(os.path.join(a.domains, f))
        doms.append((Proj(d.crs_proj4), d["x"][:].astype(float), d["y"][:].astype(float),
                     d["topo"][:].astype(float), d["lat"][:], d["lon"][:]))
    _, _, _, _, lat2, lon2 = doms[1]                         # cover the d02 footprint plus a margin
    lat0, lat1 = float(lat2.min()) - 0.04, float(lat2.max()) + 0.04
    lon0, lon1 = float(lon2.min()) - 0.04, float(lon2.max()) + 0.04
    lats = np.arange(lat0, lat1, a.res); lons = np.arange(lon0, lon1, a.res)
    LON, LAT = np.meshgrid(lons, lats)
    hgt = np.full(LAT.shape, np.nan)
    for P, X, Y, Z, _, _ in doms:
        x, y = P(LON, LAT)
        z = bilinear(x, y, X, Y, Z)
        hgt = np.where(np.isnan(hgt), z, hgt)
    if np.isnan(hgt).any():
        raise SystemExit(f"{np.isnan(hgt).sum()} points not covered by any SCHNAPS domain")

    os.makedirs(a.out, exist_ok=True)
    ny, nx = hgt.shape
    np.round(hgt).astype(">i2").tofile(os.path.join(a.out, f"00001-{nx:05d}.00001-{ny:05d}"))
    with open(os.path.join(a.out, "index"), "w") as f:
        f.write(f"""type = continuous
signed = yes
projection = regular_ll
dx = {a.res}
dy = {a.res}
known_x = 1.0
known_y = 1.0
known_lat = {lat0:.6f}
known_lon = {lon0:.6f}
wordsize = 2
tile_x = {nx}
tile_y = {ny}
tile_z = 1
units = "meters MSL"
description = "SCHNAPS Dry Creek terrain (Copernicus GLO-30 via setup_schnaps.py)"
missing_value = -32768
""")
    print(f"{nx} x {ny} points, {hgt.min():.0f}-{hgt.max():.0f} m, written to {a.out}")
    print("Add to the HGT_M entry of your GEOGRID.TBL (ERF_GEOGRID_TBL=... for run/wps_real.slurm):")
    print(f"  interp_option = schnaps_topo:average_gcell(4.0)+four_pt\n  rel_path = schnaps_topo:{os.path.basename(a.out.rstrip('/'))}/")


if __name__ == "__main__":
    main()
