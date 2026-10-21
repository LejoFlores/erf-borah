# Source me: the GCC 12 stack plus CUDA 12.4 for the GPU build and GPU runs.
# CUDA comes from the NVHPC 24.5 SDK that the SCHNAPS GPU build already installed
# ($SCHNAPS_ROOT/nvhpc); set CUDA_HOME yourself to use another CUDA 12.x <= 12.4.
HERE_ENV=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source $HERE_ENV/env_gcc12.sh
SCHNAPS_ROOT=${SCHNAPS_ROOT:-/bsuscratch/$USER/schnaps}
export CUDA_HOME=${CUDA_HOME:-$SCHNAPS_ROOT/nvhpc/Linux_x86_64/$NVHPC_VER/cuda/$CUDA_VER}
export CUDACXX=$CUDA_HOME/bin/nvcc
export CUDAHOSTCXX=$(command -v g++)      # GCC 12 host compiler; CUDA 12.4 supports up to GCC 13
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export AMREX_CUDA_ARCH
