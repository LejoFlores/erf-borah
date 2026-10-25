#!/bin/bash
#SBATCH -J erf-build-gpu
#SBATCH -p bsudfq
#SBATCH -N 1
#SBATCH --exclusive          # whole node: shared CPU nodes ran MPI jobs 10-20x slower
#SBATCH -n 1
#SBATCH -c 16
#SBATCH -t 04:00:00
#SBATCH -o erf-build-gpu-%j.log
# Compiling for the GPU needs nvcc, not a GPU, so this runs on a CPU node.
# Needs CUDA 12.4: by default the copy inside SCHNAPS's NVHPC 24.5 install (see env_gpu.sh).
# Other GPUs: ERF_GPU=v100 (or a30) sbatch --export=ALL build/build_gpu.slurm -> $ERF_ROOT/install-gpu-v100
bash $SLURM_SUBMIT_DIR/build/compile.sh gpu
