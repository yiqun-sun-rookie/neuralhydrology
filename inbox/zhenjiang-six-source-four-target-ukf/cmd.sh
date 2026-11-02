#!/usr/bin/env bash
set -eo pipefail
python3 - <<'SUBMIT_ISOLATED_GRU_GRADIENT_REPLAY'
import datetime,fcntl,hashlib,json,re,subprocess,traceback
from pathlib import Path
plan=json.loads('{"canonical_metadata_hashes": {"configs/protocol-v3.json": "ca41a57d0d19c97090f7a25a55f09bf733429a027024b00e07ca9ab7caa4f90a", "configs/registry-v3.json": "cdf4d4664021cae537597988472ca468aa51bf64cf40f42ea89d50e082859dff", "hpc/fixed200_case.slurm": "24fcd2e4e3b27f1b406cc4412cc1a6aaa4d3ccb32a644a649ca38d358120a037", "hpc/run_fixed200_case.py": "4157613be568d36e5dc322b2f39da81434d30dd7eba9c7491252e209244168ba", "hpc/submit_fixed200_continuation.py": "933796be13b8a8eff99a59e512752c66591031bf7c9af8fa17dbb384e9fec9de", "prepared/tuning/manifest.json": "df3ad9c9a2f25615ee3a8054221e392a555f7a377266a1aaa401f90653f47b13", "records/authorization.json": "1b38567991e550ac530f3dbef148b3e347db81a8f1eb71272aa47a9fd8937902", "records/explicit_gru__historical_capacity/tune_branch_group_configs.json": "7cd50af841e0f26722d252615c78c7e66428ff254ce88f79a75eea7902dbc697", "records/scheduler_jobs.json": "cbe1c49086ae15e174634edfaeace1f7108c428055a3b3a28ff9e0c98cd146de", "runs/explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p0003/checkpoint_head.json": "6bd1c528d64e45bac9048a7af853f71831b8e5b921d9078894af32056101b0fd", "runs/explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p0003/config.json": "e41bce67029d44ceb46f41337fb3c9b2dc2cd584a0d72a1c5ec24ed2906c98d2", "runs/explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p0003/continuation_anchor.json": "5550be2ad8d7db9b3cae78bed3f29d0ff1f312528a298b3b30d3090bd370d11c", "runs/explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p0003/failure.json": "d37ea6ab1db2fe12de6e6796e253ba699815bc7d4e54a0a8f03d65446da2dce8", "runs/explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p0003/migration_source.json": "5933bdf798bb1735a159aa0ab729a531ca8c6cbcc5cb92c87c3adedace636e33", "runs/explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p001/checkpoint_head.json": "c0076496d70def9eaa6ed34d914dac55d02a8e30f21451a122aa1d943321b5f5", "runs/explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p001/config.json": "87c07bcd9975441dcab627af8a105a21b0a23ace565d58375f5a185c62f79ac6", "runs/explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p001/continuation_anchor.json": "4ade17fd33699559371783b0c24aaceab612365c441379816b8c3400940307e1", "runs/explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p001/failure.json": "d37ea6ab1db2fe12de6e6796e253ba699815bc7d4e54a0a8f03d65446da2dce8", "runs/explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p001/migration_source.json": "a1db3d43719f9b18b9fcbe09f7c11c29c9a7067e40537bc77f2224ef480703ce", "runs/explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p003/checkpoint_head.json": "ff6c6dae1312238517053fd3e0f2d59d858fbc4e74079533a57f2bcfcac7247e", "runs/explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p003/config.json": "30c77367ce61002dd9ed87dc8ff7d9c3d0e84ba15f81b33c6a6112e5dad2dfac", "runs/explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p003/continuation_anchor.json": "11856601a76b3eb8c78665ea07880d1ea9756c81e452abbc10b8f0941ca26205", "runs/explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p003/failure.json": "d37ea6ab1db2fe12de6e6796e253ba699815bc7d4e54a0a8f03d65446da2dce8", "runs/explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p003/migration_source.json": "ec3b7e0a28f1c9ad0f423054f95e76c492981e7a30038ff0356719f0752abc26", "runs/explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p0003/checkpoint_head.json": "8e93152f72d6656494bf3aee96adf1674a82bc0c56383f7402b564927acf1dfd", "runs/explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p0003/config.json": "20d5f9f6ebeee2ee4abe65d6bcdebc7604575186f207b5043538e74efe20eb3a", "runs/explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p0003/continuation_anchor.json": "99e8daef9c657b6bfff7de2ba00e2422d9fe3775c637f478f1f8ff46b36896e3", "runs/explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p0003/failure.json": "d37ea6ab1db2fe12de6e6796e253ba699815bc7d4e54a0a8f03d65446da2dce8", "runs/explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p0003/migration_source.json": "733d392ad6e000fb940e0fcb40ffde7a7bc5ce2cc91d8b240a65f4854cb29866", "runs/explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p001/checkpoint_head.json": "a63550bac7a913807d7f66da611186889d34d0e81b670697969732cbf5dcd544", "runs/explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p001/config.json": "acde406b06be3d44286afa696303fef885d2e7c6048568357f131738db585859", "runs/explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p001/continuation_anchor.json": "1099ad456f0a933885265d94a5dd60ec81b5b0de26a01835f257966d33f55610", "runs/explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p001/failure.json": "d37ea6ab1db2fe12de6e6796e253ba699815bc7d4e54a0a8f03d65446da2dce8", "runs/explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p001/migration_source.json": "3ed129699b851d84c8fcef972b44353b9f15c8485034ea646b754de529e60f64", "runs/explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p003/checkpoint_head.json": "4b098cb7c50af343eef9f7b5bfb52e4ee117f49b7a1d0e590be88d9469965a96", "runs/explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p003/config.json": "f538348ccde10fab43d407b3991abc55b98a52e7fa3a18b66d23a5c830c25030", "runs/explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p003/continuation_anchor.json": "7f913119608a215f93c79f6a8f4954dc23d67f265bd566b0fa911747e27d2b57", "runs/explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p003/failure.json": "d37ea6ab1db2fe12de6e6796e253ba699815bc7d4e54a0a8f03d65446da2dce8", "runs/explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p003/migration_source.json": "90bd2c651d3517263ffaf17f36f58ad4e7bb78149591de7a61fc20e033a5a751", "runs/explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p0003/checkpoint_head.json": "aac6d5f2e8f36a6ee52f24cff3bf17a66b5216f34969a7029ed5dc55b25e1dc0", "runs/explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p0003/config.json": "78bce15ebedbd4bfa1e309e18fddcd7018ad10380698c99c1d1b89474d324d44", "runs/explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p0003/continuation_anchor.json": "a448485c3d5c76a48f2423a9780edc21bc27bbed466c4529adb8d7f47500d15b", "runs/explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p0003/failure.json": "d37ea6ab1db2fe12de6e6796e253ba699815bc7d4e54a0a8f03d65446da2dce8", "runs/explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p0003/migration_source.json": "0a66d5532543148ea6bb072356634959c88eea2c764e812c0c93944012038fdf", "runs/explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p001/checkpoint_head.json": "3c07078d5733058a08d8528c47ca15539b9dd5e5ff11997a0cd0e2c1a2a7e4f6", "runs/explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p001/config.json": "9fbdceb37265c9927f84318d53357b1b7dce072b1e201f80bf83f71cac38ea6d", "runs/explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p001/continuation_anchor.json": "b61be87a8a2c48cdb472ead2faefaf5536522b13959665e4ce079adf3cbd8778", "runs/explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p001/failure.json": "d37ea6ab1db2fe12de6e6796e253ba699815bc7d4e54a0a8f03d65446da2dce8", "runs/explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p001/migration_source.json": "eead8a33afdd0d33a032713bf17e18c8b8b4895465d08712dc063bbd3d42b52c", "runs/explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p003/checkpoint_head.json": "ea298313794b0916b9ec7b14530815bbf71d43ec49d5af91eb3aaec328bd4379", "runs/explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p003/config.json": "17624be2eeb966dc789afb6822ca7bd25196a73b550d0a349bb6b15a2a0b760b", "runs/explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p003/continuation_anchor.json": "377845e59485972ab455bde9d5f4175e88650ce631f5f95830ace82c837d85fb", "runs/explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p003/failure.json": "d37ea6ab1db2fe12de6e6796e253ba699815bc7d4e54a0a8f03d65446da2dce8", "runs/explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p003/migration_source.json": "cd8d230aac126a77b9b8dad468b469e666a017e07ab4d4bbcfe410de87973325", "runs/explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p0003/checkpoint_head.json": "1eb69a123767566ea69bca8fd96ab9875fd6c502e3a18bf7a63333211f9b14fe", "runs/explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p0003/config.json": "df47a6e34392a7ea1a63f0122c05d6f4166ca8158b86a4271e904eec3899aed3", "runs/explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p0003/continuation_anchor.json": "668a0e2bce5d56d2ba74fb0c131cb5e03c187fd0f101667042ac7402a0059e23", "runs/explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p0003/failure.json": "d37ea6ab1db2fe12de6e6796e253ba699815bc7d4e54a0a8f03d65446da2dce8", "runs/explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p0003/migration_source.json": "511b71b18949c39ff00ad594abd5a928bc7faf334b81451c01e6be255521ffee", "runs/explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p001/checkpoint_head.json": "95b978cd0dfaeb4feba637a3d5290864ad2964b2c89a1c78c3cff55ab01c1755", "runs/explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p001/config.json": "375d4abcf94f0f492a4bf85e0966165ecac81a9b08b6274220f5b17df410b989", "runs/explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p001/continuation_anchor.json": "36ceefea026683c616149164178c8f91ecfc1bb6a312a60949310c0de5ada8cb", "runs/explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p001/failure.json": "d37ea6ab1db2fe12de6e6796e253ba699815bc7d4e54a0a8f03d65446da2dce8", "runs/explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p001/migration_source.json": "e752134c82d7bb945b2ac910c7461b7c7696d3c8f0b77dc02942bc0f1bd2cc03", "runs/explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p003/checkpoint_head.json": "eaa5bbf9cdf27b620afa46af41752d2eb9627dcda558e82c5237fd8d975f8203", "runs/explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p003/config.json": "735d44e8cd1f775cd2aaa1d8c1b4aeef62d2498807f7629730ca9c28ba1ad496", "runs/explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p003/continuation_anchor.json": "aa98f6aa23ba4cdfc9b77a681c19acc1985a4ffd8226eb10ab7da9783a167ee7", "runs/explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p003/failure.json": "f4cd17b9a66cd35e64281bfb9c5f66cee795bf3f1043fe0e7ce475dc8fce8f1f", "runs/explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p003/migration_source.json": "5d8ae5f3b2220dfdc51e8790fa695e5ecc2823ffa7c35db4a7ca6c9caf941003", "scripts/train_supercomputer_case.py": "d14e202074f46e3f0f5d42b7f9d1c3d28cbdb6712d1559428c6222991c3bbd9b", "src/gradient_recovery.py": "7dffed576f32d91d51d8457d1315fa26d57c096946802091271e7d516646421e", "src/runtime.py": "4e42dfe94fd60c50cf0c85a581339e96d2fe7aa053b522b7fdd3e0ef7873087c", "src/training.py": "a7e62dc2aafb87c45a98b4062f90133c554985d3e9185401df8f07d8e24e335c"}, "canonical_model_or_Adam_or_config_or_failure_or_source_writes": false, "canonical_root": "/data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003/sqrt_gru_recovery", "canonical_training_resume": false, "case": "explicit_gru__historical_capacity", "checkpoint_sha256": "cf6826ddeb1779633d0154f4fbc779de94b880d9e1a83464b9b469a7cf11a4fe", "code_hash": "109a24b738c940a00d6f1ec0a9e132f63f9231b779b3931af8f6c12c1770c426", "complete_epochs": 141, "created_at_utc": "2026-11-02T19:04:47.159899+00:00", "diagnostic_backward_exponents": [0, -4, -8, -9, -16, -17, -32, -33], "diagnostic_epoch": 142, "diagnostic_optimizer_updates_only_in_private_in_memory_copy": true, "failed_job": "254778", "interpretation_limit": "scale-invariant zeros alone do not exclude shared underflow; no production numerical change or resumed canonical training is authorized by a diagnostic result alone", "max_epochs_to_replay": 1, "max_replay_seconds": 4500, "no_automatic_repeat": true, "no_new_scientific_experiment_or_validation_or_evaluation_or_hyperparameter_selection": true, "no_original_failure_gate_bypass_or_relaxation": true, "preservation_directory": "/data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003/sqrt_gru_recovery/records/explicit_gru__historical_capacity/repairs/gradient_zero_subnormal_254778_20261102_001", "preservation_verification": "G:\\\\github\\\\pycharm\\\\projects\\\\zhenjiang_complete_comparison_20261006_002\\\\results\\\\fixed200_003_activation_20261020_001\\\\gradient_zero_subnormal_254778_PRESERVATION_VERIFIED_893.json", "preservation_verified_native_sequence": 893, "private_diagnostic_directory": "/data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003/sqrt_gru_recovery/records/explicit_gru__historical_capacity/repairs/gradient_zero_subnormal_254778_20261102_001/diagnostic_replay_20261103_001", "production_function": "unchanged src.training.train_effective_batch; scratch model/Adam loaded from the verified immutable complete checkpoint", "registered_group_order": ["explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p0003", "explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p001", "explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p003", "explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p0003", "explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p001", "explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p003", "explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p0003", "explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p001", "explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p003", "explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p0003", "explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p001", "explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p003"], "replay_source_sha256": "e6f024c70ac1f46282c97fb5b0767df16fe9cd4bc9de5a54730dfd17e66f68b6", "schema": "003-isolated-gradient-replay-plan-v1", "target_exp_id": "explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p003", "target_selection_evidence": "The frozen train_group iterates the registered group order. The last member alone has141 complete epochs while all preceding11 have142; target is the first incomplete session in epoch142. This is a diagnostic candidate, not a proved first failing batch.", "training_manifest_file_sha256": "df3ad9c9a2f25615ee3a8054221e392a555f7a377266a1aaa401f90653f47b13", "training_manifest_sha256": "3bef2654f180185d2e36fae41e5f645932770e63189d0fce19c23374157aa42f"}');source='"""Bounded diagnostic replay from an immutable complete model/Adam copy.\n\nUsage in the existing nh_final A40 allocation: python -B this.py --plan plan.json\nOnly the private diagnostic directory receives output. No canonical epoch,\nfailure marker, configuration, model, optimizer or source file is written.\n"""\nimport argparse\nimport copy\nimport dataclasses\nimport datetime\nimport fcntl\nimport hashlib\nimport json\nimport os\nfrom pathlib import Path\nimport sys\nimport time\nimport traceback\n\n\ndef file_sha(path):\n    value = hashlib.sha256()\n    with Path(path).open(\'rb\') as handle:\n        for chunk in iter(lambda: handle.read(1024 * 1024), b\'\'):\n            value.update(chunk)\n    return value.hexdigest()\n\n\ndef main():\n    parser = argparse.ArgumentParser(description=__doc__)\n    parser.add_argument(\'--plan\', type=Path, required=True)\n    plan_path = parser.parse_args().plan.resolve()\n    plan = json.loads(plan_path.read_bytes())\n    dest = plan_path.parent\n    root = Path(plan[\'canonical_root\'])\n    preserved = Path(plan[\'preservation_directory\'])\n    case, exp = plan[\'case\'], plan[\'target_exp_id\']\n    record = root / \'records\' / case\n    with (dest / \'COMPUTE_ATTEMPT.json\').open(\'x\') as attempt:\n        json.dump({\'diagnostic_job\': os.environ.get(\'SLURM_JOB_ID\'),\n                   \'plan_sha256\': file_sha(plan_path),\n                   \'replay_allowed\': False}, attempt)\n    report = {\n        \'schema\': \'003-isolated-gradient-replay-v1\', \'case\': case,\n        \'failed_canonical_job\': plan[\'failed_job\'], \'target_exp_id\': exp,\n        \'diagnostic_job\': os.environ.get(\'SLURM_JOB_ID\'),\n        \'at_utc\': datetime.datetime.now(datetime.timezone.utc).isoformat(),\n        \'plan_sha256\': file_sha(plan_path), \'status\': \'diagnostic_initializing\',\n        \'canonical_training_resumed\': False, \'canonical_files_written\': False,\n        \'production_guard_changed\': False, \'failure_markers_removed\': False,\n        \'root_cause_proved\': False, \'diagnostic_optimizer_steps\': 0,\n        \'scale_trials\': [], \'errors\': [],\n    }\n    initial_files = {}\n\n    def status():\n        temporary = dest / \'STATUS.json.tmp\'\n        temporary.write_text(json.dumps(report, sort_keys=True, indent=2) + \'\\n\')\n        temporary.replace(dest / \'STATUS.json\')\n\n    def capture_original_metadata():\n        result = {}\n        for name in plan[\'canonical_metadata_hashes\']:\n            path = root / name\n            result[name] = file_sha(path)\n        return result\n\n    try:\n        assert root.is_dir() and preserved.is_dir()\n        initial_files = capture_original_metadata()\n        assert initial_files == plan[\'canonical_metadata_hashes\']\n        assert str(json.loads((root / \'records/scheduler_jobs.json\').read_bytes())[case]) == plan[\'failed_job\']\n        with (record / \'writer.lock\').open(\'rb\') as writer:\n            fcntl.flock(writer, fcntl.LOCK_EX | fcntl.LOCK_NB)\n            report[\'canonical_writer_lock_exclusively_held\'] = True\n            sys.path.insert(0, str(root))\n            import torch\n            from src import training as t\n            from src.continuation import load_continuation, validate_continuation\n            from src.contracts import combine_batches, slice_batch\n            from src.differentiable_filter import make_noise, StabilityLedger\n            from src.execution import bound_device, device_identity, move_batch, move_parts\n            from src.gradient_recovery import rng_state, restore_rng, tensor_hash\n            from src.models import make_parts, parameters\n            from src.runtime import load_stage, fit_stage_stats, prepare_windows, stats_record, load_whitening\n            from src.scheduler import code_identity, digest_json\n            from src.state_estimators import make_branches, configure_branch, hash_module\n\n            t.deterministic_runtime()\n            torch.set_num_threads(4)\n            auth = json.loads((root / \'records/authorization.json\').read_bytes())\n            protocol = json.loads((root / \'configs/protocol-v3.json\').read_bytes())\n            registry = json.loads((root / \'configs/registry-v3.json\').read_bytes())\n            assert code_identity() == auth[\'code_hash\'] == plan[\'code_hash\']\n            assert file_sha(root / \'configs/protocol-v3.json\') == auth[\'protocol_sha256\']\n            runs = [run for run in registry[\'runs\'] if run[\'budget_group\'] == case + \'__tune_branch_group\' and run[\'status\'] != \'alias\']\n            assert [run[\'exp_id\'] for run in runs] == plan[\'registered_group_order\']\n            assert runs[-1][\'exp_id\'] == exp\n            run = runs[-1]\n            saved = preserved / \'members\' / exp\n            assert file_sha(saved / \'continuation.pt\') == plan[\'checkpoint_sha256\']\n            state, config, checkpoint_report, config_raw, unused = load_continuation(saved, 200, \'cpu\', True)\n            assert checkpoint_report[\'completed_epochs\'] == plan[\'complete_epochs\']\n            effective = config[\'effective_config\']\n            assert effective[\'code_hash\'] == auth[\'code_hash\']\n            assert effective[\'budget_policy_hash\'] == digest_json(protocol[\'training\'])\n            assert effective[\'method\'] == run[\'method\'] == \'filter_joint\'\n            assert effective[\'learning_rate\'] == run[\'learning_rate\'] == .003\n            assert effective[\'optimizer\'] == \'Adam\'\n            assert effective[\'loss\'] == \'high_water_weighted_station_equal_mae_cm\'\n            device = bound_device(effective)\n            assert device_identity(device) == auth[\'device_identity\']\n            report[\'device_identity\'] = device_identity(device)\n            member_case = next(item for item in protocol[\'cases\'] if item[\'family\'] + \'__\' + item[\'capacity\'] == case)\n            parts = make_parts(member_case[\'family\'], member_case[\'capacity\'], run[\'seed\'])\n            parts = make_branches(parts, run[\'seed\'] + 100000)[run[\'method\']]\n            noise = make_noise(parts.state_dim)\n            whitening = load_whitening(effective[\'whitening\'], effective[\'whitening_hash\'])\n            configure_branch(parts, noise, run[\'method\'])\n            whitening = move_parts(parts, noise, whitening, device)\n            optimizer = t.make_optimizer(parts, noise, effective[\'learning_rate\'])\n            validate_continuation(state, hashlib.sha256(config_raw).hexdigest(), 200,\n                                  t.snapshot_parts(parts, noise), optimizer, True)\n            t.restore_parts(parts, state[\'current\'], noise)\n            optimizer.load_state_dict(state[\'optimizer\'])\n            assert hash_module(parts.initializer) == effective[\'initializer_hash\']\n            report[\'original_complete_model_and_Adam_loaded\'] = True\n            report[\'original_complete_checkpoint_sha256\'] = plan[\'checkpoint_sha256\']\n            report[\'original_completed_epochs\'] = len(state[\'values\'])\n            report[\'original_Adam_steps\'] = checkpoint_report[\'optimizer_steps\']\n            report[\'original_model_dtypes_preserved\'] = True\n            assert file_sha(root / \'prepared/tuning/manifest.json\') == plan[\'training_manifest_file_sha256\']\n            manifest = json.loads((root / \'prepared/tuning/manifest.json\').read_bytes())\n            assert digest_json(manifest) == plan[\'training_manifest_sha256\']\n            train = load_stage(manifest, \'tuning_train\')\n            stats = fit_stage_stats(train, manifest)\n            assert digest_json(stats_record(stats)) == effective[\'normalization_hash\']\n            windows, times = prepare_windows(train, stats)\n            epoch = len(state[\'values\']) + 1\n            assert epoch == plan[\'diagnostic_epoch\']\n            ids, shuffle_sha = t.epoch_indices(times, run[\'seed\'], epoch)\n            micro = effective.get(\'training_contract\', {}).get(\'initial_micro_batch\', 2)\n            report.update(status=\'diagnostic_replaying_original_partial_epoch\',\n                          epoch=epoch, shuffle_sha256=shuffle_sha,\n                          training_windows=len(ids), micro_batch=micro,\n                          effective_batch=16, validation_or_evaluation_loaded=False)\n            status()\n            deadline = time.monotonic() + plan[\'max_replay_seconds\']\n            trainable = list(parameters(parts, noise, True))\n            names = {}\n            for module_name in [\'initializer\', \'encoder\', \'process\', \'readout\']:\n                module = getattr(parts, module_name)\n                if module is not None:\n                    names.update({id(value): module_name + \'.\' + name for name, value in module.named_parameters()})\n            names.update({id(getattr(noise, name)): \'noise.\' + name for name in [\'raw_q\', \'raw_r\', \'raw_p0\']})\n            named = [(names[id(value)], value) for value in trainable]\n\n            def steps():\n                return [int(item[\'step\'].item() if torch.is_tensor(item[\'step\']) else item[\'step\']) for item in optimizer.state.values()]\n\n            def gradient_report():\n                output = {}\n                for name, parameter in named:\n                    value = parameter.grad\n                    if value is None:\n                        output[name] = {\'missing\': True}\n                        continue\n                    absolute = value.detach().abs()\n                    finite = torch.isfinite(value)\n                    nonzero = absolute[finite & (absolute > 0)]\n                    zeros = (value == 0).reshape(-1)\n                    output[name] = {\n                        \'shape\': list(value.shape), \'dtype\': str(value.dtype),\n                        \'elements\': value.numel(), \'nonfinite\': int((~finite).sum()),\n                        \'zero\': int(zeros.sum()),\n                        \'subnormal_nonzero\': int(((absolute > 0) & (absolute < torch.finfo(value.dtype).tiny)).sum()),\n                        \'minimum_nonzero_absolute\': float(nonzero.min()) if nonzero.numel() else None,\n                        \'first_zero_flat_indices\': torch.nonzero(zeros).flatten()[:32].cpu().tolist(),\n                    }\n                return output\n\n            for start in range(0, len(ids), 16):\n                if time.monotonic() >= deadline:\n                    raise TimeoutError(\'bounded isolated replay limit reached; no automatic repeat\')\n                batch_ids = ids[start:start + 16]\n                batch = move_batch(combine_batches([windows[index] for index in batch_ids]), device)\n                initial_rng = rng_state()\n                before_steps = steps()\n                try:\n                    t.train_effective_batch(parts, noise, whitening, run[\'method\'], batch, stats, optimizer, micro)\n                except FloatingPointError as error:\n                    report[\'observed_error\'] = str(error)\n                    report[\'failed_batch_start\'] = start\n                    report[\'failed_batch_window_indices\'] = [int(index) for index in batch_ids]\n                    report[\'failed_batch_times\'] = [str(times[index]) for index in batch_ids]\n                    report[\'failing_call_Adam_steps_unchanged\'] = steps() == before_steps\n                    report[\'gradient_at_original_guard_failure\'] = gradient_report()\n                    if str(error) != \'zero or subnormal gradient needs separate underflow diagnosis\':\n                        raise\n                    assert report[\'failing_call_Adam_steps_unchanged\']\n                    with (dest / \'failing_batch_model_Adam_fixture.pt\').open(\'xb\') as handle:\n                        torch.save({\'current\': t.snapshot_parts(parts, noise),\n                                    \'optimizer\': copy.deepcopy(optimizer.state_dict()),\n                                    \'batch\': {field.name: getattr(batch, field.name).detach().cpu() for field in dataclasses.fields(batch)},\n                                    \'stats\': stats_record(stats), \'rng_before_batch\': initial_rng,\n                                    \'source_checkpoint_sha256\': plan[\'checkpoint_sha256\'],\n                                    \'epoch\': epoch, \'batch_start\': start,\n                                    \'diagnostic_only_not_a_canonical_checkpoint\': True}, handle)\n                    report[\'fixture_sha256\'] = file_sha(dest / \'failing_batch_model_Adam_fixture.pt\')\n                    gradients_by_scale = {}\n                    endpoint = (1 + batch.high_mask[:, 24:].double()).sum((0, 1))\n                    for exponent in plan[\'diagnostic_backward_exponents\']:\n                        if time.monotonic() >= deadline:\n                            raise TimeoutError(\'bounded scale diagnosis limit reached\')\n                        restore_rng(initial_rng)\n                        optimizer.zero_grad(set_to_none=True)\n                        signature = []\n                        ledger = StabilityLedger()\n                        for offset in range(0, len(batch.history), micro):\n                            sub = slice_batch(batch, slice(offset, offset + micro))\n                            prediction = t.branch_prediction(parts, noise, whitening, run[\'method\'], sub, ledger)\n                            loss = t.weighted_mae_cm(prediction, sub.targets[:, 24:], sub.high_mask[:, 24:], stats, endpoint)\n                            assert torch.isfinite(loss)\n                            signature.append([tensor_hash(prediction), float(loss.detach()).hex()])\n                            (loss if exponent == 0 else loss * (2. ** exponent)).backward()\n                        observed = gradient_report()\n                        gradients_by_scale[str(exponent)] = {name: parameter.grad.detach().cpu().clone() if parameter.grad is not None else None for name, parameter in named}\n                        report[\'scale_trials\'].append({\'exponent\': exponent, \'forward_loss_signature\': signature, \'gradients\': observed})\n                    with (dest / \'diagnostic_gradients_by_scale.pt\').open(\'xb\') as handle:\n                        torch.save(gradients_by_scale, handle)\n                    report[\'gradient_scale_fixture_sha256\'] = file_sha(dest / \'diagnostic_gradients_by_scale.pt\')\n                    report[\'all_trial_forward_and_unscaled_losses_identical\'] = all(trial[\'forward_loss_signature\'] == report[\'scale_trials\'][0][\'forward_loss_signature\'] for trial in report[\'scale_trials\'])\n                    report[\'status\'] = \'original_zero_subnormal_guard_reproduced_fixture_and_named_gradient_scale_evidence_saved\'\n                    report[\'root_cause_proved\'] = False\n                    report[\'interpretation_limit\'] = \'Matching zero positions at adjacent scales alone cannot exclude shared underflow; no gate relaxation or production resumption is justified by this diagnostic alone.\'\n                    break\n                report[\'diagnostic_optimizer_steps\'] += 1\n                if report[\'diagnostic_optimizer_steps\'] % 100 == 0:\n                    status()\n            else:\n                report[\'status\'] = \'original_failure_not_reproduced_within_one_original_epoch_no_repeat\'\n            report[\'final_diagnostic_Adam_steps\'] = steps()\n    except Exception as error:\n        report[\'errors\'].append({\'type\': type(error).__name__, \'message\': str(error), \'traceback\': traceback.format_exc()})\n        report[\'status\'] = \'isolated_diagnostic_stopped_requires_evidence_review_no_repeat\'\n    finally:\n        report[\'finished_at_utc\'] = datetime.datetime.now(datetime.timezone.utc).isoformat()\n        if initial_files:\n            report[\'canonical_original_metadata_unchanged\'] = capture_original_metadata() == initial_files\n        report[\'canonical_training_resumed\'] = False\n        report[\'scientific_repair_or_recovery_confirmed\'] = False\n        status()\n        with (dest / \'REPORT.json\').open(\'x\') as handle:\n            json.dump(report, handle, sort_keys=True, indent=2)\n            handle.write(\'\\n\')\n        print(\'GRU_ISOLATED_GRADIENT_REPLAY_JSON \' + json.dumps(report, sort_keys=True), flush=True)\n    return 0 if report[\'status\'].startswith(\'original_zero_subnormal_guard_reproduced\') else 2\n\n\nif __name__ == \'__main__\':\n    raise SystemExit(main())\n';batch='#!/usr/bin/env bash\n#SBATCH --job-name=zj003_grad_diag_254778\n#SBATCH --no-requeue\n#SBATCH -p hgpu4\n#SBATCH --nodelist=ngu102\n#SBATCH --nodes=1\n#SBATCH --ntasks=1\n#SBATCH --cpus-per-task=4\n#SBATCH --gres=gpu:1\n#SBATCH --time=02:00:00\n#SBATCH --time-min=02:00:00\n#SBATCH --output=/data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003/sqrt_gru_recovery/records/explicit_gru__historical_capacity/repairs/gradient_zero_subnormal_254778_20261102_001/diagnostic_replay_20261103_001/diagnostic_%j.out\nset -eo pipefail\nsource /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh\nconda activate nh_final\nset -u\nexport PYTHONDONTWRITEBYTECODE=1\nexport OMP_NUM_THREADS=4\nexport MKL_NUM_THREADS=4\nexport OPENBLAS_NUM_THREADS=4\nexport CUBLAS_WORKSPACE_CONFIG=:4096:8\ncd /data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003/sqrt_gru_recovery\npython -B -u /data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003/sqrt_gru_recovery/records/explicit_gru__historical_capacity/repairs/gradient_zero_subnormal_254778_20261102_001/diagnostic_replay_20261103_001/replay.py --plan /data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003/sqrt_gru_recovery/records/explicit_gru__historical_capacity/repairs/gradient_zero_subnormal_254778_20261102_001/diagnostic_replay_20261103_001/plan.json\n'
root=Path(plan['canonical_root']);record=root/'records'/plan['case'];folder=Path(plan['private_diagnostic_directory']);slurm=Path('/usr/local/globle/softs/slurm/19.05.4.1/bin')
response={'schema':'003-isolated-gradient-diagnostic-submission-v1','case':plan['case'],'failed_canonical_job':plan['failed_job'],'diagnostic_directory':str(folder),'at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'job_id':None,'status':'not_submitted','canonical_training_resumed':False,'production_source_or_guards_changed':False,'errors':[]}
def sha(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
 return h.hexdigest()
def write_new(path,value):
 with path.open('x') as f:json.dump(value,f,sort_keys=True,indent=2);f.write(chr(10))
def query(args):
 p=subprocess.run(list(map(str,args)),capture_output=True,text=True,timeout=60)
 return {'command':list(map(str,args)),'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
created=False
try:
 preservation=json.loads((Path(plan['preservation_directory'])/'DIAGNOSIS.json').read_bytes())
 assert preservation['status']=='native_failure_and_complete_model_Adam_checkpoint_bytes_preserved_no_training_or_gate_change' and not preservation['errors']
 q=query([slurm/'squeue','-h','-u','sunyiq','-o','%i|%j|%T|%Z|%o']);response['queue']=q;assert q['returncode']==0
 assert not any(plan['case'] in row or str(root) in row for row in q['stdout'].splitlines())
 account=query([slurm/'sacct','-n','-X','-j',plan['failed_job'],'--format=JobID,State,ExitCode,Start,End,NodeList','-P']);response['failed_job_accounting']=account;rows=[row.split('|') for row in account['stdout'].splitlines() if row.startswith(plan['failed_job']+'|')];assert account['returncode']==0 and len(rows)==1 and rows[0][1:3]==['FAILED','1:0']
 with (record/'writer.lock').open('rb') as writer:
  fcntl.flock(writer,fcntl.LOCK_EX|fcntl.LOCK_NB)
  assert all(sha(root/name)==digest for name,digest in plan['canonical_metadata_hashes'].items())
  saved=Path(plan['preservation_directory'])/'members'/plan['target_exp_id']/'continuation.pt';assert sha(saved)==plan['checkpoint_sha256']
  assert hashlib.sha256(source.encode()).hexdigest()==plan['replay_source_sha256']
  folder.mkdir(parents=True,exist_ok=False);created=True
  with (folder/'replay.py').open('x') as f:f.write(source)
  write_new(folder/'plan.json',plan)
  with (folder/'run.slurm').open('x') as f:f.write(batch)
  write_new(folder/'STATUS.json',{'status':'submission_prepared_waiting_original_scheduler','canonical_training_resumed':False,'root_cause_proved':False})
  write_new(folder/'SUBMISSION_ATTEMPT.json',{'plan_sha256':sha(folder/'plan.json'),'replay_source_sha256':sha(folder/'replay.py'),'batch_sha256':sha(folder/'run.slurm'),'queue':q,'accounting':account,'mutation_retry_allowed':False})
  result=query([slurm/'xbatch',folder/'run.slurm']);write_new(folder/'SUBMISSION_RESPONSE.json',result)
  if result['returncode']:raise RuntimeError('diagnostic submission uncertain; preserve and reconcile read-only, no retry')
  match=re.fullmatch(r'Submitted batch job ([0-9]+)\s*',result['stdout'])
  assert match,'diagnostic scheduler response uncertain; do not retry'
  response.update(status='isolated_diagnostic_submitted_once',job_id=match.group(1),target_exp_id=plan['target_exp_id'],diagnostic_epoch=plan['diagnostic_epoch'],replay_source_sha256=sha(folder/'replay.py'),plan_sha256=sha(folder/'plan.json'),batch_sha256=sha(folder/'run.slurm'),actual_compute_start_confirmed=False)
  write_new(folder/'SUBMISSION_CONFIRMED.json',response)
except Exception as exc:
 response['status']='diagnostic_submission_not_confirmed_reconcile_readonly_no_replay';response['errors'].append({'type':type(exc).__name__,'message':str(exc),'traceback':traceback.format_exc()})
finally:
 if created:write_new(folder/'PUBLICATION_RESPONSE.json',response)
 print('GRU_NUMERICAL_DIAGNOSTIC_SUBMISSION_JSON '+json.dumps(response,sort_keys=True),flush=True)

SUBMIT_ISOLATED_GRU_GRADIENT_REPLAY

#!/usr/bin/env bash
set -eo pipefail
python3 - <<'READ_FIXED200_003'
"""Read fixed-200 allocation and committed-epoch evidence without loading tensors.

Example on HPC: python -B read_status.py
Reads the two activated cases, checkpoint heads/events and small record files.
Prints a status snapshot only; no scheduler submission or source writes.
"""
import datetime
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path('/data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003')
SLURM = Path('/usr/local/globle/softs/slurm/19.05.4.1/bin')
CASES = {'legacy_lstm__historical_capacity': 'base',
         'explicit_gru__historical_capacity': 'sqrt_gru_recovery'}


def read(path):
    return json.loads(path.read_bytes())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def query(command):
    result = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=45)
    return {'command': list(map(str, command)), 'returncode': result.returncode,
            'stdout': result.stdout, 'stderr': result.stderr}


def final_stage_metadata(runtime, record, case, row):
    """Read bounded final-stage records and committed heads; never load tensors."""
    result = {'group_outcomes': {}, 'physical_members': {}, 'aliases': {},
              'checkpoints_loaded': False, 'scientific_files_changed': False}
    for suffix in ('tune_branch_group', 'final_foundation_group', 'all_final_branches_group'):
        path = record / (suffix + '_outcome.json')
        if not path.exists():
            continue
        outcome = read(path)
        seal = outcome['seal']
        result['group_outcomes'][suffix] = {
            'path': str(path), 'sha256': sha(path),
            'seal': {key: seal[key] for key in ('group_id', 'member_ids', 'epochs',
                     'checkpoint_hashes', 'status', 'budget_final', 'evidence_sha256')},
            'members': {name: {key: value.get(key) for key in ('case', 'seed', 'method',
                'type', 'epochs', 'budget_final', 'best_epoch', 'checkpoint_sha256',
                'checkpoint_path', 'learning_rate', 'normalization_hash', 'whitening_hash',
                'initializer_hash', 'device_identity')} for name, value in outcome['members'].items()}}
    path = record / 'aliases_before_final_training.json'
    if path.exists():
        aliases = read(path)
        result['alias_record_sha256'] = sha(path)
        result['effective_configs_sha256_before_aliases'] = aliases['effective_configs_sha256']
        result['aliases'] = {name: target for name, target in aliases['aliases'].items()
                             if name.startswith(case + '__')}
    path = record / 'all_final_branches_group_configs.json'
    if not path.exists():
        return result
    configs = read(path)
    result['physical_configs_sha256'] = sha(path)
    for name, config in configs.items():
        assert name.startswith(case + '__') and name not in result['aliases']
        run = config['registration']
        effective = config['effective_config']
        folder = runtime / 'runs' / name
        item = {'method': run['method'], 'type': run['type'], 'seed': run['seed'],
                'learning_rate': effective['learning_rate'],
                'parent_run_id': effective['parent_run_id'], 'parent_hash': effective['parent_hash'],
                'folder_exists': folder.exists(), 'continuation_file_exists': (folder / 'continuation.pt').is_file()}
        config_path = folder / 'config.json'
        if config_path.exists():
            item['config_sha256'] = sha(config_path)
            item['frozen_config_matches'] = read(config_path) == config
        head_path = folder / 'checkpoint_head.json'
        if head_path.exists():
            head = read(head_path)
            assert 0 <= head['completed_epochs'] <= 200
            item['head'] = head
            event_path = folder / 'checkpoint_events' / (head['checkpoint_sha256'][:16] + '.json')
            if head['completed_epochs'] > 0 and event_path.exists():
                event = read(event_path)
                assert event['completed_epochs'] == head['completed_epochs']
                assert event['checkpoint_sha256'] == head['checkpoint_sha256']
                assert event['previous_epochs'] == head['completed_epochs'] - 1
                item['latest_complete_epoch_event'] = event
            anchor_path = folder / 'continuation_anchor.json'
            if anchor_path.exists():
                item['anchor_sha256'] = sha(anchor_path)
                item['anchor'] = read(anchor_path)
                item['head_anchor_matches'] = head.get('anchor_sha256') == item['anchor_sha256']
        step_path = folder / 'first_optimizer_step.json'
        if step_path.exists():
            step = read(step_path)
            item['first_optimizer_step'] = {key: step.get(key) for key in
                ('status', 'epoch', 'training_batch_size', 'method', 'device_identity')}
        failure_path = folder / 'failure.json'
        if failure_path.exists():
            row['failure_records'][name] = read(failure_path)
        result['physical_members'][name] = item
    result['physical_member_count'] = len(configs)
    result['logical_member_count'] = len(configs) + len(result['aliases'])
    result['complete200_physical_members'] = sum(
        value.get('head', {}).get('completed_epochs') == 200 for value in result['physical_members'].values())
    result['complete_member_epochs'] = sum(
        value.get('head', {}).get('completed_epochs', 0) for value in result['physical_members'].values())
    result['all_alias_targets_are_physical'] = all(target in configs for target in result['aliases'].values())
    return result


report = {'schema': 'fixed200-activation-status-v1', 'root': str(ROOT),
          'checked_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'checkpoints_loaded': False, 'evaluation_values_read': False, 'cases': {}, 'errors': []}
report['queue'] = query([SLURM / 'squeue', '-h', '-u', 'sunyiq', '-o', '%i|%j|%T|%Z|%e|%l|%N|%R'])
for case, variant in CASES.items():
    runtime = ROOT / variant
    record = runtime / 'records' / case
    try:
        initial = read(record / 'activation_starting_members.json')
        job = str(read(runtime / 'records/scheduler_jobs.json')[case])
        auth = read(runtime / 'records/authorization.json')
        row = {'case': case, 'root': str(runtime), 'job_id': job,
               'authorization_sha256': sha(runtime / 'records/authorization.json'),
               'authorization': auth, 'migration_manifest': read(record / 'migration_manifest.json'),
               'data_preparation_complete': read(runtime / 'records/data_preparation_complete.json'),
               'scheduler_script': (runtime / 'hpc/fixed200_case.slurm').read_text(),
               'device_identity': auth['device_identity'], 'members': {},
               'queue_rows': [line for line in report['queue']['stdout'].splitlines() if line.startswith(job + '|')],
               'failure_records': {}}
        allocation = record / ('runtime_binding_' + job + '.json')
        if allocation.exists():
            row['runtime_binding'] = read(allocation)
            assert row['runtime_binding']['device_identity'] == auth['device_identity']
        for name in ('progress.json', 'training_complete.json', 'selected_rates_2021.json',
                     'scheduler_slice_end_' + job + '.json', 'startup_path_recovery_' + job + '.json',
                     'submission_context_repair.confirmed.json'):
            if (record / name).exists():
                row[name] = read(record / name)
        source_outcome = record / 'tune_foundation_group_outcome.json'
        if source_outcome.exists():
            source = read(source_outcome)
            row['tuning_foundation_source'] = {'seal_epochs': source['seal']['epochs'],
                'members': {name: {'epochs': value['epochs'], 'best_epoch': value['best_epoch'],
                           'checkpoint_sha256': value['checkpoint_sha256']}
                            for name, value in source['members'].items()}}
            assert row['tuning_foundation_source']['seal_epochs'] == 400
        for member, start in initial.items():
            folder = runtime / 'runs' / member
            head = read(folder / 'checkpoint_head.json')
            anchor = read(folder / 'continuation_anchor.json')
            assert anchor['initial_checkpoint_sha256'] == start['checkpoint_sha256']
            assert anchor['initial_epochs'] == start['completed_epochs']
            assert sha(folder / 'config.json') == start['config_sha256']
            assert sha(folder / 'migration_source.json') == start['receipt_sha256']
            n = head['completed_epochs']
            assert start['completed_epochs'] <= n <= 200
            item = {'initial_epochs': start['completed_epochs'], 'completed_epochs': n,
                    'new_complete_epochs': n - start['completed_epochs'],
                    'checkpoint_sha256_from_committed_head': head['checkpoint_sha256'],
                    'initial_identity_and_config_preserved': True}
            if n > start['completed_epochs']:
                event = read(folder / 'checkpoint_events' / (head['checkpoint_sha256'][:16] + '.json'))
                assert event['checkpoint_sha256'] == head['checkpoint_sha256']
                assert event['completed_epochs'] == n and event['previous_epochs'] == n - 1
                assert event['anchor_sha256'] == head['anchor_sha256'] == sha(folder / 'continuation_anchor.json')
                item['new_epoch_event'] = event
            if (folder / 'failure.json').exists():
                row['failure_records'][member] = read(folder / 'failure.json')
            row['members'][member] = item
        row['new_complete_member_epochs'] = sum(v['new_complete_epochs'] for v in row['members'].values())
        row['members_with_new_complete_epoch'] = sum(v['new_complete_epochs'] > 0 for v in row['members'].values())
        row['tune_branch_200_complete_members'] = sum(v['completed_epochs'] == 200 for v in row['members'].values())
        row['actual_training_progress_confirmed'] = bool(row.get('runtime_binding') and row['new_complete_member_epochs'] > 0)
        try:
            row['final_stage'] = final_stage_metadata(runtime, record, case, row)
        except Exception as error:
            row['final_stage_metadata_error'] = {'type': type(error).__name__, 'message': str(error)}
        row['logs'] = []
        for path in (runtime / 'logs').glob('*_' + job + '.out'):
            with path.open('rb') as handle:
                handle.seek(max(0, path.stat().st_size - 7000))
                row['logs'].append({'path': str(path), 'tail': handle.read().decode('utf-8', errors='replace')})
        report['cases'][case] = row
    except Exception as error:
        report['errors'].append({'case': case, 'type': type(error).__name__, 'message': str(error)})
jobs = [v['job_id'] for v in report['cases'].values()]
if jobs:
    report['accounting'] = query([SLURM / 'sacct', '-n', '-X', '-j', ','.join(jobs),
                                  '--format=JobID,State,ExitCode,Start,End,NodeList', '-P'])
report['summary'] = {'cases': len(report['cases']),
    'cases_with_new_complete_epoch': sum(v['actual_training_progress_confirmed'] for v in report['cases'].values()),
    'new_complete_member_epochs': sum(v['new_complete_member_epochs'] for v in report['cases'].values()),
    'members_with_new_complete_epoch': sum(v['members_with_new_complete_epoch'] for v in report['cases'].values()),
    'tune_branch_200_complete_members': sum(v['tune_branch_200_complete_members'] for v in report['cases'].values()),
    'failure_files': sum(len(v['failure_records']) for v in report['cases'].values())}
print(json.dumps(report, sort_keys=True), flush=True)

READ_FIXED200_003
