#!/bin/bash
# Compile ERF with MPI + NetCDF + Noah-MP + RRTMGP. Usage: compile.sh cpu|gpu
# Run on a COMPUTE node (build_*.slurm or dev-session): Borah compute nodes have an older glibc
# than the login node, so login-node binaries can fail there. No network needed.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TARGET=${1:-cpu}
if [ "$TARGET" = gpu ]; then source $HERE/env_gpu.sh; else source $HERE/env_gcc12.sh; fi
NP=${SLURM_CPUS_PER_TASK:-8}

# ERF's NetCDF I/O needs a parallel (MPI) netcdf-c: check before a long build
if [ ! -f "$(nc-config --includedir)/netcdf_par.h" ]; then
  echo "netcdf-c at $(nc-config --prefix) is not the parallel build (no netcdf_par.h); load the openmpi netcdf-c module" >&2
  exit 1
fi

# netcdf-fortran (once, shared by both builds). The CPU and GPU jobs may run at the same time,
# so the first one builds it under a lock, in its own folder, and the other waits and reuses it.
mkdir -p $ERF_DEPS
(
  flock 9
  if [ ! -f $ERF_DEPS/lib/libnetcdff.so ]; then
    NFB=$ERF_SRC/netcdf-fortran-build-${SLURM_JOB_ID:-$$}
    rm -rf $NFB && mkdir -p $NFB && cd $NFB
    cmake $ERF_SRC/netcdf-fortran-$NETCDF_F_VER -DCMAKE_INSTALL_PREFIX=$ERF_DEPS \
          -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_BUILD_TYPE=Release -DENABLE_TESTS=OFF \
          -DCMAKE_C_COMPILER=mpicc -DCMAKE_Fortran_COMPILER=mpifort
    make -j $NP && make install
    cd $ERF_SRC && rm -rf $NFB
  fi
) 9>$ERF_DEPS/.netcdf-fortran.lock

BUILD=$ERF_ROOT/build-$TARGET
INSTALL=$ERF_ROOT/install-$TARGET
GPU_FLAGS=""
if [ "$TARGET" = gpu ]; then
  GPU_FLAGS="-DERF_ENABLE_CUDA=ON -DAMReX_CUDA_ARCH=$AMREX_CUDA_ARCH -DCMAKE_CUDA_HOST_COMPILER=$CUDAHOSTCXX"
fi
rm -rf $BUILD
cmake -S $ERF_SRC/ERF -B $BUILD \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$INSTALL \
  -DCMAKE_C_COMPILER=mpicc -DCMAKE_CXX_COMPILER=mpicxx -DCMAKE_Fortran_COMPILER=mpifort \
  -DERF_ENABLE_MPI=ON -DERF_ENABLE_NETCDF=ON -DERF_ENABLE_HDF5=OFF \
  -DERF_ENABLE_NOAHMP=ON -DERF_ENABLE_RRTMGP=ON -DERF_ENABLE_TESTS=OFF $GPU_FLAGS
cmake --build $BUILD -j $NP
cmake --install $BUILD

# Run-time data every case needs: Noah-MP table, sample namelist, RRTMGP coefficients
DATA=$ERF_ROOT/data; mkdir -p $DATA
cp $ERF_SRC/ERF/Submodules/Noah-MP/parameters/NoahmpTable.TBL $DATA/
cp $ERF_SRC/ERF/Docs/sphinx_doc/namelist.erf $DATA/namelist.erf.sample
cp $ERF_SRC/ERF/Submodules/RRTMGP/rrtmgp/data/rrtmgp-data-*-2018-12-04.nc $DATA/
cp $ERF_SRC/ERF/Submodules/RRTMGP/extensions/cloud_optics/rrtmgp-cloud-optics-coeffs-*.nc $DATA/

EXE=$(ls $INSTALL/bin/erf_exec 2>/dev/null || find $INSTALL $BUILD -name 'erf_exec' -type f | head -1)
{ echo "date: $(date -Is)  host: $(hostname)  target: $TARGET"
  echo "ERF: $(cd $ERF_SRC/ERF && git rev-parse HEAD)"
  echo "exe: $EXE"; module list -t 2>&1 | tr '\n' ' '; echo
  ldd $EXE | grep -iE "netcdf|hdf5|cuda|mpi" ; } | tee $ERF_ROOT/build-info-$TARGET.txt
