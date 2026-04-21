# Pretrained LSTM Knowledge Separation Design

**Objective**

Design a smallest-validity study that tests whether transferable knowledge and domain-specific knowledge exhibit partially separable structure in pretrained hydrological LSTMs built with NeuralHydrology.

**Problem Context**

Current hydrological fine-tuning work mostly asks whether adaptation helps, and which coarse strategy performs best. That is useful, but it leaves a more fundamental question unresolved: when a large-sample pretrained LSTM transfers to a shifted target domain, is the useful knowledge organized in a way that can be partially separated into shared and target-specific components?

For a first study, the goal is not to build a new adaptation method or a global foundation model. The goal is to use the existing NeuralHydrology LSTM structure as an experimental probe and determine whether this scientific question shows measurable signal.

**Design Choice**

Use a single pretrained LSTM source model and a small structured adaptation matrix:

- `head-only`
- `embedding-only`
- `lstm-only`
- `full fine-tune`

Compare those four interventions under two target-domain conditions:

- `low shift`
- `high shift`

Define shift using basin static attributes and climate descriptors rather than region names. This keeps the design tied to the scientific question instead of to arbitrary geographic boundaries.

**Why This Scope**

This design is intentionally small.

- It keeps the model family fixed to NeuralHydrology LSTM.
- It avoids introducing LoRA, adapters, or cross-architecture comparisons in phase 1.
- It limits target conditions to two interpretable shift levels.
- It uses module-level intervention as a causal probe, not as the main contribution.

This is enough to test whether:

- low-shift adaptation can be achieved with shallow changes
- high-shift adaptation requires deeper changes
- deeper adaptation brings higher forgetting or instability

**Scientific Questions**

Primary question:

> In large-sample pretrained hydrological LSTMs, do transferable knowledge and domain-specific knowledge exhibit partially separable structure?

Secondary supporting question:

> Does the current NeuralHydrology/LSTM module structure support that separation well enough to expose it experimentally?

**Hypotheses**

1. Under low shift, `head-only` adaptation can recover most of the target-domain benefit, implying that much of the relevant representation is already transferable.
2. Under high shift, shallow adaptation is insufficient and target benefit requires changing `embedding` and/or `lstm`, implying that some domain-specific information is encoded deeper in the model.
3. `lstm-only` and `full fine-tune` will produce larger representation drift and higher source-knowledge forgetting than `head-only`, indicating a tradeoff between adaptability and preservation.

**Minimal Experimental Matrix**

Source:

- one large-sample pretrained LSTM source model

Targets:

- one `low shift` target condition
- one `high shift` target condition

Adaptation groups:

- `head-only`
- `embedding-only`
- `lstm-only`
- `full FT`

**Shift Definition**

Shift should be quantified in a basin descriptor space built from interpretable variables such as:

- aridity
- mean precipitation
- fraction of snow
- elevation
- slope
- area
- forest fraction
- soil texture or depth

Candidate target basins should be selected by distance from the source distribution in that descriptor space. The first study should vary only this source-target attribute shift and keep other shifts, such as time scale or forcing product changes, out of scope.

**Evidence Types**

The study should combine two evidence classes.

1. Intervention evidence
- target-domain performance
- basin-level improvement and degradation rates
- sample-efficiency behavior
- source-knowledge retention after adaptation

2. Representation evidence
- similarity between source and adapted internal representations
- changes in static embeddings and LSTM hidden states
- simple probing analysis to test whether useful target-relevant structure is already present before deeper adaptation

**Success Criteria**

The study is worth expanding if at least two of the following hold:

- `head-only` is competitive under low shift but not under high shift
- `embedding-only` and `lstm-only` show meaningfully different adaptation behavior
- deeper adaptation yields more forgetting or instability
- representation changes align with the intervention results

**Valuable Negative Result**

A negative result is still publishable if it is cleanly demonstrated. For example, if all module-level interventions behave similarly, that would support the alternative conclusion that current hydrological LSTM module boundaries do not expose separable transferable and domain-specific knowledge well enough for structured adaptation to matter.

**Out of Scope**

- new PEFT methods such as LoRA
- cross-architecture comparison
- full Caravan/global retraining
- time-scale transfer
- forcing-product transfer
- large multi-region benchmark matrices

**Recommended Next Step**

Implement the smallest experiment that can test the hypotheses above using one source model, two shift conditions, four adaptation groups, and a minimal representation-analysis pipeline.
