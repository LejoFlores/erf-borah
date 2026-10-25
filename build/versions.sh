# Pinned versions for the ERF build (sourced by the other scripts).
ERF_COMMIT=5fa15bdc5e7feecd00a6a0e0b775ebce0b690e81   # ERF development, 2026-10-08 (built and tested in the cloud)
NETCDF_F_VER=4.6.1                                   # Noah-MP needs NetCDF-Fortran; no GCC-12 module matches netcdf-c 4.10
# GPU architecture, by ERF_GPU (build/build_gpu.slurm, run/erf_gpu.slurm): l40s (default), v100, a30.
# The L40S is slow in double precision (~1.4 TFLOPS FP64); V100 ~7.8 and A30 ~5.2.
case ${ERF_GPU:-l40s} in
  l40s) AMREX_CUDA_ARCH=8.9; KOKKOS_ARCH=ADA89 ;;       # gpu-l40 partition (L40S / L40)
  a30)  AMREX_CUDA_ARCH=8.0; KOKKOS_ARCH=AMPERE80 ;;    # shortgpu-a30 partition
  v100) AMREX_CUDA_ARCH=7.0; KOKKOS_ARCH=VOLTA70 ;;     # gpu-v100 partition
  *) echo "ERF_GPU=$ERF_GPU: use l40s, v100 or a30" >&2; return 1 2>/dev/null || exit 1 ;;
esac
CMAKE_VER=3.31.6                                     # pip-installed: Borah's CMake 3.25 lacks CUDA C++20
NVHPC_VER=24.5                                       # only for its bundled CUDA 12.4 (matches the L40S driver 550)
CUDA_VER=12.4
