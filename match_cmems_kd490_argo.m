function OUT = match_cmems_kd490_argo(argoLat, argoLon, argoTime, cmemsFolder, useParallel)
%MATCH_CMEMS_KD490_ARGO Match BGC-Argo locations with daily CMEMS KD490 data.
%
% This function matches BGC-Argo profile locations and dates with the daily
% CMEMS global ocean colour transparency product:
%
%   YYYYMMDD_cmems_obs-oc_glo_bgc-transp_my_l4-gapfree-multi-4km_P1D.nc
%
% For each Argo profile, the function:
%   1. identifies the CMEMS daily file corresponding to the Argo date;
%   2. finds the nearest CMEMS grid cell to the Argo location;
%   3. extracts a 3 x 3 pixel window centered on that grid cell;
%   4. computes the mean KD490 and spatial standard deviation within the window;
%   5. propagates the CMEMS KD490_uncertainty using the standard law of
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
%   Latitude of the BGC-Argo profile locations, in degrees north.
%
% argoLon
%   Numeric scalar or vector.
%   Longitude of the BGC-Argo profile locations, in degrees east.
%   Both [-180, 180] and [0, 360] conventions are supported.
%
% argoTime
%   datetime scalar or vector.
%   Profile time. Only the date is used for matching because the CMEMS
%   product is daily.
%
% cmemsFolder
%   Character vector or string scalar.
%   Path to the folder containing daily CMEMS NetCDF files.
%
% useParallel (optional)
%   Integer or logical flag controlling parallel execution.
%
%   = 1 (default)
%       Parallel computation is enabled. Profiles are grouped by date, each
%       CMEMS file is read once, and all profiles from the same day are
%       processed in parallel using PARFOR.
%
%   = 0
%       Serial computation is used with a standard FOR loop. This is useful
%       for debugging or when the Parallel Computing Toolbox is unavailable.
%
% -------------------------------------------------------------------------
% REQUIRED VARIABLES IN EACH CMEMS NETCDF FILE
% -------------------------------------------------------------------------
%
% lat
%   Latitude vector.
%
% lon
%   Longitude vector.
%
% KD490
%   Diffuse attenuation coefficient at 490 nm.
%   Unit: m^-1.
%
% KD490_uncertainty
%   Relative uncertainty of KD490.
%   Unit: %.
%
% -------------------------------------------------------------------------
% OUTPUT
% -------------------------------------------------------------------------
%
% OUT
%   Table with one row per input Argo profile.
%
%   OUT.ArgoLat
%       Original input Argo latitude.
%
%   OUT.ArgoLon
%       Original input Argo longitude.
%
%   OUT.ArgoTime
%       Original input Argo datetime.
%
%   OUT.CMEMS_KD490_1px
%       KD490 value from the nearest CMEMS grid cell.
%       Unit: m^-1.
%
%   OUT.CMEMS_KD490_unc_1px_pct
%       CMEMS relative KD490 uncertainty from the nearest grid cell.
%       Unit: %.
%
%   OUT.CMEMS_KD490_mean_3x3
%       Mean KD490 within the valid pixels of the 3 x 3 window centered on
%       the nearest CMEMS grid cell.
%       Unit: m^-1.
%
%   OUT.CMEMS_KD490_sd_3x3
%       Standard deviation of KD490 within the valid pixels of the 3 x 3
%       window. This represents local spatial variability, not retrieval
%       uncertainty.
%       Unit: m^-1.
%
%   OUT.CMEMS_KD490_unc_abs_3x3
%       Absolute uncertainty of the 3 x 3 mean KD490, obtained by propagating
%       the pixel-level CMEMS KD490_uncertainty using the standard law of
%       propagation of uncertainties.
%       Unit: m^-1.
%
%   OUT.CMEMS_KD490_unc_pct_3x3
%       Relative uncertainty of the 3 x 3 mean KD490.
%       Unit: %.
%
%   OUT.CMEMS_KD490_unc_total_abs_3x3
%       Total absolute uncertainty of the 3 x 3 mean KD490, combining the
%       propagated retrieval uncertainty and a spatial representativeness
%       term estimated as SD/sqrt(N).
%       Unit: m^-1.
%
%   OUT.CMEMS_KD490_unc_total_pct_3x3
%       Total relative uncertainty of the 3 x 3 mean KD490.
%       Unit: %.
%
%   OUT.CMEMS_KD490_Nvalid_3x3
%       Number of valid pixels used within the 3 x 3 window.
%
% -------------------------------------------------------------------------
% UNCERTAINTY CALCULATION
% -------------------------------------------------------------------------
%
% For each valid pixel i:
%
%   sigma_i = KD490_i * KD490_uncertainty_i / 100
%
% The propagated uncertainty of the 3 x 3 mean is:
%
%   sigma_mean = sqrt(sum(sigma_i.^2)) / N
%
% where N is the number of valid pixels.
%
% The total uncertainty is calculated as:
%
%   sigma_total = sqrt(sigma_mean.^2 + (KD490_sd_3x3 / sqrt(N)).^2)
%
% -------------------------------------------------------------------------
% RECOMMENDED USE
% -------------------------------------------------------------------------
%
% For BGC-Argo versus CMEMS KD490 comparison:
%
%   x value:
%       OUT.CMEMS_KD490_mean_3x3
%
%   x error bar based on retrieval uncertainty:
%       OUT.CMEMS_KD490_unc_abs_3x3
%
%   conservative x error bar including representativeness:
%       OUT.CMEMS_KD490_unc_total_abs_3x3
%
%   local spatial variability diagnostic:
%       OUT.CMEMS_KD490_sd_3x3
%

if nargin < 5
    useParallel = 1;
end

n = numel(argoLat);

argoLat = argoLat(:);
argoLon = argoLon(:);
argoTime = argoTime(:);

OUT = table;
OUT.ArgoLat = argoLat;
OUT.ArgoLon = argoLon;
OUT.ArgoTime = argoTime;

OUT.CMEMS_KD490_1px = nan(n,1);
OUT.CMEMS_KD490_unc_1px_pct = nan(n,1);

OUT.CMEMS_KD490_mean_3x3 = nan(n,1);
OUT.CMEMS_KD490_sd_3x3 = nan(n,1);
OUT.CMEMS_KD490_unc_abs_3x3 = nan(n,1);
OUT.CMEMS_KD490_unc_pct_3x3 = nan(n,1);

OUT.CMEMS_KD490_unc_total_abs_3x3 = nan(n,1);
OUT.CMEMS_KD490_unc_total_pct_3x3 = nan(n,1);

OUT.CMEMS_KD490_Nvalid_3x3 = nan(n,1);

if useParallel ~= 1

    lastFile = "";
    lat = [];
    lon = [];
    KD490 = [];
    UNC = [];

    for i = 1:n

        if isnat(argoTime(i)) || isnan(argoLat(i)) || isnan(argoLon(i))
            continue
        end

        thisDate = dateshift(argoTime(i), 'start', 'day');
        dateStr = datestr(thisDate, 'yyyymmdd');

        ncfile = fullfile(cmemsFolder, ...
            [dateStr '_cmems_obs-oc_glo_bgc-transp_my_l4-gapfree-multi-4km_P1D.nc']);

        if ~isfile(ncfile)
            continue
        end

        if string(ncfile) ~= lastFile

            lat = ncread(ncfile, 'lat');
            lon = ncread(ncfile, 'lon');

            KD490 = squeeze(ncread(ncfile, 'KD490'));
            UNC = squeeze(ncread(ncfile, 'KD490_uncertainty'));

            KD490 = double(KD490);
            UNC = double(UNC);

            KD490(KD490 < 0) = NaN;
            UNC(UNC < 0) = NaN;

            lastFile = string(ncfile);

        end

        res = process_kd490_core(argoLat(i), argoLon(i), lat, lon, KD490, UNC);

        OUT.CMEMS_KD490_1px(i) = res.val1;
        OUT.CMEMS_KD490_unc_1px_pct(i) = res.unc1;

        OUT.CMEMS_KD490_mean_3x3(i) = res.mean;
        OUT.CMEMS_KD490_sd_3x3(i) = res.sd;
        OUT.CMEMS_KD490_unc_abs_3x3(i) = res.unc_abs;
        OUT.CMEMS_KD490_unc_pct_3x3(i) = res.unc_pct;
        OUT.CMEMS_KD490_unc_total_abs_3x3(i) = res.total_abs;
        OUT.CMEMS_KD490_unc_total_pct_3x3(i) = res.total_pct;
        OUT.CMEMS_KD490_Nvalid_3x3(i) = res.N;

    end

    return

end

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
        [dateStr '_cmems_obs-oc_glo_bgc-transp_my_l4-gapfree-multi-4km_P1D.nc']);

    if ~isfile(ncfile)
        continue
    end

    idxDay = find(argoDate == thisDate);

    lat = ncread(ncfile, 'lat');
    lon = ncread(ncfile, 'lon');

    KD490 = squeeze(ncread(ncfile, 'KD490'));
    UNC = squeeze(ncread(ncfile, 'KD490_uncertainty'));

    KD490 = double(KD490);
    UNC = double(UNC);

    KD490(KD490 < 0) = NaN;
    UNC(UNC < 0) = NaN;

    nd = numel(idxDay);

    tmp = repmat(struct( ...
        'val1',nan, ...
        'unc1',nan, ...
        'mean',nan, ...
        'sd',nan, ...
        'unc_abs',nan, ...
        'unc_pct',nan, ...
        'total_abs',nan, ...
        'total_pct',nan, ...
        'N',nan), nd, 1);

    parfor k = 1:nd

        i = idxDay(k);

        if isnat(argoTime(i)) || isnan(argoLat(i)) || isnan(argoLon(i))
            continue
        end

        tmp(k) = process_kd490_core(argoLat(i), argoLon(i), lat, lon, KD490, UNC);

    end

    for k = 1:nd

        i = idxDay(k);

        OUT.CMEMS_KD490_1px(i) = tmp(k).val1;
        OUT.CMEMS_KD490_unc_1px_pct(i) = tmp(k).unc1;

        OUT.CMEMS_KD490_mean_3x3(i) = tmp(k).mean;
        OUT.CMEMS_KD490_sd_3x3(i) = tmp(k).sd;
        OUT.CMEMS_KD490_unc_abs_3x3(i) = tmp(k).unc_abs;
        OUT.CMEMS_KD490_unc_pct_3x3(i) = tmp(k).unc_pct;
        OUT.CMEMS_KD490_unc_total_abs_3x3(i) = tmp(k).total_abs;
        OUT.CMEMS_KD490_unc_total_pct_3x3(i) = tmp(k).total_pct;
        OUT.CMEMS_KD490_Nvalid_3x3(i) = tmp(k).N;

    end

end

end


function res = process_kd490_core(lat0, lon0, lat, lon, KD490, UNC)

res = struct( ...
    'val1',nan, ...
    'unc1',nan, ...
    'mean',nan, ...
    'sd',nan, ...
    'unc_abs',nan, ...
    'unc_pct',nan, ...
    'total_abs',nan, ...
    'total_pct',nan, ...
    'N',nan);

if max(lon) > 180 && lon0 < 0
    lon0 = lon0 + 360;
elseif max(lon) <= 180 && lon0 > 180
    lon0 = lon0 - 360;
end

[~, ilat] = min(abs(lat - lat0));
[~, ilon] = min(abs(lon - lon0));

res.val1 = KD490(ilon, ilat);
res.unc1 = UNC(ilon, ilat);

ilatRange = max(ilat-1,1):min(ilat+1,numel(lat));

ilonRaw = ilon-1:ilon+1;
ilonRange = mod(ilonRaw-1, numel(lon)) + 1;

kd3 = KD490(ilonRange, ilatRange);
unc3 = UNC(ilonRange, ilatRange);

valid = isfinite(kd3) & kd3 > 0 & ...
        isfinite(unc3) & unc3 >= 0;

kdValid = kd3(valid);
uncValid = unc3(valid);

N = numel(kdValid);

if N < 3
    return
end

kdMean = mean(kdValid, 'omitnan');
kdSd = std(kdValid, 0, 'omitnan');

sigma_i = kdValid .* uncValid ./ 100;

uncAbs = sqrt(sum(sigma_i.^2)) ./ N;
uncPct = uncAbs ./ kdMean .* 100;

repAbs = kdSd ./ sqrt(N);

totalAbs = sqrt(uncAbs.^2 + repAbs.^2);
totalPct = totalAbs ./ kdMean .* 100;

res.mean = kdMean;
res.sd = kdSd;
res.unc_abs = uncAbs;
res.unc_pct = uncPct;
res.total_abs = totalAbs;
res.total_pct = totalPct;
res.N = N;

end