# Historical-interval expert pilot: compliant version 02 result

## Evidence qualification

This experiment returned a valid **NO_GO** for the fixed 60-basin internal-validation pilot.
It does not establish a result on the sealed 531-basin formal benchmark and does not reject
every possible temporal-expert architecture. It rejects scaling the tested fixed historical
intervals, encoder design, expert heads, and dynamic gate under the preregistered stopping rule.

The formal evaluation period, 1989-10-01 through 1999-09-30, remained outside the emitted
supervised-target bundle. Candidate training code had no raw-streamflow loader or raw-streamflow
path. This is supported by code-path review and frozen hashes, not by operating-system-level file
access tracing.

The interval labels describe the age of meteorological input information, not the physical age
of water discharged by the basin. Gate weights therefore cannot be interpreted as new-water or
old-water fractions.

## Frozen comparison

- Supervised training target dates: 1999-10-01 through 2006-09-30.
- Internal validation target dates: 2006-10-01 through 2008-09-30.
- Basins: 60, selected deterministically using only the allowed 27 static attributes.
- Random seeds: 100, 200, and 300.
- Dynamic inputs: Maurer meteorological forcing only; observed discharge was a supervised target
  and validation observation, never a model input.
- Recent interval: lags 0-29 days, retained daily.
- Medium interval: lags 30-1824 days, aggregated into 60 equal-width mean bins.
- Old interval: lags 1825-3649 days, aggregated into 60 equal-width mean bins.
- Model sizes: mainstream long short-term memory network 83,073 parameters; equal-input
  multiscale fusion control 82,497; explicit historical-interval experts 82,758. The maximum
  spread was 0.693%.
- The two multiscale arms consumed the same three interval tensors and applied dropout once to
  each of the same three encoder states. Their intended mechanism difference was one fusion head
  versus three interval-specific prediction heads combined by a dynamic gate.
- Each of the nine runs used 10 epochs and 153,420 training samples and produced 43,860 daily
  validation predictions covering all 60 basins.

The training and analysis code base recorded in every run was
df01333b68db82f113906d267be65d7150c230a3. The frozen configuration commit was
0b3145751e3339801db65f6f9847cf8219579442.

## Controlled target bundle

- Target bundle:
  results/26_historical_band_experts/trusted_targets/pilot_targets_1999_2008_v02.csv.
- Target bundle SHA-256:
  d4c93675eefd433515d6f7e10943caea31c6eb7e30533d4c387cf9325886e05c.
- Basin-list SHA-256:
  3160dad3b22200fdb596164c9f69e4fbe19cc156cfad768beb193efea7b26b65.
- Row count: 197,280.
- Date bounds: 1999-10-01 through 2008-09-30.
- Basin count: 60.
- Formal-evaluation rows emitted: 0.
- Trusted preparation raw-streamflow files read: 60.
- Candidate raw-streamflow reads found by code-path audit: 0.

The version 02 configuration SHA-256 was
0ce82a1cd26326b42ecf6827ad8ad946afdae91c2aa5e2d1d836e9bff554cb63.

## Results

Median basin Nash-Sutcliffe efficiency by random seed:

| Model | Seed 100 | Seed 200 | Seed 300 |
|---|---:|---:|---:|
| Mainstream long short-term memory network | 0.62841 | 0.62724 | 0.63034 |
| Equal-input multiscale fusion control | 0.61412 | 0.65383 | 0.62672 |
| Explicit historical-interval experts | 0.60712 | 0.61132 | 0.59855 |

Paired historical-interval-expert minus equal-input-fusion results:

| Seed | Median basin difference | Basin win fraction | Joint threshold result |
|---|---:|---:|---|
| 100 | 0.003801 | 0.5167 | Fail |
| 200 | -0.042703 | 0.3167 | Fail |
| 300 | -0.016909 | 0.4333 | Fail |

No seed reached both the preregistered median-effect threshold of 0.01 and basin-win-fraction
threshold of 0.55. The paired basin-level bootstrap 95% interval for the mean-across-seeds
expert-minus-fusion effect was [-0.028417, -0.005830], entirely below zero.

The median paired expert-minus-mainstream difference was -0.013554. Mean gate weights were
0.266514 for the recent interval, 0.257606 for the medium interval, and 0.475880 for the old
interval. The largest mean weight remained below the frozen collapse limit of 0.95.

## Frozen stopping criteria

| Criterion | Result |
|---|---|
| Median expert-minus-fusion effect at least 0.01 in at least two seeds | Fail |
| Expert basin win fraction at least 0.55 in at least two seeds | Fail |
| Both thresholds met jointly in at least two seeds | Fail |
| Paired bootstrap 95% lower bound above zero | Fail |
| Expert not worse than the mainstream model | Fail |
| No expert-weight collapse above 0.95 | Pass |

All six criteria were required. The fixed version 02 design therefore returned **NO_GO** and
must not be scaled to the sealed formal benchmark in its current form.

## Exact commands

Each formal pilot run used:

    python src/26_historical_band_experts/train.py --config src/26_historical_band_experts/configs/pilot_v02.json --variant <mainstream_lstm|multiscale_fusion|historical_band_experts> --seed <100|200|300> --data-dir G:\github\pycharm\projects\neuralhydrology\data\camels_us --targets-file results\26_historical_band_experts\trusted_targets\pilot_targets_1999_2008_v02.csv --targets-sha256 d4c93675eefd433515d6f7e10943caea31c6eb7e30533d4c387cf9325886e05c --device cuda:0

Analysis and focused verification used:

    python src/26_historical_band_experts/analyze.py --results-root results/26_historical_band_experts/pilot_v02
    pytest src/26_historical_band_experts/tests -v
    git diff --check

## Evidence verification

- All 9 expected runs completed; no run was missing.
- All 36 manifest-listed artifact hashes matched.
- All 394,740 daily predictions were checked.
- Every run contained exactly 60 basins and 43,860 unique daily keys from 2006-10-01 through
  2008-09-30.
- Basin, date, and observed discharge matched exactly among the three models for every seed.
- All 540 stored per-basin Nash-Sutcliffe efficiencies were independently recomputed.
- The 10,000-resample paired bootstrap interval, three mean expert weights, and six stopping
  criteria were independently recomputed.
- The focused implementation suite completed with 52 passing tests and one pre-existing pytest
  configuration warning.
- Two independent reviews reported 0 Critical issues and 0 Important issues. The sole
  non-blocking limitation was that zero candidate raw-streamflow access is a code-path audit
  conclusion rather than operating-system-level file access telemetry.

Analysis-output SHA-256 hashes:

- summary.json:
  dc65fbcab16638589fba642d7b214dfbc93489342281f5c20a5dec5780104c1e.
- per_seed.csv:
  e4f6f01a2bc0b1a1d71b9b1679562136243814bb8c719525fcb7517aa4728b39.
- paired_per_basin.csv:
  f50048fad7ae2bb709cc326f19ceb5efc31baedc1468bf326fe525b424aaf8c4.

## Run artifact SHA-256 hashes

| Run | Checkpoint | Config snapshot | Per-basin metrics | Daily predictions |
|---|---|---|---|---|
| mainstream_lstm_s100 | ffcab4920471a6611a1e6b7b6ad7cd223741594a09ce55bafbb46d0c3a95b368 | 605b605025334c36853f74bdd4ae78d706bb98481d5b893f391be77753fdec15 | 65674d81887a5dee83be0053b0a1d16d39163addc79554ca729b23eaf728903b | 8c49d2661463a9741ab5d1b6fbf188eb56357a6ea8a2406a547180fbeeb1d9e3 |
| mainstream_lstm_s200 | 0af94a08ce28f71d9e9669d3c1e10608e36d430ed45b1d5cbecd03874f186af0 | b9c88a76f7a17d43c9516bd0f1649e223e98f444054a7400044d591fcf847d88 | 9ff0abedc284410bd8e7f2f27a5ccd7645d5e2bc3886824e6e850b1bbbdcc18c | 0a9cab043fd536be8acd7e700d84fe41b61444426b47ae621a6d954773d9e1da |
| mainstream_lstm_s300 | 77228ae42cdd3922e3e4e3878b6867f33d9dada9b1dbecca0081da450e845b84 | 1efb5fc8f3ee7dc86687229431bdd84fa3895776537da192bc9464580c09602b | 7afc590bf5ed07311c92450df719c75f606236a7435920676f5132b35c2cf5ed | 8c8fd6628156519240daee77721f0a77acb37a80492600f4f407675fb8cf6732 |
| multiscale_fusion_s100 | 0b70188dbd1f170ac2f270a7d6df980898726f8d225362da0bce46e1d26627e9 | 2f999ed76e8946cabd513ec2054ce2330f117a8edce44ab13031fa16567e7899 | e034b7503231b6a316b6f29a84351e0c2e961d1fe9999184adc0d2531486c3bc | 572fedd99b35a443fb9124649305c7e9659d8cb2acf402e8d88238ffdd702ed6 |
| multiscale_fusion_s200 | ac814f0ea35791d636ae4b380b8f1ff22dcea3e60cb799058b807fd823e4d210 | befc5cfb4fb736ef5e1bc41dc4eef690c4aef544372611558bbcaea7b8fb32f1 | 90b431cc0e375f71b16c48b14bb4b1bb31d1eb384b2e24c0c456a1e02dafbfb2 | f61b1d53eb6cee9b91e7899103d2401e1ae8ea2d2110e2c3cd10063faae94303 |
| multiscale_fusion_s300 | cae0e64ee5b1af0ef277cc8c035fe134c158fbcf47a22578c22636ed6fc3f009 | 12b99192cd6be76f808f68eef90617509597098d56bbbc6edbda30933e0ecf43 | df351f9bf1fb090ccacc0be4929602bc79a90413974b52a6a115b7b16937f523 | da5002f3c19af9c9a7892732fe83ae4d07204fdd016a88d5078a6baee2d4ee3d |
| historical_band_experts_s100 | a63a928c75479ea12365e5737b9ab8cbd616ead929b808b3de3341d184ec158c | 2ea77d53a8607ef69b9e166a39c0f7849fe28e8dbbc488bb943fe0c59c2688a3 | fbda5248b910bbf8eaa37334eb38ec205d0f50599536aede989c07016586630a | e1076a23f6043fc3cc6aba3eeaef286c4de66e23eeb3536f65fcf7f5edc43039 |
| historical_band_experts_s200 | dea3f7d5bcf5af282a83cf49dca9fef076b1532859ef3122e03267b103cc56de | fcbaba7f1d69f82ad2491a703d7448326106bfd67c58fc9a1b87034279467e7c | b4ecdf46b863f1d1bc5efddca7df208e1f8673e01f922b48dc7348fd5a1ef264 | 0a4d3878b4e3212201cba6a6d5f94a81a79c5f76c412e12761c2ed660622937d |
| historical_band_experts_s300 | ce57ec0a8868f1f48a1ca7843f2f29e060d49e8876448d1e2a764c2a9ca2cb66 | 07d1b9fb34dd7934fb7d04a4c6a7b72c5603895cc77fc7c6183b69ca7f26a09b | 8a1af27ed1c91e1bf37fe5f78aabcfafef6a1f65945c56a02cfb327a742f27c7 | d3dc2bd56a5353cbd26ad48775440f6c06b75b0726889cb007a0218b05f6014a |

The raw result directories remain under the project-standard ignored results/ tree. Preserve
or archive them before workspace cleanup if long-term independent replay of the hashes is needed.
