#!/bin/bash
#SBATCH -J erf-build-cpu
#SBATCH -p bsudfq
#SBATCH -N 1
#SBATCH --exclusive          # whole node: shared CPU nodes ran MPI jobs 10-20x slower
#SBATCH -n 1
#SBATCH -c 16
#SBATCH -t 03:00:00
#SBATCH -o erf-build-cpu-%j.log
# Run build/fetch_sources.sh on the login node first, then: sbatch build/build_cpu.slurm
bash $SLURM_SUBMIT_DIR/build/compile.sh cpu
