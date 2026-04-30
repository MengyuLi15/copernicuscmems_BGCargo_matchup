# Match BGC-Argo Profiles with CMEMS Ocean Colour Products

## Project Information

**Principal Investigator (PI)**  
Emanuele Organelli (CNR-ISMAR, Roma)

**Developer / Author**  
Mengyu Li (CNR-ISMAR, Roma)

**Contact**  
mengyuli@cnr.it

---

## Overview

This repository provides MATLAB functions to match BGC-Argo profile locations with daily CMEMS Level-4 ocean colour products, including chlorophyll-a (CHL) and diffuse attenuation coefficient at 490 nm (KD490).

The workflow is designed for robust satellite–in situ comparison and explicitly separates:

- measurement uncertainty from satellite retrieval,
- spatial variability within a 3×3 pixel window,
- combined uncertainty including representativeness effects.

---

## Functions

```matlab
OUT_CHL = match_cmems_chla_argo(argoLat, argoLon, argoTime, cmemsFolder, useParallel)

OUT_KD490 = match_cmems_kd490_argo(argoLat, argoLon, argoTime, cmemsFolder, useParallel)
```

---

## Input Arguments

### `argoLat`

- Numeric vector
- Latitude of Argo profiles, in degrees north

### `argoLon`

- Numeric vector
- Longitude of Argo profiles, in degrees east
- Accepts both:
  - [-180, 180]
  - [0, 360]

### `argoTime`

- `datetime` vector
- Profile timestamps
- Time of day is ignored because CMEMS products are daily

### `cmemsFolder`

- String / char
- Path to folder containing CMEMS daily files

### `useParallel` optional

- Default: `1`
- Controls execution mode:

| Value | Mode |
|---|---|
| 1 | Parallel, recommended |
| 0 | Serial |

---

## CMEMS Data Requirements

### Chlorophyll-a product

Each NetCDF file must follow the naming format:

```text
YYYYMMDD_cmems_obs-oc_glo_bgc-plankton_my_l4-gapfree-multi-4km_P1D.nc
```

Required variables:

| Variable | Description |
|---|---|
| `lat` | Latitude |
| `lon` | Longitude |
| `CHL` | Chlorophyll-a, mg m⁻³ |
| `CHL_uncertainty` | Relative uncertainty, % |
| `flags` | Quality flag |

---

### KD490 product

Each NetCDF file must follow the naming format:

```text
YYYYMMDD_cmems_obs-oc_glo_bgc-transp_my_l4-gapfree-multi-4km_P1D.nc
```

Required variables:

| Variable | Description |
|---|---|
| `lat` | Latitude |
| `lon` | Longitude |
| `KD490` | Diffuse attenuation coefficient at 490 nm, m⁻¹ |
| `KD490_uncertainty` | Relative uncertainty, % |
| `time` | Time |

---

## Processing Workflow

For each Argo profile:

1. Match to the corresponding CMEMS daily file using date
2. Find the nearest grid pixel
3. Extract a 3×3 window centered on the nearest pixel
4. Apply validity filtering
5. Compute:
   - 3×3 mean value
   - 3×3 spatial standard deviation
6. Propagate product uncertainty
7. Compute total uncertainty including spatial representativeness

---

## Parallel Implementation

When `useParallel = 1`:

- Profiles are grouped by date
- Each CMEMS file is read once per day
- A `parfor` loop processes all profiles from the same day

### Advantages

- Reduced I/O cost
- Improved performance for large datasets
- Deterministic results

---

## Output Tables

Each output table contains one row per Argo profile.

---

## Chlorophyll-a Output Variables

### Core variables

| Variable | Description |
|---|---|
| `CMEMS_CHL_1px` | CHL at nearest pixel |
| `CMEMS_CHL_mean_3x3` | 3×3 mean CHL |
| `CMEMS_CHL_sd_3x3` | Spatial variability of CHL |

### Uncertainty variables

| Variable | Description |
|---|---|
| `CMEMS_CHL_unc_1px_pct` | Pixel-level relative CHL uncertainty, % |
| `CMEMS_CHL_unc_abs_3x3` | Propagated absolute uncertainty of 3×3 mean CHL |
| `CMEMS_CHL_unc_pct_3x3` | Propagated relative uncertainty of 3×3 mean CHL, % |
| `CMEMS_CHL_unc_total_abs_3x3` | Total absolute uncertainty of 3×3 mean CHL |
| `CMEMS_CHL_unc_total_pct_3x3` | Total relative uncertainty of 3×3 mean CHL, % |
| `CMEMS_CHL_Nvalid_3x3` | Number of valid pixels in the 3×3 window |

---

## KD490 Output Variables

### Core variables

| Variable | Description |
|---|---|
| `CMEMS_KD490_1px` | KD490 at nearest pixel |
| `CMEMS_KD490_mean_3x3` | 3×3 mean KD490 |
| `CMEMS_KD490_sd_3x3` | Spatial variability of KD490 |

### Uncertainty variables

| Variable | Description |
|---|---|
| `CMEMS_KD490_unc_1px_pct` | Pixel-level relative KD490 uncertainty, % |
| `CMEMS_KD490_unc_abs_3x3` | Propagated absolute uncertainty of 3×3 mean KD490 |
| `CMEMS_KD490_unc_pct_3x3` | Propagated relative uncertainty of 3×3 mean KD490, % |
| `CMEMS_KD490_unc_total_abs_3x3` | Total absolute uncertainty of 3×3 mean KD490 |
| `CMEMS_KD490_unc_total_pct_3x3` | Total relative uncertainty of 3×3 mean KD490, % |
| `CMEMS_KD490_Nvalid_3x3` | Number of valid pixels in the 3×3 window |

---

## Uncertainty Calculation

For each valid pixel:

$$
\sigma_i = X_i \times \frac{U_i}{100}
$$

where:

- $X_i$ is either CHL or KD490
- $U_i$ is the corresponding product uncertainty in percent

The propagated uncertainty of the 3×3 mean is:

$$
\sigma_{\mathrm{mean}} = \frac{\sqrt{\sum_i \sigma_i^2}}{N}
$$

The total uncertainty is:

$$
\sigma_{\mathrm{total}} = \sqrt{\sigma_{\mathrm{mean}}^2 + \left(\frac{SD}{\sqrt{N}}\right)^2}
$$

where:

- $N$ is the number of valid pixels
- $SD$ is the spatial standard deviation within the 3×3 window

---

## Interpretation of Uncertainty Terms

### Pixel-level uncertainty

Examples:

```text
CMEMS_CHL_unc_1px_pct
CMEMS_KD490_unc_1px_pct
```

This is the relative uncertainty provided by the CMEMS product for the nearest grid cell.

---

### Propagated uncertainty, recommended for error bars

Examples:

```text
CMEMS_CHL_unc_abs_3x3
CMEMS_KD490_unc_abs_3x3
```

This represents the measurement uncertainty of the 3×3 window-averaged matchup value, estimated using the standard law of propagation of uncertainties.

---

### Spatial variability

Examples:

```text
CMEMS_CHL_sd_3x3
CMEMS_KD490_sd_3x3
```

This represents subpixel heterogeneity within the 3×3 window.

It is not measurement uncertainty.

---

### Total uncertainty

Examples:

```text
CMEMS_CHL_unc_total_abs_3x3
CMEMS_KD490_unc_total_abs_3x3
```

This combines propagated retrieval uncertainty and a simple spatial representativeness term.

---

## Recommended Usage

### For BGC-Argo vs CMEMS CHL comparison

| Purpose | Variable |
|---|---|
| X value | `CMEMS_CHL_mean_3x3` |
| Error bar, recommended | `CMEMS_CHL_unc_abs_3x3` |
| Conservative error bar | `CMEMS_CHL_unc_total_abs_3x3` |
| Spatial variability diagnostic | `CMEMS_CHL_sd_3x3` |

---

### For BGC-Argo vs CMEMS KD490 comparison

| Purpose | Variable |
|---|---|
| X value | `CMEMS_KD490_mean_3x3` |
| Error bar, recommended | `CMEMS_KD490_unc_abs_3x3` |
| Conservative error bar | `CMEMS_KD490_unc_total_abs_3x3` |
| Spatial variability diagnostic | `CMEMS_KD490_sd_3x3` |

---

## Example

```matlab
argoLat = [
    25.0
    28.5
    31.0
    33.0
    27.0
];

argoLon = [
   -60.0
   -50.0
   -45.0
   -40.0
   -55.0
];

argoTime = datetime([
    2020 01 01 10 32 15
    2020 01 02 13 05 42
    2020 01 03 09 47 30
    2020 01 04 15 21 10
    2020 01 05 11 58 05
]);

OUT_CHL = match_cmems_chla_argo(argoLat, argoLon, argoTime, chlFolder);

OUT_KD490 = match_cmems_kd490_argo(argoLat, argoLon, argoTime, kd490Folder);
```

---

## Example Plot

```matlab
scatter(OUT_CHL.CMEMS_CHL_mean_3x3, Argo_CHL)
hold on
errorbar(OUT_CHL.CMEMS_CHL_mean_3x3, Argo_CHL, ...
         OUT_CHL.CMEMS_CHL_unc_abs_3x3, '.')
```

For KD490:

```matlab
scatter(OUT_KD490.CMEMS_KD490_mean_3x3, Argo_KD490)
hold on
errorbar(OUT_KD490.CMEMS_KD490_mean_3x3, Argo_KD490, ...
         OUT_KD490.CMEMS_KD490_unc_abs_3x3, '.')
```

---

## Notes

- 3×3 averaging reduces independent retrieval uncertainty approximately by √N.
- Spatial variability is typically small in open-ocean gyres but can increase in productive or coastal regions.
- Quality flags can be used for stricter filtering if needed.
- The propagated uncertainty and spatial variability should be interpreted separately unless the total uncertainty is explicitly used.

---

## Scientific Context

This workflow follows standard practices in ocean colour validation:

- nearest-pixel spatial matching,
- 3×3 spatial averaging,
- uncertainty propagation,
- separation of measurement uncertainty and representativeness error.

---

## Author Notes

- Designed for BGC-Argo matchup analysis.
- Suitable for global-scale satellite–in situ comparison.
- Optimized for CMEMS Level-4 ocean colour products.
- Currently supports CHL and KD490 products.