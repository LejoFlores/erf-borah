#!/bin/bash
# Run on the Borah LOGIN node (network, no compiling): ERF at the pinned commit with the
# submodules the Dry Creek setup needs (AMReX, Noah-MP, RRTMGP + EKAT/Kokkos), and netcdf-fortran.
# Then compile on a compute node: sbatch build/build_cpu.slurm  (and/or build/build_gpu.slurm)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ERF_NO_MODULES=1 source $HERE/versions.sh
ERF_ROOT=${ERF_ROOT:-/bsuscratch/$USER/erf}; ERF_SRC=$ERF_ROOT/src
mkdir -p $ERF_SRC && cd $ERF_SRC
if [ ! -d ERF ]; then
  git clone https://github.com/erf-model/ERF.git ERF
fi
cd ERF
git fetch origin && git checkout $ERF_COMMIT
git submodule update --init Submodules/AMReX Submodules/Noah-MP Submodules/RRTMGP
git submodule update --init --recursive Submodules/ekat
cd $ERF_SRC
if [ ! -d netcdf-fortran-$NETCDF_F_VER ]; then
  curl -fsSL https://github.com/Unidata/netcdf-fortran/archive/refs/tags/v$NETCDF_F_VER.tar.gz | tar xz
fi
# CMake from PyPI (manylinux2014 wheel, runs on the compute nodes' older glibc)
if [ ! -x $ERF_ROOT/cmake-venv/bin/cmake ]; then
  python3 -m venv $ERF_ROOT/cmake-venv
  $ERF_ROOT/cmake-venv/bin/pip install -q "cmake==$CMAKE_VER"
fi
echo "CMake: $($ERF_ROOT/cmake-venv/bin/cmake --version | head -1)"
echo "Sources in $ERF_SRC (ERF $(cd ERF && git rev-parse --short HEAD))."
echo "Next: sbatch $HERE/build_cpu.slurm   and/or   sbatch $HERE/build_gpu.slurm"
