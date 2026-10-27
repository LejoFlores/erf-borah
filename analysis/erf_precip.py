#!/usr/bin/env python3
"""Surface precipitation from ERF plotfiles into one small NetCDF, for copying off Borah.

    python analysis/erf_precip.py $ERF_CASE/erf erf_precip.nc

Writes, for each AMR level and each plotfile time, the accumulated precipitation at the surface
(rain_accum, snow_accum, graup_accum in mm since the start; with Morrison, rain_accum is TOTAL
precipitation) and the lowest cell-centre height z_phys, on that level's grid (x, y in m from the
domain's south-west corner; NaN outside a nest), plus XLAT, XLONG and HGT from the
wrfinput_d0N files in the same folder. Only numpy and netCDF4 are needed (no yt).
"""
import glob, os, re, sys
import numpy as np
import netCDF4

FIELDS = ["rain_accum", "snow_accum", "graup_accum", "z_phys"]


def read_header(plt):
    with open(os.path.join(plt, "Header")) as f:
        lines = [l.rstrip("\n") for l in f]
    ncomp = int(lines[1])
    names = lines[2:2 + ncomp]
    i = 2 + ncomp
    time = float(lines[i + 1])
    finest = int(lines[i + 2])
    lo = [float(v) for v in lines[i + 3].split()]
    i += 6  # skip prob_hi and ref ratios
    i += 2  # domain boxes, steps
    dx = [[float(v) for v in lines[i + l].split()] for l in range(finest + 1)]
    return dict(names=names, time=time, finest=finest, lo=lo, dx=dx)


def read_level(plt, lev, comps):
    """Return {name: list of (lo, hi, k=0 slab)} for the requested components on one level."""
    d = os.path.join(plt, f"Level_{lev}")
    with open(os.path.join(d, "Cell_H")) as f:
        txt = f.read()
    fabs = re.findall(r"FabOnDisk: (\S+) (\d+)", txt)
    out = {c: [] for c in comps}
    for fname, off in fabs:
        with open(os.path.join(d, fname), "rb") as f:
            f.seek(int(off))
            head = f.readline().decode()
            m = re.search(r"\(\((-?\d+),(-?\d+),(-?\d+)\) \((-?\d+),(-?\d+),(-?\d+)\)[^)]*\)\)\s*(\d+)", head)
            ilo, jlo, klo, ihi, jhi, khi, nc = map(int, m.groups())
            bo = "<" if "(8 7 6 5 4 3 2 1)" in head else ">"   # AMReX's tag for little-endian doubles
            nx, ny, nz = ihi - ilo + 1, jhi - jlo + 1, khi - klo + 1
            n = nx * ny * nz
            base = f.tell()
            for name, c in comps.items():
                if klo != 0:
                    continue
                f.seek(base + c * n * 8)
                slab = np.fromfile(f, dtype=bo + "f8", count=nx * ny)  # k = 0 plane, x fastest
                out[name].append(((ilo, jlo), (ihi, jhi), slab.reshape(ny, nx)))
    return out


def main(erfdir, outfile):
    plts = sorted(p for p in glob.glob(os.path.join(erfdir, "plt*")) if re.fullmatch(r"plt\d+", os.path.basename(p)))
    if not plts:
        sys.exit(f"no plt* folders in {erfdir}")
    h0 = read_header(plts[-1])
    comps = {n: h0["names"].index(n) for n in FIELDS if n in h0["names"]}
    missing = set(FIELDS) - set(comps)
    if missing:
        print("not in plotfiles:", ", ".join(sorted(missing)))
    nlev = h0["finest"] + 1

    # Grid of each level: bounding box of its boxes, from the last plotfile
    grids = []
    for lev in range(nlev):
        boxes = next(iter(read_level(plts[-1], lev, comps).values()))
        ilo = min(b[0][0] for b in boxes); jlo = min(b[0][1] for b in boxes)
        ihi = max(b[1][0] for b in boxes); jhi = max(b[1][1] for b in boxes)
        dx, dy = h0["dx"][lev][:2]
        grids.append(dict(ilo=ilo, jlo=jlo, nx=ihi - ilo + 1, ny=jhi - jlo + 1, dx=dx, dy=dy))

    nc = netCDF4.Dataset(outfile, "w")
    nc.title = "ERF surface precipitation from plotfiles (analysis/erf_precip.py)"
    nc.source_dir = os.path.abspath(erfdir)
    nc.note = "Morrison: rain_accum is total precipitation (rain + snow + graupel), mm since model start"
    nc.createDimension("time", len(plts))
    t = nc.createVariable("time", "f8", ("time",))
    t.units = "seconds since model start"
    for lev, g in enumerate(grids):
        sx, sy = f"x{lev}", f"y{lev}"
        nc.createDimension(sx, g["nx"]); nc.createDimension(sy, g["ny"])
        x = nc.createVariable(sx, "f8", (sx,)); x.units = "m"
        y = nc.createVariable(sy, "f8", (sy,)); y.units = "m"
        x[:] = h0["lo"][0] + (g["ilo"] + np.arange(g["nx"]) + 0.5) * g["dx"]
        y[:] = h0["lo"][1] + (g["jlo"] + np.arange(g["ny"]) + 0.5) * g["dy"]
        for name in comps:
            v = nc.createVariable(f"{name}_l{lev}", "f4", ("time", sy, sx), zlib=True, complevel=4, fill_value=np.float32(np.nan))
            v.units = "m" if name == "z_phys" else "mm"
            v.level = lev; v.dx_m = g["dx"]
    # Latitude, longitude and terrain of the WPS grids (wrfinput_d0N next to the plotfiles), for regridding
    for n in range(1, 4):
        w = os.path.join(erfdir, f"wrfinput_d0{n}")
        if not os.path.exists(w):
            continue
        with netCDF4.Dataset(w) as src:
            ny, nx = src["XLAT"].shape[-2:]
            nc.createDimension(f"south_north_d0{n}", ny); nc.createDimension(f"west_east_d0{n}", nx)
            for v in ["XLAT", "XLONG", "HGT"]:
                o = nc.createVariable(f"{v}_d0{n}", "f4", (f"south_north_d0{n}", f"west_east_d0{n}"), zlib=True)
                o[:] = src[v][0]
                o.units = src[v].units
    for it, p in enumerate(plts):
        h = read_header(p)
        t[it] = h["time"]
        for lev, g in enumerate(grids):
            if lev > h["finest"]:
                continue
            for name, boxes in read_level(p, lev, comps).items():
                a = np.full((g["ny"], g["nx"]), np.nan, np.float32)
                for (ilo, jlo), (ihi, jhi), slab in boxes:
                    a[jlo - g["jlo"]:jhi - g["jlo"] + 1, ilo - g["ilo"]:ihi - g["ilo"] + 1] = slab
                nc[f"{name}_l{lev}"][it] = a
        print(os.path.basename(p), f"t={h['time']:.0f} s",
              " ".join(f"L{l} mean rain_accum {np.nanmean(nc[f'rain_accum_l{l}'][it]):.2f} mm" for l in range(nlev) if "rain_accum" in comps))
    nc.close()
    print("wrote", outfile, f"{os.path.getsize(outfile)/1e6:.1f} MB")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
