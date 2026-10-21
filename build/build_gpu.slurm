#!/bin/bash
#SBATCH -J erf-build-gpu
#SBATCH -p bsudfq
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 16
#SBATCH -t 04:00:00
#SBATCH -o erf-build-gpu-%j.log
# Compiling for the GPU needs nvcc, not a GPU, so this runs on a CPU node.
# Needs CUDA 12.4: by default the copy inside SCHNAPS's NVHPC 24.5 install (see env_gpu.sh).
bash $SLURM_SUBMIT_DIR/build/compile.sh gpu
