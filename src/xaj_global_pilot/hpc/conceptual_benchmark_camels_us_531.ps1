param(
    [string]$Manifest = "src/xaj_global_pilot/configs/conceptual_benchmark_camels_us_531.txt",
    [string]$OutputDir = "results/10_global_conceptual_model_benchmark/camels_us_531_v02",
    [int]$ChunkSize = 50,
    [int]$Trials = 5000,
    [int]$Restarts = 3,
    [string]$DataRoot = "data/camels_us"
)

python -m src.xaj_global_pilot.hpc.build_conceptual_benchmark_chunks `
  --manifest $Manifest `
  --output-dir $OutputDir `
  --chunk-size $ChunkSize `
  --allow-scale-up

foreach ($model in @("xaj_pdd", "hbv", "gr4j_pdd")) {
  foreach ($chunkFile in Get-ChildItem (Join-Path $OutputDir "chunks") -Filter "chunk_*.txt" | Sort-Object Name) {
    python -m src.xaj_global_pilot.hpc.run_conceptual_benchmark_chunk `
      --model $model `
      --chunk-file $chunkFile.FullName `
      --output-dir $OutputDir `
      --data-root $DataRoot `
      --trials $Trials `
      --restarts $Restarts
  }
}
