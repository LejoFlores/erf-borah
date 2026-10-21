#!/usr/bin/env python3
"""Fetch HRRR GRIB2 for WPS (ungrib with Vtable.raphrrr) from the AWS archive.

Same source and lead as the SCHNAPS forcing (setup/hrrr_forcing.py in schnaps-borah): each valid hour
comes from the forecast of length --lead (default 6 h) started --lead hours earlier, falling back to a
longer lead when a file is missing. Only the GRIB records ungrib needs are downloaded (HTTP byte
ranges from the .idx files), so each hour is one small GRIB2 file:
  native (hybrid) levels from wrfnat: HGT PRES TMP SPFH UGRD VGRD + CLMR CICE RWMR SNMR GRLE
  surface fields from wrfnat; soil temperature and moisture from wrfprs (wrfnat has none in 2015).
Optionally crops each file with wgrib2 -small_grib to --bbox to save space.

  python hrrr_wps.py --start 2015-12-18T00 --end 2015-12-23T00 --out $CASE/hrrr \
      [--lead 6] [--bbox 42.7 -117.6 44.7 -114.8]
"""
import argparse, datetime as dt, os, re, shutil, subprocess, sys, urllib.request

BASE = "https://noaa-hrrr-bdp-pds.s3.amazonaws.com"
NAT = [r":(HGT|PRES|TMP|SPFH|UGRD|VGRD|CLMR|CICE|CIMIXR|RWMR|SNMR|GRLE):\d+ hybrid level:",
       r":(TMP|SPFH):2 m above ground:", r":(UGRD|VGRD):10 m above ground:",
       r":(PRES|HGT|TMP|SNOD|LAND|ICEC):surface:", r":PRMSL:mean sea level:",
       r":WEASD:surface:\d+ hour fcst:"]
PRS = [r":(TSOIL|SOILW):[\d.]+-[\d.]+ m below ground:", r":CNWAT:surface:"]


def get(url, rng=None):
    req = urllib.request.Request(url, headers={"Range": f"bytes={rng[0]}-{rng[1]}"} if rng else {})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def ranges(idx_text, patterns):
    lines = [l for l in idx_text.splitlines() if l]
    offs = [int(l.split(":")[1]) for l in lines]
    out = []
    for i, l in enumerate(lines):
        if any(re.search(p, ":" + l.split(":", 2)[2]) for p in patterns):
            end = offs[i + 1] - 1 if i + 1 < len(lines) else ""
            out.append((offs[i], end))
    return out


def fetch_hour(valid, lead, out, max_lead=18):
    for L in range(lead, max_lead + 1):
        init = valid - dt.timedelta(hours=L)
        stem = f"{BASE}/hrrr.{init:%Y%m%d}/conus/hrrr.t{init:%H}z"
        try:
            parts = []
            for kind, pats in (("wrfnat", NAT), ("wrfprs", PRS)):
                url = f"{stem}.{kind}f{L:02d}.grib2"
                for rng in ranges(get(url + ".idx").decode(), pats):
                    parts.append(get(url, rng))
            dest = os.path.join(out, f"hrrr.{valid:%Y%m%d%H}.f{L:02d}.grib2")
            with open(dest, "wb") as f:
                f.write(b"".join(parts))
            return dest, L, len(parts)
        except urllib.error.HTTPError as e:
            print(f"  {valid:%Y-%m-%d %H}Z lead {L}: {e.code}, trying a longer lead", file=sys.stderr)
    raise RuntimeError(f"no HRRR file for {valid}")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--start", required=True); p.add_argument("--end", required=True)
    p.add_argument("--out", required=True); p.add_argument("--lead", type=int, default=6)
    p.add_argument("--bbox", type=float, nargs=4, metavar=("LAT0", "LON0", "LAT1", "LON1"))
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)
    t, end = dt.datetime.fromisoformat(a.start), dt.datetime.fromisoformat(a.end)
    wg = shutil.which("wgrib2") if a.bbox else None
    if a.bbox and not wg:
        print("wgrib2 not found: keeping full CONUS records (about 0.5 GB per hour)", file=sys.stderr)
    while t <= end:
        dest, L, n = fetch_hour(t, a.lead, a.out)
        if wg:
            la0, lo0, la1, lo1 = a.bbox
            tmp = dest + ".crop"
            subprocess.run([wg, dest, "-small_grib", f"{lo0}:{lo1}", f"{la0}:{la1}", tmp],
                           check=True, stdout=subprocess.DEVNULL)
            os.replace(tmp, dest)
        print(f"{t:%Y-%m-%d %H}Z  lead {L} h  {n} records  {os.path.getsize(dest)/1e6:.0f} MB  {dest}")
        t += dt.timedelta(hours=1)


if __name__ == "__main__":
    main()
