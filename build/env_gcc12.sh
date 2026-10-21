# Source me: GCC 12.1 + OpenMPI 4.1.3 stack for building and running ERF on Borah (same as SCHNAPS/ParFlow).
HERE_ENV=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source $HERE_ENV/versions.sh
if command -v module >/dev/null 2>&1 && [ -z "${ERF_NO_MODULES:-}" ]; then
  module purge
  module load slurm borah-base borah-libraries gcc/12.1.0 openmpi/4.1.3/gcc/12.1.0 \
      hdf5/1.14.6/openmpi/4.1.3/gcc/12.1.0 netcdf-c/4.10.0/openmpi/4.1.3/gcc/12.1.0 \
      cmake/3.25.0/gcc/12.1.0
fi
export ERF_ROOT=${ERF_ROOT:-/bsuscratch/$USER/erf}
export ERF_SRC=$ERF_ROOT/src
export ERF_DEPS=$ERF_ROOT/deps            # netcdf-fortran built here
NCC=$(nc-config --prefix)
export CMAKE_PREFIX_PATH=$ERF_DEPS:$NCC${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}
export PKG_CONFIG_PATH=$ERF_DEPS/lib/pkgconfig:$NCC/lib/pkgconfig:$NCC/lib64/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
export LD_LIBRARY_PATH=$ERF_DEPS/lib:$NCC/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export PATH=$ERF_DEPS/bin:$PATH
export CC=mpicc CXX=mpicxx FC=mpifort
