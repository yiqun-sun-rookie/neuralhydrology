# Namou TiRex Minimal Validation Design

**Objective**

Introduce a minimal `TiRex` experiment path into the existing `neuralhydrology` framework so we can quickly test whether a newer sequence model shows any signal on the Namou/Kuwei hourly forecasting task before investing in broader experiments or paper framing.

**Problem Context**

Current Namou conclusions show a strong gap between rain-only and historical-flow-informed setups. Before expanding the scientific story, we need one controlled answer: does a newer model family offer any practical value on the existing task definitions, especially in settings where rainfall information is hard to exploit?

This should not become a large model integration effort. The first pass only needs:
- framework-level model registration
- minimal smoke-safe configs
- a direct comparison path against an existing recurrent baseline

**Design Choice**

Use a lightweight adapter model named `tirex` inside `neuralhydrology/modelzoo/` that:
- follows the same interface as existing single-frequency models
- reuses `InputLayer` and the standard regression head
- degrades gracefully if the external `tirex` dependency is unavailable

For the first validation pass, we do not aim for pretrained zero-shot use. We only need a trainable model path that is consistent with the current framework and easy to compare against `gru`.

**Scope**

In scope:
- add a new `tirex` model class
- register it in `neuralhydrology.modelzoo.get_model()`
- add focused unit tests for model construction and forward output shape
- add minimal Namou/Kuwei configs for `LT1h` and `LT24h`

Out of scope:
- full pretrained-foundation integration
- broad benchmark matrix across all leads and model families
- paper writing or interpretation beyond initial result screening

**Success Criteria**

The experiment path is worth continuing only if all of the following are true:
- the new model builds through the existing training framework without special-case scripts
- targeted tests pass
- at least one minimal TiRex configuration can be launched with the current config machinery
- early results show a credible signal over `gru` in either rain-only or long-lead settings

If those conditions are not met, we stop the TiRex line and return to input-representation work instead of expanding model work.
