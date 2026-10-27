#!/usr/bin/env python3
"""Put HRRR's cloud water, rain, ice, snow and graupel into wrfbdy_d01's lateral boundaries.

    python setup/wrfbdy_hydrometeors.py wrfbdy_d01 'wrfinput_d01.*'

WRF's real.exe (checked 4.3.3 to 4.7.1) fills only QVAPOR in wrfbdy: QCLOUD, QRAIN, QICE, QSNOW and
QGRAUP are written but stay zero, even with have_bcs_moist and hydrometeors in the met_em files. ERF reads
them (erf.use_wrf_bdy_qc_qi), so without this step no cloud or precipitation enters through the boundaries.

real.exe with all_ic_times = .true. writes wrfinput_d01.<date> at every boundary time, holding the
hydrometeors on the model grid. real.exe couples moisture as q * (c1h * (mu + mub) + c2h) for QVAPOR; the
same factor applies to every moisture species, so it is taken from wrfbdy's own QVAPOR values (coupled QV / qv
at each boundary point). Tendencies (_BT*) are the coupled change to the next time over interval_seconds,
as real.exe computes them for QVAPOR. wrfbdy is changed in place; a copy of the original is kept as
<wrfbdy>.qv_only.
"""
import glob, os, shutil, sys
import numpy as np
import netCDF4

SPECIES = ["QCLOUD", "QRAIN", "QICE", "QSNOW", "QGRAUP"]


def edges(a, w):
    """Boundary strips of a (k, j, i) field, in wrfbdy's (bdy_width, k, along-edge) layout."""
    ny, nx = a.shape[1:]
    return {"BXS": np.stack([a[:, :, i] for i in range(w)]),
            "BXE": np.stack([a[:, :, nx - 1 - i] for i in range(w)]),
            "BYS": np.stack([a[:, j, :] for j in range(w)]),
            "BYE": np.stack([a[:, ny - 1 - j, :] for j in range(w)])}


def main(bdyfile, pattern):
    inputs = sorted(glob.glob(pattern))
    if not inputs:
        sys.exit(f"no files match {pattern}: run real.exe with all_ic_times = .true.")
    if not os.path.exists(bdyfile + ".qv_only"):
        shutil.copy2(bdyfile, bdyfile + ".qv_only")
    bdy = netCDF4.Dataset(bdyfile, "r+")
    times = [b"".join(t).decode() for t in bdy["Times"][:]]
    dt = float(bdy.getncattr("INTERVAL_SECONDS")) if "INTERVAL_SECONDS" in bdy.ncattrs() else 3600.0
    w = bdy.dimensions["bdy_width"].size
    byname = {}
    for f in inputs:
        with netCDF4.Dataset(f) as d:
            byname[b"".join(d["Times"][0]).decode()] = f
    # wrfbdy record n holds the values at times[n] and the tendency to the next time
    have = sorted(byname)
    for n, t in enumerate(times):
        if t not in byname or have.index(t) + 1 >= len(have):
            sys.exit(f"need wrfinput_d01 at {t} and at the next boundary time (have {have})")
        tnext = have[have.index(t) + 1]
        coupled = {}
        for when, f in (("now", byname[t]), ("next", byname[tnext])):
            with netCDF4.Dataset(f) as d:
                qv = edges(d["QVAPOR"][0].astype("f8"), w)
                for s in SPECIES:
                    if s in d.variables:
                        q = edges(d[s][0].astype("f8"), w)
                        coupled[when, s] = {}
                        for side in q:
                            # coupling factor from wrfbdy's QVAPOR at this record (now) or the next (via tendency)
                            qvc = bdy[f"QVAPOR_{side}"][n].astype("f8")
                            if when == "next":
                                qvc = qvc + dt * bdy[f"QVAPOR_BT{side[1:]}"][n].astype("f8")
                            n_al = min(qvc.shape[-1], q[side].shape[-1])
                            fac = qvc[..., :n_al] / np.maximum(qv[side][..., :n_al], 1e-12)
                            out = np.zeros_like(qvc)
                            out[..., :n_al] = fac * q[side][..., :n_al]
                            coupled[when, s][side] = out
        for s in SPECIES:
            if ("now", s) not in coupled:
                continue
            for side in ("BXS", "BXE", "BYS", "BYE"):
                if f"{s}_{side}" not in bdy.variables:
                    continue
                bdy[f"{s}_{side}"][n] = coupled["now", s][side]
                bdy[f"{s}_BT{side[1:]}"][n] = (coupled["next", s][side] - coupled["now", s][side]) / dt
    for s in SPECIES:
        if f"{s}_BXS" in bdy.variables:
            print(f"{s}: max coupled boundary value {max(float(bdy[f'{s}_{x}'][:].max()) for x in ('BXS', 'BXE', 'BYS', 'BYE')):.3g}")
    bdy.close()
    print(f"filled {len(times)} boundary times in {bdyfile} from {len(inputs)} wrfinput files")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
