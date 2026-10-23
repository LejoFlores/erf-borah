# Pinned versions for the ERF build (sourced by the other scripts).
ERF_COMMIT=5fa15bdc5e7feecd00a6a0e0b775ebce0b690e81   # ERF development, 2026-10-08 (built and tested in the cloud)
NETCDF_F_VER=4.6.1                                   # Noah-MP needs NetCDF-Fortran; no GCC-12 module matches netcdf-c 4.10
AMREX_CUDA_ARCH=8.9                                  # L40S / L40. A30 nodes are 8.0
KOKKOS_ARCH=ADA89                                    # same GPU for Kokkos (RRTMGP); AMPERE80 for A30
CMAKE_VER=3.31.6                                     # pip-installed: Borah's CMake 3.25 lacks CUDA C++20
NVHPC_VER=24.5                                       # only for its bundled CUDA 12.4 (matches the L40S driver 550)
CUDA_VER=12.4
