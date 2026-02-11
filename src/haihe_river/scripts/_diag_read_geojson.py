import glob
import geopandas as gpd

files = glob.glob('data/haihe/basins_individual/*.geojson')
print('count', len(files))
if not files:
    raise SystemExit('no files found')
fp = files[0]
print('sample', fp)
gdf = gpd.read_file(fp)
print('rows', len(gdf), 'crs', gdf.crs)
print('columns', list(gdf.columns))
print('geom type', gdf.geometry.iloc[0].geom_type)



