# ERF on Borah: Dry Creek Dec 2015, compared with SCHNAPS at 50 m

These scripts build ERF (github.com/erf-model/ERF) on Borah and run it on the same storm, forcing and grids as the SCHNAPS 50 m case (schnaps-borah `setup/drycreek/drycreek_50m_setup.yml`).

The chain is:

1. HRRR from AWS
2. WPS
3. real.exe, which writes `wrfinput_d01`, `wrfinput_d02`, `wrfinput_d03` and `wrfbdy_d01`
4. ERF, with a 1 km domain plus 250 m and 50 m static refinement levels

Everything installs under `/bsuscratch/$USER/erf` (override with `ERF_ROOT`).

## Steps

```bash
git clone https://github.com/LejoFlores/erf-borah ~/erf-borah && cd ~/erf-borah
# 1. Login node: sources (ERF at a pinned commit + AMReX, Noah-MP, RRTMGP, EKAT; netcdf-fortran)
bash build/fetch_sources.sh
# 2. Compute node: builds (CPU ~1 h; GPU needs SCHNAPS's NVHPC 24.5 for CUDA 12.4, see env_gpu.sh)
sbatch build/build_cpu.slurm
sbatch build/build_gpu.slurm
# 3. HRRR for WPS (login node). The same 6 h forecasts as the SCHNAPS forcing.
#    Each hour is ~420 MB uncropped; with wgrib2 on PATH, --bbox crops it to a few MB.
export ERF_CASE=/bsuscratch/$USER/erf/cases/drycreek_dec2015
python setup/hrrr_wps.py --start 2015-12-18T18 --end 2015-12-19T06 --out $ERF_CASE/hrrr --bbox 42.7 -117.6 44.7 -114.8
# 4. Optional but recommended: SCHNAPS's 30 m terrain for the 250 m and 50 m levels (see below).
#    Needs numpy, netCDF4 and pyproj, e.g. the schnaps-forcing conda env (hrrr_wps.py needs only Python 3)
# 5. WPS + real.exe
ERF_GEOG_DIR=/path/to/WPS_GEOG ERF_START=2015-12-18_18 ERF_END=2015-12-19_06 sbatch --export=ALL run/wps_real.slurm
# 6. ERF on one L40S
ERF_START="2015-12-18 18:00:00" ERF_END="2015-12-19 06:00:00" sbatch --export=ALL run/erf_gpu.slurm
```

The defaults cover the wettest 12 h, the same window as the SCHNAPS d01 smoke test. For the full storm, use `--start 2015-12-18T00 --end 2015-12-23T00` and the matching ERF_START/ERF_END values.

## Files

| File | What it does |
| --- | --- |
| `build/versions.sh` | Pinned versions: ERF commit 5fa15bd (2026-10-08), netcdf-fortran 4.6.1, CUDA arch 8.9 (L40S) |
| `build/env_gcc12.sh`, `build/env_gpu.sh` | Module environment (GCC 12.1, OpenMPI 4.1.3, parallel netcdf-c 4.10, HDF5 1.14.6, CMake 3.25). The GPU build adds CUDA 12.4 from SCHNAPS's NVHPC 24.5 install |
| `build/fetch_sources.sh` | Login node: clones sources |
| `build/compile.sh`, `build/build_{cpu,gpu}.slurm` | Compute node: builds netcdf-fortran and then ERF (MPI, NetCDF, Noah-MP, RRTMGP). Copies the Noah-MP table and RRTMGP data to `$ERF_ROOT/data` and writes `build-info-*.txt` |
| `setup/hrrr_wps.py` | Fetches only the HRRR GRIB records that WPS's `Vtable.raphrrr` uses (byte ranges). Native levels and surface fields come from wrfnat; soil fields come from wrfprs, because 2015 wrfnat has none |
| `setup/namelist.wps`, `setup/namelist.input` | WPS and real.exe templates for the three nests |
| `setup/schnaps_topo_to_wps.py` | Converts the SCHNAPS terrain into a WPS static dataset |
| `setup/inputs_drycreek`, `setup/namelist.erf` | ERF inputs and Noah-MP options |
| `run/wps_real.slurm` | Runs geogrid, ungrib, metgrid and real.exe. Uses Borah's Intel `wps/4.6.0` and `wrf/4.7.1` modules unless you set `WPS_DIR` and `WRF_DIR` to your own install |
| `run/erf_gpu.slurm` | Runs ERF on one L40S. `ERF_RESTART=chkNNNNN` restarts from a checkpoint |
| `analysis/erf_precip.py` | After a run: surface precipitation (rain/snow/graupel accumulations, lowest-cell height) from every plotfile and level into one small NetCDF, plus the WPS grids' lat/lon. Needs only numpy and netCDF4: `python analysis/erf_precip.py $ERF_CASE/erf erf_precip.nc` |

## Grids

| | SCHNAPS | ERF (this setup) |
| --- | --- | --- |
| Outer | d01: 1 km, 123 x 123, oblique stereographic centred 43.7 N 116.2 W | Level 0: 1 km, 123 x 123, Lambert true at 43.7 N, same centre |
| 250 m | d02: 111 x 112 (27.7 x 28.1 km) | Level 1: 128 x 136 (32 x 34 km); covers the SCHNAPS d02 |
| 50 m | d03: 227 x 268 (11.3 x 13.4 km) | Level 2: 240 x 280 (12 x 14 km); covers the SCHNAPS d03 |
| Vertical | SCHNAPS levels | 60 levels, model top at 50 hPa |

The ERF nests are a little larger than SCHNAPS's. Their sides are snapped to whole parent cells and to multiples of 8 cells, which AMReX requires. ERF's level boxes in `inputs_drycreek` and the WPS d02 and d03 in `namelist.wps` describe the same areas. Change them together.

## Terrain and land cover

WPS's default terrain is about 1 km, which would make the 50 m level much smoother than SCHNAPS's Copernicus 30 m terrain. `schnaps_topo_to_wps.py` resamples the SCHNAPS domain terrain to a regular lat-lon WPS dataset at 0.0003° (about 30 m). It takes each point from the finest SCHNAPS domain that covers it.

Running it on the domain files gave 1,272 x 968 points from 779 to 2,304 m. To use it:

1. Copy the output into `ERF_GEOG_DIR`.
2. Add the two lines the script prints to the `HGT_M` entry of a copy of `GEOGRID.TBL`.
3. Run WPS with `ERF_GEOGRID_TBL=<that copy> ERF_GEOGRES=schnaps_topo+default`.

Land cover still comes from WPS's MODIS classes. SCHNAPS uses ESA WorldCover, so that remains a known difference.

## Things to know

- **Precipitation at the boundaries.**
  - ERF brings HRRR cloud water and cloud ice in at the lateral boundaries (`use_wrf_bdy_qc_qi`). It does not bring in rain, snow or graupel.
  - Precipitation therefore has to form inside the 1 km domain. Compare only inside the 250 m and 50 m levels, well away from the edge.
  - `wps_real.slurm` prints whether `wrfbdy_d01` holds the moisture fields.
- **Turbulence.**
  - The draft uses YSU at 1 km and 250 m, and Deardorff LES at 50 m.
  - For a strict match with SCHNAPS (YSU everywhere), set `erf.pbl_type = YSU YSU YSU` and `erf.les_type = None None None`.
- **Precipitation phase.**
  - Noah-MP takes rain, snow and graupel from Morrison (`PCP_PARTITION_OPTION = 4`), as SCHNAPS does.
  - In ERF's Morrison output, `rain_accum` is total precipitation. `snow_accum` and `graup_accum` are parts of it.
- **Cost.**
  - The 50 m level is about 4 million cells at a 0.25 s step.
  - Start with the 12 h window. Check the time per step in the log before committing to the full storm.

## What was checked in the cloud (2026-10-20)

- **HRRR records.** I downloaded and decoded one hour (2015-12-18 18Z, 6 h lead). Every field `Vtable.raphrrr` needs is present, with matching GRIB2 codes. That covers the 50 native levels of height, pressure, temperature, humidity, winds and qc/qr/qi/qs/qg, plus the surface fields and the 9 soil levels. Mean sea-level pressure is the exception: HRRR names it PRMSL rather than MSLMA, which real.exe doesn't need because surface pressure is present.
- **Terrain converter.** It ran on the SCHNAPS domain files.
- **ERF CPU build.** It builds with MPI + NetCDF + Noah-MP + RRTMGP: 16 min on 4 cores, using the same CMake options as `compile.sh`. A 20-step smoke test with Morrison + RRTMGP on the idealized ridge ran on 4 MPI ranks in 27 s. RRTMGP needs `erf.rad_t_sfc` and the gas mixing ratios, which are now in `inputs_drycreek`. ERF also aborts if a key appears twice in the inputs. ERF's NetCDF I/O needs the parallel netcdf-c, and Noah-MP needs netcdf-fortran. Both are handled in `compile.sh`.
- **Not yet run.** Nothing has run on Borah yet: WPS, real.exe, the GPU build and the ERF run itself.
