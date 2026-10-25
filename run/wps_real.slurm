#!/bin/bash
#SBATCH -J erf-wps-real
#SBATCH -p bsudfq
#SBATCH -N 1
#SBATCH --exclusive          # whole node: shared CPU nodes ran MPI jobs 10-20x slower
#SBATCH -n 16
#SBATCH -t 04:00:00
#SBATCH -o erf-wps-real-%j.log
# HRRR -> WPS (geogrid, ungrib, metgrid) -> real.exe -> wrfinput_d01..d03 + wrfbdy_d01 for ERF.
# Uses Borah's Intel WPS 4.6.0 / WRF 4.7.1 modules unless ERF_WRF_ENV=/path/env.sh (your own build, e.g. from
# idaho-summer-precip's build_wrf_wvt.sh) or WPS_DIR and WRF_DIR point at your own build.
#   ERF_GEOG_DIR=/path/to/WPS_GEOG ERF_CASE=/bsuscratch/$USER/erf/cases/drycreek_dec2015 \
#   ERF_START=2015-12-18_18 ERF_END=2015-12-19_06 sbatch --export=ALL run/wps_real.slurm
# ERF_UNGRIB_EXE=/path/ungrib.exe uses another WPS build's ungrib (its intermediate files work with metgrid 4.6);
# ERF_EXTRA_MODULES="..." loads extra modules that build needs.
# ERF_REAL_ONLY=1 reruns only real.exe if every met_em file is readable, else reruns metgrid on the
# existing ungrib output. ERF_METGRID_NP sets metgrid's MPI ranks (default 1: with 16, ranks clashed on the first file).
# Fetch HRRR first (login node is fine): python setup/hrrr_wps.py ... --out $ERF_CASE/hrrr
set -euo pipefail
# Variables are ERF_-prefixed so other models' jobs (SCHNAPS, WRF, ParFlow use CASE, START, ...) can't leak in.
for p in CASE:ERF_CASE START:ERF_START END:ERF_END ENV_SH:ERF_WRF_ENV GEOG_DIR:ERF_GEOG_DIR GEOGRES:ERF_GEOGRES GEOGRID_TBL:ERF_GEOGRID_TBL UNGRIB_EXE:ERF_UNGRIB_EXE EXTRA_MODULES:ERF_EXTRA_MODULES REAL_ONLY:ERF_REAL_ONLY METGRID_NP:ERF_METGRID_NP; do o=${p%%:*} n=${p#*:}
  [ -n "${!o:-}" ] && [ -z "${!n:-}" ] && echo "note: $o is set but ignored here; this script reads $n"; done
REPO=$SLURM_SUBMIT_DIR
: ${ERF_GEOG_DIR:?set ERF_GEOG_DIR to the WPS static geography data}
: ${ERF_CASE:?set ERF_CASE}
ERF_START=${ERF_START:-2015-12-18_18}; ERF_END=${ERF_END:-2015-12-19_06}
ERF_GEOGRES=${ERF_GEOGRES:-default}       # e.g. "schnaps_topo+default" once the SCHNAPS terrain is in ERF_GEOG_DIR

if [ -n "${ERF_WRF_ENV:-}" ]; then
  # Your own WRF/WPS build: env.sh from idaho-summer-precip's build_wrf_wvt.sh sets the modules,
  # WRF_DIR, WPS_DIR and the jasper/netCDF library path. Its `module purge` drops the slurm module,
  # so keep that directory on PATH.
  SLURM_BIN=$(dirname "$(command -v sbatch || echo /nonexistent/sbatch)")
  source "$ERF_WRF_ENV"
  [ -d "$SLURM_BIN" ] && export PATH=$PATH:$SLURM_BIN
else
  module purge
  module load slurm borah-base borah-libraries
  if [ -z "${WPS_DIR:-}" ]; then module load wps/4.6.0/openmpi/4.1.3/intel/2021.6.0; fi
  if [ -z "${WRF_DIR:-}" ]; then module load wrf/4.7.1/openmpi/4.1.3/intel/2021.6.0; fi
fi
[ -n "${ERF_EXTRA_MODULES:-}" ] && module load $ERF_EXTRA_MODULES       # e.g. intel/2021.6.0 for your own WPS build
: ${WPS_DIR:?WPS module did not set WPS_DIR; set it to your WPS directory}
: ${WRF_DIR:?set WRF_DIR to your WRF directory}
# Some installs keep the executables in geogrid/, ungrib/ and metgrid/, others at the top level
findexe() { local f; f=$(find -L $1 -maxdepth $2 -name $3 -type f | head -1); [ -n "$f" ] || { echo "$3 not found under $1" >&2; exit 1; }; echo $f; }
GEOGRID=$(findexe $WPS_DIR 2 geogrid.exe); UNGRIB=${ERF_UNGRIB_EXE:-$(findexe $WPS_DIR 2 ungrib.exe)}   # Borah's module ungrib lacks libjasper.so.6/libpng15; override with your own
METGRID=$(findexe $WPS_DIR 2 metgrid.exe)
REALEXE=$(findexe $WRF_DIR 3 real.exe)
# A serial WPS build launched with mpirun runs N copies that all write the same file and corrupt it
par() { local n=$1; shift; if ldd $1 | grep -q libmpi; then mpirun -np $n --bind-to core "$@"; else "$@"; fi; }
# link_grib.csh in bash: Borah has no csh on some nodes. GRIBFILE.AAA, .AAB, ...
link_grib() { local i=0 L=ABCDEFGHIJKLMNOPQRSTUVWXYZ f
  for f in "$@"; do ln -sf "$f" "GRIBFILE.${L:i/676%26:1}${L:i/26%26:1}${L:i%26:1}"; i=$((i + 1)); done; }
echo "geogrid: $GEOGRID  ungrib: $UNGRIB  metgrid: $METGRID  real.exe: $REALEXE"

fill() {  # fill() template out: substitute dates and paths
  local y0=${ERF_START:0:4} m0=${ERF_START:5:2} d0=${ERF_START:8:2} h0=${ERF_START:11:2}
  local y1=${ERF_END:0:4} m1=${ERF_END:5:2} d1=${ERF_END:8:2} h1=${ERF_END:11:2}
  sed -e "s|__START__|${ERF_START}:00:00|g" -e "s|__END__|${ERF_END}:00:00|g" -e "s|__GEOG__|$ERF_GEOG_DIR|" \
      -e "s|__GEOGRES1__|default|" -e "s|__GEOGRES2__|$ERF_GEOGRES|" -e "s|__GEOGRES3__|$ERF_GEOGRES|" \
      -e "s|__Y0__|$y0|g" -e "s|__M0__|$m0|g" -e "s|__D0__|$d0|g" -e "s|__H0__|$h0|g" \
      -e "s|__Y1__|$y1|g" -e "s|__M1__|$m1|g" -e "s|__D1__|$d1|g" -e "s|__H1__|$h1|g" $1 > $2
}

mkdir -p $ERF_CASE/wps $ERF_CASE/real $ERF_CASE/erf
cd $ERF_CASE/wps
fill $REPO/setup/namelist.wps namelist.wps
mkdir -p geogrid metgrid
ln -sf $WPS_DIR/geogrid/GEOGRID.TBL.ARW geogrid/GEOGRID.TBL 2>/dev/null || ln -sf $WPS_DIR/geogrid/GEOGRID.TBL geogrid/
[ -n "${ERF_GEOGRID_TBL:-}" ] && ln -sf $ERF_GEOGRID_TBL geogrid/GEOGRID.TBL     # custom table with schnaps_topo
ln -sf $WPS_DIR/metgrid/METGRID.TBL.ARW metgrid/METGRID.TBL 2>/dev/null || ln -sf $WPS_DIR/metgrid/METGRID.TBL metgrid/
# WPS's Vtable.raphrrr with PMSL read from PRMSL (our wrfnat records have PRMSL, not MSLMA). Without sea-level
# pressure, real.exe interpolates hydrometeors with an unset order: WRF 4.3.3 stops ("pal, linear is
# about as low as we go"); Borah's 4.7.1 likely segfaulted for the same reason.
ln -sf $REPO/setup/Vtable.hrrr Vtable
ncdump -k geo_em.d03.nc >/dev/null 2>&1 || par 4 $GEOGRID
# Nests get met_em files only at the start time, so a full set is all hours of d01 plus one d02 and one d03
met_ok() { ls met_em.d03.* >/dev/null 2>&1 || return 1
           for f in met_em.d0*; do ncdump -k $f >/dev/null 2>&1 || { echo "unreadable: $f" >&2; return 1; }; done; }
if [ -n "${ERF_REAL_ONLY:-}" ] && met_ok; then
  echo "ERF_REAL_ONLY: reusing the existing met_em files"
else
  if [ -z "${ERF_REAL_ONLY:-}" ] || ! ls HRRR:* >/dev/null 2>&1; then
    rm -f GRIBFILE.* HRRR:*
    link_grib $ERF_CASE/hrrr/hrrr.*.grib2
    $UNGRIB
  else
    echo "ERF_REAL_ONLY: reusing ungrib output, rerunning metgrid"
  fi
  rm -f met_em.d0*
  par ${ERF_METGRID_NP:-1} $METGRID     # several ranks clash opening the first met_em file on Borah
  met_ok || { echo "metgrid wrote unreadable files" >&2; exit 1; }
fi
ls met_em.d0* | head -3

cd $ERF_CASE/real
fill $REPO/setup/namelist.input namelist.input
ln -sf $ERF_CASE/wps/met_em.d0* .
for f in $WRF_DIR/run/*.TBL $WRF_DIR/run/*_DATA $WRF_DIR/run/*.formatted; do [ -e $f ] && ln -sf $f .; done
ulimit -s unlimited          # real.exe segfaults in vertical interpolation with the default 8 MB stack
mpirun -np ${SLURM_NTASKS:-16} --bind-to core $REALEXE
tail -2 rsl.out.0000
cp wrfinput_d01 wrfinput_d02 wrfinput_d03 wrfbdy_d01 $ERF_CASE/erf/
ncdump -h $ERF_CASE/erf/wrfbdy_d01 | grep -E "QCLOUD_BXS|QICE_BXS|QRAIN_BXS" || echo "no moisture boundaries in wrfbdy_d01"
echo "ERF inputs ready in $ERF_CASE/erf. Next: sbatch --export=ALL run/erf_gpu.slurm"
