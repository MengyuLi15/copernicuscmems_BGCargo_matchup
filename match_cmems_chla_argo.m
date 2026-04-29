function OUT = match_cmems_chla_argo(argoLat, argoLon, argoTime, cmemsFolder, useParallel)
%MATCH_CMEMS_CHLA_ARGO Match BGC-Argo locations with daily CMEMS CHL data.
%
% This function matches BGC-Argo profile locations and dates with the daily
% CMEMS global ocean colour chlorophyll-a product:
%
%   YYYYMMDD_cmems_obs-oc_glo_bgc-plankton_my_l4-gapfree-multi-4km_P1D.nc
%
% For each Argo profile, the function:
%   1. identifies the CMEMS daily file corresponding to the Argo date;
%   2. finds the nearest CMEMS grid cell to the Argo location;
%   3. extracts a 3 × 3 pixel window centered on that grid cell;
%   4. computes the mean CHL and spatial standard deviation within the window;
%   5. propagates the CMEMS CHL_uncertainty using the standard law of 
%      propagation of uncertainties;
%   6. computes a total uncertainty combining retrieval uncertainty and a 
%      spatial representativeness term.
%
% -------------------------------------------------------------------------
% INPUTS
% -------------------------------------------------------------------------
%
% argoLat
%   Numeric scalar or vector.
%   Latitude of the BGC-Argo profile locations (degrees north).
%
% argoLon
%   Numeric scalar or vector.
%   Longitude of the BGC-Argo profile locations (degrees east).
%   Both [-180, 180] and [0, 360] conventions are supported.
%
% argoTime
%   datetime scalar or vector.
%   Profile time. Only the date (day) is used for matching.
%
% cmemsFolder
%   Character vector or string scalar.
%   Path to the folder containing daily CMEMS NetCDF files.
%
% useParallel (optional)
%   Integer or logical flag controlling parallel execution.
%
%   = 1 (default)
%       Parallel computation is enabled.
%       Profiles are grouped by day, each CMEMS file is read once, and all
%       profiles from the same day are processed in parallel using PARFOR.
%
%   = 0
%       Serial computation is used (standard FOR loop).
%       Useful for debugging, reproducibility, or when the Parallel Toolbox
%       is unavailable.
%
% -------------------------------------------------------------------------
% PARALLEL IMPLEMENTATION DETAILS
% -------------------------------------------------------------------------
%
% When useParallel = 1:
%
%   • Profiles are grouped by acquisition date.
%   • Each CMEMS daily file is read only once per date (minimizing I/O cost).
%   • A PARFOR loop processes all profiles belonging to that day.
%   • Each worker performs independent spatial matching and uncertainty
%     computation.
%
% This strategy:
%   - avoids repeated NetCDF reads,
%   - improves performance for large datasets,
%   - ensures deterministic results (no race conditions).
%
% Note:
%   The Parallel Computing Toolbox is required. A parallel pool is
%   automatically started if not already active.
%
% -------------------------------------------------------------------------
% REQUIRED VARIABLES IN CMEMS FILES
% -------------------------------------------------------------------------
%
% lat
%   Latitude vector.
%
% lon
%   Longitude vector.
%
% CHL
%   Chlorophyll-a concentration (mg m^-3).
%
% CHL_uncertainty
%   Relative uncertainty of CHL (%).
%
% flags
%   Quality flag.
%
% -------------------------------------------------------------------------
% OUTPUT
% -------------------------------------------------------------------------
%
% OUT (table, one row per Argo profile)
%
%   OUT.ArgoLat
%   OUT.ArgoLon
%   OUT.ArgoTime
%
%   OUT.CMEMS_CHL_1px
%       CHL at nearest grid cell (mg m^-3)
%
%   OUT.CMEMS_CHL_unc_1px_pct
%       Pixel-level relative uncertainty (%)
%
%   OUT.CMEMS_flag_1px
%       Pixel-level quality flag
%
%   OUT.CMEMS_CHL_mean_3x3
%       Mean CHL over 3 × 3 window (mg m^-3)
%
%   OUT.CMEMS_CHL_sd_3x3
%       Spatial standard deviation within window (mg m^-3)
%       → represents local variability (NOT measurement uncertainty)
%
%   OUT.CMEMS_CHL_unc_abs_3x3
%       Absolute uncertainty of mean CHL (mg m^-3)
%
%   OUT.CMEMS_CHL_unc_pct_3x3
%       Relative uncertainty of mean CHL (%)
%
%   OUT.CMEMS_CHL_unc_total_abs_3x3
%       Total absolute uncertainty (mg m^-3)
%
%   OUT.CMEMS_CHL_unc_total_pct_3x3
%       Total relative uncertainty (%)
%
%   OUT.CMEMS_CHL_Nvalid_3x3
%       Number of valid pixels in 3 × 3 window
%
% -------------------------------------------------------------------------
% UNCERTAINTY CALCULATION
% -------------------------------------------------------------------------
%
% For each pixel i:
%
%   sigma_i = CHL_i × (CHL_uncertainty_i / 100)
%
% Propagated uncertainty:
%
%   sigma_mean = sqrt(sum(sigma_i^2)) / N
%
% Total uncertainty:
%
%   sigma_total = sqrt( sigma_mean^2 + (SD / sqrt(N))^2 )
%
% where SD represents spatial variability within the 3 × 3 window.
%
% -------------------------------------------------------------------------
% RECOMMENDED USE
% -------------------------------------------------------------------------
%
% For BGC-Argo vs CMEMS comparison:
%
%   x value:
%       OUT.CMEMS_CHL_mean_3x3
%
%   x error bar (recommended):
%       OUT.CMEMS_CHL_unc_abs_3x3
%
%   conservative error bar:
%       OUT.CMEMS_CHL_unc_total_abs_3x3
%
%   spatial variability diagnostic:
%       OUT.CMEMS_CHL_sd_3x3
%

if nargin < 5
    useParallel = 1; % 默认并行
end

n = numel(argoLat);

OUT = table;
OUT.ArgoLat = argoLat(:);
OUT.ArgoLon = argoLon(:);
OUT.ArgoTime = argoTime(:);

OUT.CMEMS_CHL_1px = nan(n,1);
OUT.CMEMS_CHL_unc_1px_pct = nan(n,1);
OUT.CMEMS_flag_1px = nan(n,1);

OUT.CMEMS_CHL_mean_3x3 = nan(n,1);
OUT.CMEMS_CHL_sd_3x3 = nan(n,1);
OUT.CMEMS_CHL_unc_abs_3x3 = nan(n,1);
OUT.CMEMS_CHL_unc_pct_3x3 = nan(n,1);
OUT.CMEMS_CHL_Nvalid_3x3 = nan(n,1);

OUT.CMEMS_CHL_unc_total_abs_3x3 = nan(n,1);
OUT.CMEMS_CHL_unc_total_pct_3x3 = nan(n,1);

%% =======================
% 非并行版本（原始逻辑）
%% =======================
if useParallel ~= 1

    lastFile = "";
    lat = []; lon = [];
    CHL = []; UNC = []; FLAGS = [];

    for i = 1:n

        if isnat(argoTime(i)) || isnan(argoLat(i)) || isnan(argoLon(i))
            continue
        end

        thisDate = dateshift(argoTime(i), 'start', 'day');
        dateStr = datestr(thisDate, 'yyyymmdd');

        ncfile = fullfile(cmemsFolder, ...
            [dateStr '_cmems_obs-oc_glo_bgc-plankton_my_l4-gapfree-multi-4km_P1D.nc']);

        if ~isfile(ncfile)
            continue
        end

        if string(ncfile) ~= lastFile
            lat = ncread(ncfile, 'lat');
            lon = ncread(ncfile, 'lon');

            CHL = squeeze(ncread(ncfile, 'CHL'));
            UNC = squeeze(ncread(ncfile, 'CHL_uncertainty'));
            FLAGS = squeeze(ncread(ncfile, 'flags'));

            CHL = double(CHL);
            UNC = double(UNC);
            FLAGS = double(FLAGS);

            CHL(CHL < 0) = NaN;
            UNC(UNC < 0) = NaN;

            lastFile = string(ncfile);
        end

        [OUT] = process_one(i, OUT, argoLat, argoLon, lat, lon, CHL, UNC, FLAGS);

    end

    return
end

%% =======================
% 并行版本（按日期分组）
%% =======================

p = gcp('nocreate');
if isempty(p)
    parpool;
end

argoDate = dateshift(argoTime, 'start', 'day');
uniqueDates = unique(argoDate(~isnat(argoDate)));

for d = 1:numel(uniqueDates)

    thisDate = uniqueDates(d);
    dateStr = datestr(thisDate, 'yyyymmdd');

    ncfile = fullfile(cmemsFolder, ...
        [dateStr '_cmems_obs-oc_glo_bgc-plankton_my_l4-gapfree-multi-4km_P1D.nc']);

    if ~isfile(ncfile)
        continue
    end

    idxDay = find(argoDate == thisDate);

    lat = ncread(ncfile, 'lat');
    lon = ncread(ncfile, 'lon');

    CHL = squeeze(ncread(ncfile, 'CHL'));
    UNC = squeeze(ncread(ncfile, 'CHL_uncertainty'));
    FLAGS = squeeze(ncread(ncfile, 'flags'));

    CHL = double(CHL);
    UNC = double(UNC);
    FLAGS = double(FLAGS);

    CHL(CHL < 0) = NaN;
    UNC(UNC < 0) = NaN;

    nd = numel(idxDay);

    tmp = repmat(struct( ...
        'chl1',nan,'unc1',nan,'flag',nan, ...
        'mean',nan,'sd',nan,'unc_abs',nan,'unc_pct',nan, ...
        'total_abs',nan,'total_pct',nan,'N',nan), nd,1);

    parfor k = 1:nd

        i = idxDay(k);

        if isnat(argoTime(i)) || isnan(argoLat(i)) || isnan(argoLon(i))
            continue
        end

        tmp(k) = process_core(argoLat(i), argoLon(i), lat, lon, CHL, UNC, FLAGS);

    end

    % 写回
    for k = 1:nd
        i = idxDay(k);

        OUT.CMEMS_CHL_1px(i) = tmp(k).chl1;
        OUT.CMEMS_CHL_unc_1px_pct(i) = tmp(k).unc1;
        OUT.CMEMS_flag_1px(i) = tmp(k).flag;

        OUT.CMEMS_CHL_mean_3x3(i) = tmp(k).mean;
        OUT.CMEMS_CHL_sd_3x3(i) = tmp(k).sd;
        OUT.CMEMS_CHL_unc_abs_3x3(i) = tmp(k).unc_abs;
        OUT.CMEMS_CHL_unc_pct_3x3(i) = tmp(k).unc_pct;
        OUT.CMEMS_CHL_unc_total_abs_3x3(i) = tmp(k).total_abs;
        OUT.CMEMS_CHL_unc_total_pct_3x3(i) = tmp(k).total_pct;
        OUT.CMEMS_CHL_Nvalid_3x3(i) = tmp(k).N;
    end

end

end


function OUT = process_one(i, OUT, argoLat, argoLon, lat, lon, CHL, UNC, FLAGS)

res = process_core(argoLat(i), argoLon(i), lat, lon, CHL, UNC, FLAGS);

OUT.CMEMS_CHL_1px(i) = res.chl1;
OUT.CMEMS_CHL_unc_1px_pct(i) = res.unc1;
OUT.CMEMS_flag_1px(i) = res.flag;

OUT.CMEMS_CHL_mean_3x3(i) = res.mean;
OUT.CMEMS_CHL_sd_3x3(i) = res.sd;
OUT.CMEMS_CHL_unc_abs_3x3(i) = res.unc_abs;
OUT.CMEMS_CHL_unc_pct_3x3(i) = res.unc_pct;
OUT.CMEMS_CHL_unc_total_abs_3x3(i) = res.total_abs;
OUT.CMEMS_CHL_unc_total_pct_3x3(i) = res.total_pct;
OUT.CMEMS_CHL_Nvalid_3x3(i) = res.N;

end


function res = process_core(lat0, lon0, lat, lon, CHL, UNC, FLAGS)

res = struct('chl1',nan,'unc1',nan,'flag',nan, ...
             'mean',nan,'sd',nan,'unc_abs',nan,'unc_pct',nan, ...
             'total_abs',nan,'total_pct',nan,'N',nan);

if max(lon) > 180 && lon0 < 0
    lon0 = lon0 + 360;
elseif max(lon) <= 180 && lon0 > 180
    lon0 = lon0 - 360;
end

[~, ilat] = min(abs(lat - lat0));
[~, ilon] = min(abs(lon - lon0));

res.chl1 = CHL(ilon, ilat);
res.unc1 = UNC(ilon, ilat);
res.flag = FLAGS(ilon, ilat);

ilatRange = max(ilat-1,1):min(ilat+1,numel(lat));
ilonRange = mod((ilon-1:ilon+1)-1, numel(lon)) + 1;

chl3 = CHL(ilonRange, ilatRange);
unc3 = UNC(ilonRange, ilatRange);
flag3 = FLAGS(ilonRange, ilatRange);

valid = isfinite(chl3) & chl3 > 0 & ...
        isfinite(unc3) & unc3 >= 0 & ...
        isfinite(flag3);

chlValid = chl3(valid);
uncValid = unc3(valid);

N = numel(chlValid);

if N < 3
    return
end

chlMean = mean(chlValid);
chlSd = std(chlValid);

sigma_i = chlValid .* uncValid ./ 100;

uncAbs = sqrt(sum(sigma_i.^2)) / N;
uncPct = uncAbs / chlMean * 100;

repAbs = chlSd / sqrt(N);

totalAbs = sqrt(uncAbs.^2 + repAbs.^2);
totalPct = totalAbs / chlMean * 100;

res.mean = chlMean;
res.sd = chlSd;
res.unc_abs = uncAbs;
res.unc_pct = uncPct;
res.total_abs = totalAbs;
res.total_pct = totalPct;
res.N = N;

end