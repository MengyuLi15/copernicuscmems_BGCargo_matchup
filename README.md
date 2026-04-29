# Match BGC-Argo Profiles with CMEMS Chlorophyll-a Product

## Overview

This function matches BGC-Argo profile locations with daily CMEMS Level-4 chlorophyll-a (CHL) products and computes spatially averaged values and associated uncertainties.

The workflow is designed for robust satellite–in situ comparison and explicitly separates:

- measurement uncertainty (from satellite retrieval),
- spatial variability (within a 3×3 pixel window),
- combined uncertainty including representativeness effects.

---

## Function

```matlab
OUT = match_cmems_chla_argo(argoLat, argoLon, argoTime, cmemsFolder, useParallel)
````

---

## Input Arguments

### `argoLat`

* Numeric vector
* Latitude of Argo profiles (degrees north)

### `argoLon`

* Numeric vector
* Longitude of Argo profiles (degrees east)
* Accepts both:

  * [-180, 180]
  * [0, 360]

### `argoTime`

* `datetime` vector
* Profile timestamps (time of day is ignored for matching)

### `cmemsFolder`

* String / char
* Path to folder containing CMEMS daily files

### `useParallel` (optional)

* Default: `1`
* Controls execution mode:

| Value | Mode                   |
| ----- | ---------------------- |
| 1     | Parallel (recommended) |
| 0     | Serial                 |

---

## CMEMS Data Requirements

Each NetCDF file must follow naming:

```
YYYYMMDD_cmems_obs-oc_glo_bgc-plankton_my_l4-gapfree-multi-4km_P1D.nc
```

Required variables:

| Variable          | Description              |
| ----------------- | ------------------------ |
| `lat`             | Latitude                 |
| `lon`             | Longitude                |
| `CHL`             | Chlorophyll-a (mg m⁻³)   |
| `CHL_uncertainty` | Relative uncertainty (%) |
| `flags`           | Quality flag             |

---

## Processing Workflow

For each Argo profile:

1. Match to CMEMS daily file using date
2. Find nearest grid pixel
3. Extract 3×3 window
4. Apply validity filtering
5. Compute:

   * mean CHL
   * spatial standard deviation
6. Propagate uncertainty
7. Compute total uncertainty

---

## Parallel Implementation

When `useParallel = 1`:

* Profiles are grouped by date
* Each CMEMS file is read **once per day**
* A `parfor` loop processes all profiles of that day

### Advantages

* Reduced I/O cost
* Improved performance
* Deterministic results

---

## Output Table

Each row corresponds to one Argo profile.

### Core Variables

| Variable             | Description          |
| -------------------- | -------------------- |
| `CMEMS_CHL_1px`      | CHL at nearest pixel |
| `CMEMS_CHL_mean_3x3` | 3×3 mean CHL         |
| `CMEMS_CHL_sd_3x3`   | Spatial variability  |

---

### Uncertainty Variables

#### 1. Pixel-level uncertainty

```
CMEMS_CHL_unc_1px_pct
```

* From CMEMS product
* Relative (%)

---

#### 2. Propagated uncertainty (recommended)

```
CMEMS_CHL_unc_abs_3x3
CMEMS_CHL_unc_pct_3x3
```

Computed using:

$$
\sigma_i = C_i \times \frac{U_i}{100}
$$

$$
\sigma_{\mathrm{mean}} = \frac{\sqrt{\sum_i \sigma_i^2}}{N}
$$

---

#### 3. Spatial variability

```
CMEMS_CHL_sd_3x3
```

* Represents subpixel heterogeneity
* **Not measurement uncertainty**

---

#### 4. Total uncertainty (optional)

```
CMEMS_CHL_unc_total_abs_3x3
CMEMS_CHL_unc_total_pct_3x3
```

$$
\sigma_{\mathrm{total}} = \sqrt{\sigma_{\mathrm{mean}}^2 + \left(\frac{SD}{\sqrt{N}}\right)^2}
$$

Includes:

* retrieval uncertainty
* representativeness error

---

## Recommended Usage

### For Argo vs CMEMS comparison

| Purpose                 | Variable                      |
| ----------------------- | ----------------------------- |
| X value                 | `CMEMS_CHL_mean_3x3`          |
| Error bar (recommended) | `CMEMS_CHL_unc_abs_3x3`       |
| Conservative error      | `CMEMS_CHL_unc_total_abs_3x3` |
| Variability analysis    | `CMEMS_CHL_sd_3x3`            |

---

## Notes

* 3×3 averaging reduces uncertainty by ~√N
* Spatial variability is typically small in open ocean (e.g., gyres)
* Quality flags can be used for stricter filtering if needed

---

## Example

```matlab
OUT = match_cmems_chla_argo(lat, lon, time, folder);

scatter(OUT.CMEMS_CHL_mean_3x3, Argo_CHL)
errorbar(OUT.CMEMS_CHL_mean_3x3, Argo_CHL, ...
         OUT.CMEMS_CHL_unc_abs_3x3, '.')
```

---

## Scientific Context

This workflow follows standard practices in ocean color validation:

* spatial averaging (3×3 window)
* uncertainty propagation
* separation of measurement vs representativeness error

---

## Author Notes

* Designed for BGC-Argo matchup analysis
* Suitable for global-scale studies
* Optimized for CMEMS L4 products

```
