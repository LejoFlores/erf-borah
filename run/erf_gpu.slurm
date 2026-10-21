#!/bin/bash
#SBATCH -J erf-drycreek-gpu
#SBATCH -p gpu-l40
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 8
#SBATCH --gres=gpu:1
#SBATCH -t 12:00:00
#SBATCH -o erf-drycreek-gpu-%j.log
# ERF at Dry Creek on one L40S, from the files run/wps_real.slurm put in $CASE/erf.
#   CASE=/bsuscratch/$USER/erf/cases/drycreek_dec2015 START="2015-12-18 18:00:00" END="2015-12-19 06:00:00" \
#   sbatch --export=ALL run/erf_gpu.slurm
# CPU instead: EXE=$ERF_ROOT/install-cpu/... sbatch -p bsudfq --gres=none -n 48 ... (same script)
# Restart: RESTART=chk00123 (a checkpoint directory in $CASE/erf) sbatch --export=ALL run/erf_gpu.slurm
set -euo pipefail
REPO=$SLURM_SUBMIT_DIR
source $REPO/build/env_gpu.sh
: ${CASE:?set CASE}
START=${START:-2015-12-18 18:00:00}; END=${END:-2015-12-19 06:00:00}
EXE=${EXE:-$(find $ERF_ROOT/install-gpu $ERF_ROOT/build-gpu -name 'erf_exec' -type f 2>/dev/null | head -1)}
cd $CASE/erf
sed -e "s|__START__|$START|" -e "s|__END__|$END|" $REPO/setup/inputs_drycreek > inputs
[ -n "${RESTART:-}" ] && echo "erf.restart = $RESTART" >> inputs
cp $REPO/setup/namelist.erf .
cp $ERF_ROOT/data/NoahmpTable.TBL $ERF_ROOT/data/rrtmgp-*.nc .
ulimit -s unlimited          # Noah-MP's Fortran driver, as for CLM in ParFlow
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv
echo "exe: $EXE"
srun $EXE inputs amrex.the_arena_init_size=0 2>&1 | tee erf-$SLURM_JOB_ID.out | grep -E "STEP|Writing|error|Error" | tail -40
