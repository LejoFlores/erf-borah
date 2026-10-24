#!/bin/bash
#SBATCH -J erf-wps-real
#SBATCH -p bsudfq
#SBATCH -N 1
#SBATCH -n 16
#SBATCH -t 04:00:00
#SBATCH -o erf-wps-real-%j.log
# HRRR -> WPS (geogrid, ungrib, metgrid) -> real.exe -> wrfinput_d01..d03 + wrfbdy_d01 for ERF.
# Uses Borah's Intel WPS 4.6.0 / WRF 4.7.1 modules unless ENV_SH=/path/env.sh (your own build, e.g. from
# idaho-summer-precip's build_wrf_wvt.sh) or WPS_DIR and WRF_DIR point at your own build.
#   GEOG_DIR=/path/to/WPS_GEOG CASE=/bsuscratch/$USER/erf/cases/drycreek_dec2015 \
#   START=2015-12-18_18 END=2015-12-19_06 sbatch --export=ALL run/wps_real.slurm
# UNGRIB_EXE=/path/ungrib.exe uses another WPS build's ungrib (its intermediate files work with metgrid 4.6);
# EXTRA_MODULES="..." loads extra modules that build needs.
# REAL_ONLY=1 reruns only real.exe if every met_em file is readable, else reruns metgrid on the
# existing ungrib output. METGRID_NP sets metgrid's MPI ranks (default 1: with 16, ranks clashed on the first file).
# Fetch HRRR first (login node is fine): python setup/hrrr_wps.py ... --out $CASE/hrrr
set -euo pipefail
REPO=$SLURM_SUBMIT_DIR
: ${GEOG_DIR:?set GEOG_DIR to the WPS static geography data}
: ${CASE:?set CASE}
START=${START:-2015-12-18_18}; END=${END:-2015-12-19_06}
GEOGRES=${GEOGRES:-default}       # e.g. "schnaps_topo+default" once the SCHNAPS terrain is in GEOG_DIR

if [ -n "${ENV_SH:-}" ]; then
  # Your own WRF/WPS build: env.sh from idaho-summer-precip's build_wrf_wvt.sh sets the modules,
  # WRF_DIR, WPS_DIR and the jasper/netCDF library path. Its `module purge` drops the slurm module,
  # so keep that directory on PATH.
  SLURM_BIN=$(dirname "$(command -v sbatch || echo /nonexistent/sbatch)")
  source "$ENV_SH"
  [ -d "$SLURM_BIN" ] && export PATH=$PATH:$SLURM_BIN
else
  module purge
  module load slurm borah-base borah-libraries
  if [ -z "${WPS_DIR:-}" ]; then module load wps/4.6.0/openmpi/4.1.3/intel/2021.6.0; fi
  if [ -z "${WRF_DIR:-}" ]; then module load wrf/4.7.1/openmpi/4.1.3/intel/2021.6.0; fi
fi
[ -n "${EXTRA_MODULES:-}" ] && module load $EXTRA_MODULES       # e.g. intel/2021.6.0 for your own WPS build
: ${WPS_DIR:?WPS module did not set WPS_DIR; set it to your WPS directory}
: ${WRF_DIR:?set WRF_DIR to your WRF directory}
# Some installs keep the executables in geogrid/, ungrib/ and metgrid/, others at the top level
findexe() { local f; f=$(find -L $1 -maxdepth $2 -name $3 -type f | head -1); [ -n "$f" ] || { echo "$3 not found under $1" >&2; exit 1; }; echo $f; }
GEOGRID=$(findexe $WPS_DIR 2 geogrid.exe); UNGRIB=${UNGRIB_EXE:-$(findexe $WPS_DIR 2 ungrib.exe)}   # Borah's module ungrib lacks libjasper.so.6/libpng15; override with your own
METGRID=$(findexe $WPS_DIR 2 metgrid.exe)
REALEXE=$(findexe $WRF_DIR 3 real.exe)
# A serial WPS build launched with mpirun runs N copies that all write the same file and corrupt it
par() { local n=$1; shift; if ldd $1 | grep -q libmpi; then mpirun -np $n --bind-to core "$@"; else "$@"; fi; }
# link_grib.csh in bash: Borah has no csh on some nodes. GRIBFILE.AAA, .AAB, ...
link_grib() { local i=0 L=ABCDEFGHIJKLMNOPQRSTUVWXYZ f
  for f in "$@"; do ln -sf "$f" "GRIBFILE.${L:i/676%26:1}${L:i/26%26:1}${L:i%26:1}"; i=$((i + 1)); done; }
echo "geogrid: $GEOGRID  ungrib: $UNGRIB  metgrid: $METGRID  real.exe: $REALEXE"

fill() {  # fill() template out: substitute dates and paths
  local y0=${START:0:4} m0=${START:5:2} d0=${START:8:2} h0=${START:11:2}
  local y1=${END:0:4} m1=${END:5:2} d1=${END:8:2} h1=${END:11:2}
  sed -e "s|__START__|${START}:00:00|g" -e "s|__END__|${END}:00:00|g" -e "s|__GEOG__|$GEOG_DIR|" \
      -e "s|__GEOGRES1__|default|" -e "s|__GEOGRES2__|$GEOGRES|" -e "s|__GEOGRES3__|$GEOGRES|" \
      -e "s|__Y0__|$y0|g" -e "s|__M0__|$m0|g" -e "s|__D0__|$d0|g" -e "s|__H0__|$h0|g" \
      -e "s|__Y1__|$y1|g" -e "s|__M1__|$m1|g" -e "s|__D1__|$d1|g" -e "s|__H1__|$h1|g" $1 > $2
}

mkdir -p $CASE/wps $CASE/real $CASE/erf
cd $CASE/wps
fill $REPO/setup/namelist.wps namelist.wps
mkdir -p geogrid metgrid
ln -sf $WPS_DIR/geogrid/GEOGRID.TBL.ARW geogrid/GEOGRID.TBL 2>/dev/null || ln -sf $WPS_DIR/geogrid/GEOGRID.TBL geogrid/
[ -n "${GEOGRID_TBL:-}" ] && ln -sf $GEOGRID_TBL geogrid/GEOGRID.TBL     # custom table with schnaps_topo
ln -sf $WPS_DIR/metgrid/METGRID.TBL.ARW metgrid/METGRID.TBL 2>/dev/null || ln -sf $WPS_DIR/metgrid/METGRID.TBL metgrid/
ln -sf $WPS_DIR/ungrib/Variable_Tables/Vtable.raphrrr Vtable
ncdump -k geo_em.d03.nc >/dev/null 2>&1 || par 4 $GEOGRID
# Nests get met_em files only at the start time, so a full set is all hours of d01 plus one d02 and one d03
met_ok() { ls met_em.d03.* >/dev/null 2>&1 || return 1
           for f in met_em.d0*; do ncdump -k $f >/dev/null 2>&1 || { echo "unreadable: $f" >&2; return 1; }; done; }
if [ -n "${REAL_ONLY:-}" ] && met_ok; then
  echo "REAL_ONLY: reusing the existing met_em files"
else
  if [ -z "${REAL_ONLY:-}" ] || ! ls HRRR:* >/dev/null 2>&1; then
    rm -f GRIBFILE.* HRRR:*
    link_grib $CASE/hrrr/hrrr.*.grib2
    $UNGRIB
  else
    echo "REAL_ONLY: reusing ungrib output, rerunning metgrid"
  fi
  rm -f met_em.d0*
  par ${METGRID_NP:-1} $METGRID     # several ranks clash opening the first met_em file on Borah
  met_ok || { echo "metgrid wrote unreadable files" >&2; exit 1; }
fi
ls met_em.d0* | head -3

cd $CASE/real
fill $REPO/setup/namelist.input namelist.input
ln -sf $CASE/wps/met_em.d0* .
for f in $WRF_DIR/run/*.TBL $WRF_DIR/run/*_DATA $WRF_DIR/run/*.formatted; do [ -e $f ] && ln -sf $f .; done
ulimit -s unlimited          # real.exe segfaults in vertical interpolation with the default 8 MB stack
mpirun -np ${SLURM_NTASKS:-16} --bind-to core $REALEXE
tail -2 rsl.out.0000
cp wrfinput_d01 wrfinput_d02 wrfinput_d03 wrfbdy_d01 $CASE/erf/
ncdump -h $CASE/erf/wrfbdy_d01 | grep -E "QCLOUD_BXS|QICE_BXS|QRAIN_BXS" || echo "no moisture boundaries in wrfbdy_d01"
echo "ERF inputs ready in $CASE/erf. Next: sbatch --export=ALL run/erf_gpu.slurm"
