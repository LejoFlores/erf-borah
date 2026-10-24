#!/bin/bash
#SBATCH -J erf-drycreek-gpu
#SBATCH -p gpu-l40
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 8
#SBATCH --gres=gpu:1
#SBATCH -t 12:00:00
#SBATCH -o erf-drycreek-gpu-%j.log
# ERF at Dry Creek on one L40S, from the files run/wps_real.slurm put in $ERF_CASE/erf.
#   ERF_CASE=/bsuscratch/$USER/erf/cases/drycreek_dec2015 ERF_START="2015-12-18 18:00:00" ERF_END="2015-12-19 06:00:00" \
#   sbatch --export=ALL run/erf_gpu.slurm
# CPU instead: ERF_EXE=$ERF_ROOT/install-cpu/... sbatch -p bsudfq --gres=none -n 48 ... (same script)
# Restart: ERF_RESTART=chk00123 (a checkpoint directory in $ERF_CASE/erf) sbatch --export=ALL run/erf_gpu.slurm
set -euo pipefail
# Variables are ERF_-prefixed so other models' jobs (SCHNAPS, WRF, ParFlow use CASE, START, ...) can't leak in.
for p in CASE:ERF_CASE START:ERF_START END:ERF_END EXE:ERF_EXE RESTART:ERF_RESTART; do o=${p%%:*} n=${p#*:}
  [ -n "${!o:-}" ] && [ -z "${!n:-}" ] && echo "note: $o is set but ignored here; this script reads $n"; done
REPO=$SLURM_SUBMIT_DIR
source $REPO/build/env_gpu.sh
: ${ERF_CASE:?set ERF_CASE}
ERF_START=${ERF_START:-2015-12-18 18:00:00}; ERF_END=${ERF_END:-2015-12-19 06:00:00}
ERF_EXE=${ERF_EXE:-$(find $ERF_ROOT/install-gpu $ERF_ROOT/build-gpu -name 'erf_exec' -type f 2>/dev/null | head -1)}
cd $ERF_CASE/erf
sed -e "s|__START__|$ERF_START|" -e "s|__END__|$ERF_END|" $REPO/setup/inputs_drycreek > inputs
[ -n "${ERF_RESTART:-}" ] && echo "erf.restart = $ERF_RESTART" >> inputs
cp $REPO/setup/namelist.erf .
cp $ERF_ROOT/data/NoahmpTable.TBL $ERF_ROOT/data/rrtmgp-*.nc .
ulimit -s unlimited          # Noah-MP's Fortran driver, as for CLM in ParFlow
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv || echo "nvidia-smi not permitted here; carrying on"   # informational only
echo "exe: $ERF_EXE"
echo "CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-unset}  $(ls /dev/nvidia[0-9]* 2>/dev/null | tr '\n' ' ')"
# mpirun, not srun: an srun step on Borah doesn't see the job's GPU (CUDA error 100, "no CUDA-capable
# device"), and Borah's OpenMPI has no Slurm PMI anyway. The SCHNAPS GPU jobs launch the same way.
mpirun -np ${SLURM_NTASKS:-1} --bind-to none $ERF_EXE inputs amrex.the_arena_init_size=0 2>&1 | tee erf-$SLURM_JOB_ID.out | grep -E "STEP|Writing|error|Error" | tail -40
