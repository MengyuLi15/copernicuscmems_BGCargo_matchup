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
cmemsFolder = 'F:\cmems_obs-oc_glo_bgc-plankton_my_l4-gapfree-multi-4km_P1D\';
out = match_cmems_chla_argo(argoLat, argoLon, argoTime, cmemsFolder,0);