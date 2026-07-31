# 历史连续多尺度气象模型版本09正式输入阶段实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不触碰正式评估观测的前提下，构建、封存并独立审核版本09所需的531流域 Maurer 气象、27项静态属性和仅训练期流量目标。

**Architecture:** 将授权、气象存储、可信目标导出、归一化、输入重载和独立审核拆成可单独拒绝的组件。气象按冻结流域顺序写入只读 NumPy 内存映射文件；可信目标进程是唯一允许读取原始流量的组件；候选训练代码以后只能读取封存输入，不得读取原始流量目录。

**Tech Stack:** Python 3、NumPy、Pandas、PyTorch、psutil、pytest、Git。

## Global Constraints

- 未收到用户在当前对话中逐字回复
  `批准版本09正式输入生成阶段；不批准训练、正式预测或评分。`
  前，不执行本计划的任何代码或数据生成步骤。
- 上述无换行 UTF-8 文本的 SHA-256 必须为
  `a9ba69f6ee0fcd17bcfc5313140c98bdd483ad6b9f7a3ef3d7d3bcdfe46a4c7d`。
- 冻结协议文件保持
  `src/26_historical_band_experts/configs/formal_v09_protocol.json`，
  SHA-256 保持
  `b81bce8fc83aa8c4cad2d36475c6e6da553567f54b5f5f8d52457006fb446ed8`。
- 不修改`src/fair_benchmark/frozen/`、`src/fair_benchmark/score.py`、流域列表、切分文件或冻结规范。
- 动态输入只有5项 Maurer：
  `PRCP(mm/day)`、`Tmin(C)`、`Tmax(C)`、`SRAD(W/m2)`、`Vp(Pa)`。
- 静态输入只有冻结文件中的27项属性，顺序采用`data.py::STATIC_COLUMNS`。
- 气象期为`1980-01-01`至`2008-09-30`，每个流域10,501天。
- 训练目标期为`1999-10-01`至`2008-09-30`，每个流域3,288天；不得输出任何正式评估期流量。
- 气象文件必须递归查找；不得根据测站编号前两位推导18个水文分区目录。
- 正式气象根目录固定为
  `G:/github/pycharm/projects/neuralhydrology/data/camels_us/basin_mean_forcing/maurer`；
  不得从`data/camels_us`整体、`full/basin_mean_forcing/maurer`或
  `_maurer_header_fix_backup_20260616`递归选文件。
- 上述规范根目录中按冻结流域顺序组合的531个源文件SHA-256摘要树固定为
  `59665c3f34a42b6c6ba7f6dd7696481ef56a9ac0d30eacad116b4fee6bcb83fa`。
  `full`副本有3个旧文件头，与规范根目录不同，不能作为等价来源。
- 531个已盘点气象文件均为10,597行，含4行文件头和10,593个逐日记录，覆盖`1980-01-01`至`2008-12-31`。
- 所需531个原始气象文件合计约`0.309 GiB`；输出气象 float32 数组有效载荷为
  `111,520,620`字节，即`106.35 MiB`，`.npy`文件还包含版本相关的文件头。
- 训练目标 float32 数组有效载荷为`6,983,712`字节，即`6.66 MiB`，`.npy`文件还包含文件头；
  按60流域既有文件外推，目标逗号分隔文件约`66.44 MiB`。
- 长任务启动可用物理内存至少`12.68 GiB`；运行中至少保留`8 GiB`；当前进程驻留内存不超过`6 GiB`；单次计划分配不超过`512 MiB`。
- 真实输出根目录固定为
  `results/26_historical_band_experts/formal_v09/input_attempt_01`，
  临时构建目录固定为同父目录下的`input_attempt_01.building`；任一目录已存在时拒绝覆盖。
- 本计划只到输入独立审核结束；不包含严格嵌套训练、三个模型家族训练、正式预测或评分。
- 可信目标导出模块含有正式评分服务禁止的原始流量标记，永远不得放入未来评分命令的
  `--experiment-dir`。未来评分必须显式指向一个另行封存的候选源码包；该包必须包含训练和预测
  实际使用的全部传递依赖，但不得包含可信输入工具，并在评分前证明禁止标记扫描为零。

---

### Task 1: 增加独立的阶段授权凭据

**Files:**
- Create: `src/26_historical_band_experts/stage_authorization_v09.py`
- Modify: `src/26_historical_band_experts/launch_gate_v09.py`
- Create after direct approval: `src/26_historical_band_experts/configs/formal_v09_input_authorization.json`
- Test: `src/26_historical_band_experts/tests/test_stage_authorization_v09.py`
- Modify: `src/26_historical_band_experts/tests/test_launch_gate_v09.py`

**Interfaces:**
- Consumes: 冻结协议文件、协议 SHA-256、动作名称和单独的授权JSON。
- Produces: `load_stage_authorization_v09(path, *, action) -> dict`。
- Produces:
  `consume_stage_authorization_v09(receipt, *, action, consumption_path, launch_evidence) -> dict`。
- Produces: 扩展后的
  `assert_launch_allowed_v09(config, action, estimated_peak_bytes, snapshot=None, stage_authorization=None) -> dict`。

- [ ] **Step 1: 写授权凭据失败测试**

```python
def _receipt():
    return {
        "receipt_id": "A09-INPUT-01",
        "attempt_id": "input_attempt_01",
        "output_root": "results/26_historical_band_experts/formal_v09/input_attempt_01",
        "maximum_attempts": 1,
        "data_root": "G:/github/pycharm/projects/neuralhydrology/data/camels_us",
        "forcing_root": (
            "G:/github/pycharm/projects/neuralhydrology/data/camels_us/"
            "basin_mean_forcing/maurer"
        ),
        "forcing_source_digest_tree_sha256": (
            "59665c3f34a42b6c6ba7f6dd7696481ef56a9ac0d30eacad116b4fee6bcb83fa"
        ),
        "protocol_id": "P09-FORMAL",
        "protocol_sha256": (
            "b81bce8fc83aa8c4cad2d36475c6e6da553567f54b5f5f8d52457006fb446ed8"
        ),
        "action": "formal_target_bundle_generation",
        "authorized": True,
        "approval_source_thread_id": "019fa26d-11a6-7812-86ec-3812823cb9a8",
        "approval_text": "批准版本09正式输入生成阶段；不批准训练、正式预测或评分。",
        "approval_text_sha256": (
            "a9ba69f6ee0fcd17bcfc5313140c98bdd483ad6b9f7a3ef3d7d3bcdfe46a4c7d"
        ),
        "training_authorized": False,
        "formal_prediction_generation_authorized": False,
        "official_scoring_authorized": False,
    }


def test_formal_input_action_requires_exact_external_receipt(tmp_path):
    from stage_authorization_v09 import StageAuthorizationError, validate_stage_authorization_v09

    receipt = _receipt()
    receipt["action"] = "training"
    with pytest.raises(StageAuthorizationError, match="action"):
        validate_stage_authorization_v09(
            receipt,
            action="formal_target_bundle_generation",
        )


def test_formal_input_authorization_is_consumed_exactly_once(tmp_path):
    from stage_authorization_v09 import consume_stage_authorization_v09

    path = tmp_path / "input_authorization_consumed.json"
    consume_stage_authorization_v09(
        _receipt(),
        action="formal_target_bundle_generation",
        consumption_path=path,
        launch_evidence={"preflight_sha256": "a" * 64},
    )
    with pytest.raises(FileExistsError):
        consume_stage_authorization_v09(
            _receipt(),
            action="formal_target_bundle_generation",
            consumption_path=path,
            launch_evidence={"preflight_sha256": "a" * 64},
        )
```

- [ ] **Step 2: 运行授权测试并确认失败**

Run:
`pytest src/26_historical_band_experts/tests/test_stage_authorization_v09.py -q`

Expected: FAIL，原因是`stage_authorization_v09`尚不存在。

- [ ] **Step 3: 实现精确授权验证器**

```python
"""Exact external stage authorization for formal version 09."""
from __future__ import annotations

import hashlib
import json
import os
from collections.abc import Mapping
from pathlib import Path


APPROVAL_TEXT = "批准版本09正式输入生成阶段；不批准训练、正式预测或评分。"
APPROVAL_SHA256 = "a9ba69f6ee0fcd17bcfc5313140c98bdd483ad6b9f7a3ef3d7d3bcdfe46a4c7d"
PROTOCOL_SHA256 = "b81bce8fc83aa8c4cad2d36475c6e6da553567f54b5f5f8d52457006fb446ed8"
AUTHORIZED_ACTION = "formal_target_bundle_generation"


class StageAuthorizationError(RuntimeError):
    pass


def validate_stage_authorization_v09(
    receipt: Mapping,
    *,
    action: str,
) -> dict:
    if action != AUTHORIZED_ACTION:
        raise StageAuthorizationError(f"stage authorization does not allow action {action}")
    expected = {
        "receipt_id": "A09-INPUT-01",
        "attempt_id": "input_attempt_01",
        "output_root": "results/26_historical_band_experts/formal_v09/input_attempt_01",
        "maximum_attempts": 1,
        "data_root": "G:/github/pycharm/projects/neuralhydrology/data/camels_us",
        "forcing_root": (
            "G:/github/pycharm/projects/neuralhydrology/data/camels_us/"
            "basin_mean_forcing/maurer"
        ),
        "forcing_source_digest_tree_sha256": (
            "59665c3f34a42b6c6ba7f6dd7696481ef56a9ac0d30eacad116b4fee6bcb83fa"
        ),
        "protocol_id": "P09-FORMAL",
        "protocol_sha256": PROTOCOL_SHA256,
        "action": AUTHORIZED_ACTION,
        "authorized": True,
        "approval_source_thread_id": "019fa26d-11a6-7812-86ec-3812823cb9a8",
        "approval_text": APPROVAL_TEXT,
        "approval_text_sha256": APPROVAL_SHA256,
        "training_authorized": False,
        "formal_prediction_generation_authorized": False,
        "official_scoring_authorized": False,
    }
    if dict(receipt) != expected:
        raise StageAuthorizationError("stage authorization receipt does not match the exact approved action")
    actual_text_hash = hashlib.sha256(APPROVAL_TEXT.encode("utf-8")).hexdigest()
    if actual_text_hash != APPROVAL_SHA256:
        raise StageAuthorizationError("approval text SHA-256 drift")
    return dict(receipt)


def load_stage_authorization_v09(
    path: str | Path,
    *,
    action: str,
) -> dict:
    receipt = json.loads(Path(path).read_text(encoding="utf-8"))
    return validate_stage_authorization_v09(
        receipt,
        action=action,
    )


def consume_stage_authorization_v09(
    receipt: Mapping,
    *,
    action: str,
    consumption_path: str | Path,
    launch_evidence: Mapping,
) -> dict:
    validated = validate_stage_authorization_v09(receipt, action=action)
    path = Path(consumption_path)
    record = {
        "receipt_sha256": hashlib.sha256(
            json.dumps(validated, sort_keys=True, separators=(",", ":")).encode("utf-8")
        ).hexdigest(),
        "action": action,
        "launch_evidence": dict(launch_evidence),
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8", newline="\n") as handle:
        json.dump(record, handle, indent=2, sort_keys=True)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    return record
```

正式输入的只读预检不消费授权。只有规范气象根目录、源摘要树、静态属性、目标可信源、磁盘、
内存、Git和所有输出不存在检查均通过后，构建器才在写第一个正式产物之前独占创建
`results/26_historical_band_experts/formal_v09/input_authorization_consumed.json`。
文件一旦出现，无论构建成功、失败、中断或机器重启，原授权都不得重用。

- [ ] **Step 4: 将外部授权接入启动门**

```python
if config["authorization"].get(authorization_key) is not True:
    if stage_authorization is None:
        raise LaunchAuthorizationError(
            f"version 09 action {action} has no exact external authorization receipt"
        )
    validate_stage_authorization_v09(
        stage_authorization,
        action=action,
    )
```

`synthetic_test`继续使用协议内授权；四项正式动作没有外部凭据时继续拒绝。输入凭据只允许
`formal_target_bundle_generation`，不能授权训练、预测或评分。真正构建器还必须对传入协议文件
执行`sha256_file(protocol_path) == PROTOCOL_SHA256`，不能只信反序列化后的协议内容。

- [ ] **Step 5: 运行授权与启动门测试**

Run:
`pytest src/26_historical_band_experts/tests/test_stage_authorization_v09.py src/26_historical_band_experts/tests/test_launch_gate_v09.py -q`

Expected: PASS。

- [ ] **Step 6: 提交授权门代码**

```powershell
git add src/26_historical_band_experts/stage_authorization_v09.py `
  src/26_historical_band_experts/launch_gate_v09.py `
  src/26_historical_band_experts/tests/test_stage_authorization_v09.py `
  src/26_historical_band_experts/tests/test_launch_gate_v09.py
git commit -m "Feat: Add external formal v09 stage authorization"
```

---

### Task 2: 增加原子产物和环境指纹工具

**Files:**
- Create: `src/26_historical_band_experts/artifact_v09.py`
- Test: `src/26_historical_band_experts/tests/test_artifact_v09.py`

**Interfaces:**
- Produces: `sha256_file(path) -> str`。
- Produces: `digest_pairs_v09(pairs) -> str`。
- Produces: `atomic_json(path, payload) -> None`。
- Produces: `environment_fingerprint_v09(repo_root) -> dict`。
- Produces: `promote_complete_directory_v09(building_root, final_root) -> None`。

- [ ] **Step 1: 写原子性和指纹失败测试**

```python
def test_atomic_json_refuses_existing_destination(tmp_path):
    from artifact_v09 import atomic_json

    path = tmp_path / "manifest.json"
    path.write_text("preserve", encoding="utf-8")
    with pytest.raises(FileExistsError):
        atomic_json(path, {"status": "complete"})
    assert path.read_text(encoding="utf-8") == "preserve"


def test_environment_fingerprint_contains_reproducibility_keys(repo_root):
    from artifact_v09 import environment_fingerprint_v09

    report = environment_fingerprint_v09(repo_root)
    assert set(report) == {
        "git_head",
        "git_tree",
        "git_clean",
        "python",
        "python_executable",
        "platform",
        "numpy",
        "pandas",
        "torch",
        "torch_cuda_version",
        "torch_cuda_available",
        "psutil",
        "pip_freeze",
        "pip_freeze_sha256",
    }


def test_digest_pairs_is_order_sensitive_and_unambiguous():
    from artifact_v09 import digest_pairs_v09

    first = (("00000001", "0" * 64), ("00000002", "1" * 64))
    assert digest_pairs_v09(first) != digest_pairs_v09(tuple(reversed(first)))


def test_directory_promotion_requires_complete_verified_seal(tmp_path):
    from artifact_v09 import atomic_json, promote_complete_directory_v09, sha256_file

    building = tmp_path / "input.building"
    building.mkdir()
    (building / "manifest.json").write_text('{"status":"built_pending_audit"}\n', encoding="utf-8")
    with pytest.raises(FileNotFoundError):
        promote_complete_directory_v09(building, tmp_path / "input_attempt_01")

    (building / "input_audit.json").write_text(
        '{"status":"complete_input_audit"}\n',
        encoding="utf-8",
    )
    atomic_json(building / "seal.json", {
        "status": "complete_input_seal",
        "artifacts": {
            "manifest.json": sha256_file(building / "manifest.json"),
            "input_audit.json": sha256_file(building / "input_audit.json"),
        },
    })
    promote_complete_directory_v09(building, tmp_path / "input_attempt_01")
```

- [ ] **Step 2: 运行工具测试并确认失败**

Run:
`pytest src/26_historical_band_experts/tests/test_artifact_v09.py -q`

Expected: FAIL，原因是`artifact_v09`尚不存在。

- [ ] **Step 3: 实现哈希、原子写入和环境指纹**

```python
def sha256_file(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def digest_pairs_v09(pairs: Sequence[tuple[str, str]]) -> str:
    normalized = [(str(key), str(digest)) for key, digest in pairs]
    if len({key for key, _digest in normalized}) != len(normalized):
        raise ValueError("digest tree keys must be unique")
    if any(re.fullmatch(r"[0-9a-f]{64}", digest) is None for _key, digest in normalized):
        raise ValueError("digest tree values must be lowercase SHA-256")
    payload = json.dumps(
        normalized,
        ensure_ascii=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def atomic_json(path: str | Path, payload: Mapping) -> None:
    path = Path(path)
    if path.exists():
        raise FileExistsError(path)
    temporary = path.with_suffix(path.suffix + ".tmp")
    if temporary.exists():
        raise FileExistsError(temporary)
    temporary.write_text(
        json.dumps(dict(payload), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    os.link(temporary, path)
    temporary.unlink()


def environment_fingerprint_v09(repo_root: str | Path) -> dict:
    freeze_stdout = subprocess.run(
        [sys.executable, "-m", "pip", "freeze"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    freeze_lines = tuple(line for line in freeze_stdout.splitlines() if line)
    freeze = "".join(f"{line}\n" for line in freeze_lines)
    head = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=repo_root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    tree = subprocess.run(
        ["git", "rev-parse", "HEAD^{tree}"],
        cwd=repo_root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    dirty = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=repo_root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return {
        "git_head": head,
        "git_tree": tree,
        "git_clean": dirty == "",
        "python": platform.python_version(),
        "python_executable": str(Path(sys.executable).resolve()),
        "platform": platform.platform(),
        "numpy": np.__version__,
        "pandas": pd.__version__,
        "torch": torch.__version__,
        "torch_cuda_version": torch.version.cuda,
        "torch_cuda_available": torch.cuda.is_available(),
        "psutil": psutil.__version__,
        "pip_freeze": list(freeze_lines),
        "pip_freeze_sha256": hashlib.sha256(freeze.encode("utf-8")).hexdigest(),
    }


def promote_complete_directory_v09(
    building_root: str | Path,
    final_root: str | Path,
) -> None:
    building_root = Path(building_root)
    final_root = Path(final_root)
    if not building_root.is_dir():
        raise FileNotFoundError(building_root)
    if final_root.exists():
        raise FileExistsError(final_root)
    seal_path = building_root / "seal.json"
    seal = json.loads(seal_path.read_text(encoding="utf-8"))
    if seal.get("status") != "complete_input_seal":
        raise RuntimeError("building directory has no complete input seal")
    for name, expected in seal["artifacts"].items():
        if sha256_file(building_root / name) != expected:
            raise RuntimeError(f"sealed artifact hash drift: {name}")
    building_root.replace(final_root)
```

`atomic_json`使用同目录硬链接发布，目标已存在时由文件系统原子拒绝覆盖。目录提升使用同卷原子重命名；
真实构建器必须把`.building`和最终目录放在同一父目录。

- [ ] **Step 4: 运行工具测试**

Run:
`pytest src/26_historical_band_experts/tests/test_artifact_v09.py -q`

Expected: PASS。

- [ ] **Step 5: 提交产物工具**

```powershell
git add src/26_historical_band_experts/artifact_v09.py `
  src/26_historical_band_experts/tests/test_artifact_v09.py
git commit -m "Feat: Add formal v09 artifact fingerprints"
```

---

### Task 3: 实现流式 Maurer 气象和静态属性存储

**Files:**
- Create: `src/26_historical_band_experts/formal_forcing_store_v09.py`
- Test: `src/26_historical_band_experts/tests/test_formal_forcing_store_v09.py`

**Interfaces:**
- Consumes: 冻结531流域列表、原始 Maurer 根目录、冻结静态属性文件、协议和输入阶段授权。
- Produces: `discover_maurer_files_v09(root, basin_ids) -> dict[str, Path]`。
- Produces: `build_forcing_store_v09(...) -> dict`。
- Produces: `forcing.npy`、`dates.npy`、`basins.txt`、`statics.npy`和`forcing_manifest.json`。

- [ ] **Step 1: 写递归发现和不正确目录假设的失败测试**

```python
def test_discovery_does_not_infer_huc_from_basin_prefix(tmp_path):
    from formal_forcing_store_v09 import discover_maurer_files_v09

    huc = tmp_path / "01"
    huc.mkdir()
    path = huc / "04296000_lump_maurer_forcing_leap.txt"
    path.write_text("synthetic", encoding="utf-8")
    found = discover_maurer_files_v09(tmp_path, ("04296000",))
    assert found == {"04296000": path}


def test_discovery_rejects_missing_or_duplicate_basin_files(tmp_path):
    from formal_forcing_store_v09 import ForcingStoreError, discover_maurer_files_v09

    with pytest.raises(ForcingStoreError, match="missing"):
        discover_maurer_files_v09(tmp_path, ("01022500",))
```

- [ ] **Step 2: 运行气象存储测试并确认失败**

Run:
`pytest src/26_historical_band_experts/tests/test_formal_forcing_store_v09.py -q`

Expected: FAIL，原因是`formal_forcing_store_v09`尚不存在。

- [ ] **Step 3: 实现递归唯一文件发现**

```python
def discover_maurer_files_v09(
    root: str | Path,
    basin_ids: tuple[str, ...],
) -> dict[str, Path]:
    root = Path(root)
    candidates: dict[str, list[Path]] = {}
    for path in root.rglob("*_forcing_leap.txt"):
        basin = path.name[:8]
        candidates.setdefault(basin, []).append(path)
    missing = [basin for basin in basin_ids if basin not in candidates]
    duplicates = [basin for basin in basin_ids if len(candidates.get(basin, ())) != 1]
    if missing:
        raise ForcingStoreError(f"missing Maurer files for {len(missing)} frozen basins")
    if duplicates:
        raise ForcingStoreError(f"non-unique Maurer files for {len(duplicates)} frozen basins")
    return {basin: candidates[basin][0] for basin in basin_ids}
```

- [ ] **Step 4: 实现单文件严格读取**

```python
RAW_HEADER = (
    "Year Mnth Day Hr\tDayl(s)\tPRCP(mm/day)\tSRAD(W/m2)\tSWE(mm)"
    "\tTmax(C)\tTmin(C)\tVp(Pa)"
)
OUTPUT_COLUMNS = (
    "PRCP(mm/day)",
    "Tmin(C)",
    "Tmax(C)",
    "SRAD(W/m2)",
    "Vp(Pa)",
)


def read_maurer_file_v09(path: Path) -> tuple[np.ndarray, pd.DatetimeIndex]:
    with path.open("r", encoding="utf-8") as handle:
        for _ in range(3):
            if handle.readline() == "":
                raise ForcingStoreError(f"truncated Maurer header: {path.name}")
        header = handle.readline().rstrip("\r\n")
    if header != RAW_HEADER:
        raise ForcingStoreError(f"Maurer header drift: {path.name}")
    frame = pd.read_csv(path, sep=r"\s+", skiprows=3)
    dates = pd.to_datetime(frame[["Year", "Mnth", "Day"]].rename(
        columns={"Year": "year", "Mnth": "month", "Day": "day"}
    ))
    expected = pd.date_range("1980-01-01", "2008-12-31", freq="D")
    if not pd.DatetimeIndex(dates).equals(expected):
        raise ForcingStoreError(f"Maurer date coverage drift: {path.name}")
    values = frame.loc[:, list(OUTPUT_COLUMNS)].to_numpy(dtype=np.float32)
    required = values[:10_501]
    if not np.isfinite(required).all():
        raise ForcingStoreError(f"non-finite Maurer value: {path.name}")
    if not np.array_equal(required[:, 1], required[:, 2]):
        raise ForcingStoreError(f"frozen Tmin/Tmax equality changed: {path.name}")
    return required, expected[:10_501]
```

- [ ] **Step 5: 实现逐流域内存映射写入**

```python
def build_forcing_store_v09(
    *,
    protocol: Mapping,
    protocol_path: str | Path,
    stage_authorization: Mapping,
    basin_file: str | Path,
    data_dir: str | Path,
    statics_file: str | Path,
    building_root: str | Path,
) -> dict:
    building_root = Path(building_root)
    if building_root.exists():
        raise FileExistsError(building_root)
    if sha256_file(Path(protocol_path)) != PROTOCOL_SHA256:
        raise ForcingStoreError("formal version 09 protocol SHA-256 drift")
    basin_ids = load_basin_ids(basin_file)
    if len(basin_ids) != 531 or len(set(basin_ids)) != 531:
        raise ForcingStoreError("frozen basin list must contain 531 unique basins")
    snapshot = sample_host_memory()
    assert_launch_allowed_v09(
        dict(protocol),
        action="formal_target_bundle_generation",
        estimated_peak_bytes=256 * 2**20,
        snapshot=snapshot,
        stage_authorization=stage_authorization,
    )
    gate = MemorySafetyGate.from_snapshot(snapshot)
    paths = discover_maurer_files_v09(
        Path(data_dir) / "basin_mean_forcing" / "maurer",
        basin_ids,
    )
    resolved_forcing_root = (
        Path(data_dir) / "basin_mean_forcing" / "maurer"
    ).resolve()
    expected_forcing_root = Path(stage_authorization["forcing_root"]).resolve()
    if resolved_forcing_root != expected_forcing_root:
        raise ForcingStoreError("formal Maurer root is not the authorized canonical root")
    building_root.mkdir(parents=True)
    forcing = np.lib.format.open_memmap(
        building_root / "forcing.npy",
        mode="w+",
        dtype=np.float32,
        shape=(531, 10_501, 5),
    )
    source_hashes = []
    for basin_index, basin in enumerate(basin_ids):
        gate.assert_runtime_safe(sample_host_memory())
        values, _dates = read_maurer_file_v09(paths[basin])
        np.copyto(forcing[basin_index], values, casting="no")
        # Check once after the array write and again immediately before hashing.
        gate.assert_runtime_safe(sample_host_memory())
        source_path = paths[basin]
        gate.assert_runtime_safe(sample_host_memory())
        source_hashes.append((basin, sha256_file(source_path)))
    forcing.flush()
    digest_tree = digest_pairs_v09(source_hashes)
    if digest_tree != stage_authorization["forcing_source_digest_tree_sha256"]:
        raise ForcingStoreError("formal Maurer source digest tree drift")

    static_frame = pd.read_csv(statics_file, dtype={"gauge_id": "string"})
    if list(static_frame.columns) != ["gauge_id", *STATIC_COLUMNS]:
        raise ForcingStoreError("static attribute column order drift")
    static_frame["gauge_id"] = static_frame["gauge_id"].str.zfill(8)
    static_frame = static_frame.set_index("gauge_id").loc[list(basin_ids)]
    statics = static_frame.loc[:, list(STATIC_COLUMNS)].to_numpy(dtype=np.float32)
    np.save(building_root / "statics.npy", statics, allow_pickle=False)
    dates = np.arange(
        np.datetime64("1980-01-01"),
        np.datetime64("2008-10-01"),
        dtype="datetime64[D]",
    ).astype(np.int32)
    np.save(building_root / "dates.npy", dates, allow_pickle=False)
    (building_root / "basins.txt").write_text(
        "".join(f"{basin}\n" for basin in basin_ids),
        encoding="utf-8",
    )
    return {
        "forcing_shape": [531, 10_501, 5],
        "source_file_count": len(source_hashes),
        "source_digest_tree_sha256": digest_tree,
    }
```

启动门使用`formal_target_bundle_generation`动作和外部授权凭据，估计峰值固定为
`256 MiB`。每个流域读取前、写入后和哈希前均调用运行时内存门。

静态属性必须验证：

```python
assert sha256_file(statics_file) == (
    "085e8b5e0e56b42bfe7e6d012ebb6f2f56681059b60c61c04b835b207864a1f2"
)
assert list(frame.columns) == ["gauge_id", *STATIC_COLUMNS]
assert frame["gauge_id"].astype(str).str.zfill(8).is_unique
```

按冻结流域顺序写出`statics.npy`，形状`(531, 27)`、类型`float32`、数组有效载荷
`57,348`字节；不把 NumPy 文件头长度写成跨版本固定值。

- [ ] **Step 6: 写出气象清单并测试重载**

`forcing_manifest.json`必须记录。`digest_tree`必须由
`digest_pairs_v09(tuple(source_hashes))`按冻结流域顺序计算；清单不得写入原始文件路径或逐文件摘要：

```python
{
    "status": "complete",
    "protocol_sha256": PROTOCOL_SHA256,
    "basin_count": 531,
    "forcing_dates": 10501,
    "forcing_shape": [531, 10501, 5],
    "forcing_dtype": "float32",
    "forcing_start": "1980-01-01",
    "forcing_end": "2008-09-30",
    "dates_encoding": "int32_days_since_1970-01-01",
    "dynamic_columns": list(OUTPUT_COLUMNS),
    "tmin_equals_tmax_elementwise": True,
    "source_file_count": 531,
    "source_digest_tree_sha256": digest_tree,
    "artifacts": artifact_hashes,
}
```

测试必须以`np.load(path, mmap_mode="r")`重载并核对形状、类型、首尾日期、流域顺序和全部产物哈希。

- [ ] **Step 7: 运行气象存储测试**

Run:
`pytest src/26_historical_band_experts/tests/test_formal_forcing_store_v09.py src/26_historical_band_experts/tests/test_memory_safety_v09.py -q`

Expected: PASS。

- [ ] **Step 8: 提交气象存储实现**

```powershell
git add src/26_historical_band_experts/formal_forcing_store_v09.py `
  src/26_historical_band_experts/tests/test_formal_forcing_store_v09.py
git commit -m "Feat: Add formal v09 streaming forcing store"
```

---

### Task 4: 实现可信训练目标流式导出

**Files:**
- Create: `src/26_historical_band_experts/prepare_formal_targets_v09.py`
- Test: `src/26_historical_band_experts/tests/test_prepare_formal_targets_v09.py`
- Modify: `src/26_historical_band_experts/tests/test_data.py`

**Interfaces:**
- Consumes: 冻结协议、输入阶段授权、冻结流域顺序和可信原始流量加载函数。
- Produces: `prepare_formal_target_bundle_v09(...) -> dict`。
- Produces: `targets.csv`和`targets.manifest.json`。

- [ ] **Step 1: 写训练期边界和常量内存失败测试**

```python
def test_formal_target_export_writes_only_training_dates(tmp_path):
    from prepare_formal_targets_v09 import prepare_formal_target_bundle_v09

    dates = pd.date_range("1989-10-01", "2008-09-30", freq="D")
    series = pd.Series(np.arange(len(dates), dtype=np.float64), index=dates)
    basin_file = tmp_path / "basins.txt"
    basin_file.write_text("00000001\n00000002\n", encoding="utf-8")
    report = prepare_formal_target_bundle_v09(
        protocol=_protocol(),
        stage_authorization=_receipt(),
        basin_ids=("00000001", "00000002"),
        basin_file=basin_file,
        output_path=tmp_path / "targets.csv",
        load_one=lambda _basin: series,
        source_digest=lambda _basin: "0" * 64,
        gate=_safe_gate(),
        snapshot=_safe_snapshot(),
    )
    emitted = pd.read_csv(tmp_path / "targets.csv", dtype={"basin": str})
    assert emitted["date"].min() == "1999-10-01"
    assert emitted["date"].max() == "2008-09-30"
    assert len(emitted) == 2 * 3_288
    assert report["formal_evaluation_rows_emitted"] == 0
```

- [ ] **Step 2: 运行目标测试并确认失败**

Run:
`pytest src/26_historical_band_experts/tests/test_prepare_formal_targets_v09.py -q`

Expected: FAIL，原因是`prepare_formal_targets_v09`尚不存在。

- [ ] **Step 3: 实现逐流域临时文件写入**

```python
assert_launch_allowed_v09(
    dict(protocol),
    action="formal_target_bundle_generation",
    estimated_peak_bytes=128 * 2**20,
    snapshot=snapshot,
    stage_authorization=stage_authorization,
)
allowed_dates = pd.date_range("1999-10-01", "2008-09-30", freq="D")
temporary = output_path.with_suffix(".csv.tmp")
with temporary.open("x", encoding="utf-8", newline="") as handle:
    writer = csv.writer(handle, lineterminator="\n")
    writer.writerow(("basin", "date", "qobs"))
    for basin in basin_ids:
        gate.assert_runtime_safe(sample_host_memory())
        series = load_one(basin).copy()
        series.index = pd.to_datetime(series.index)
        values = pd.to_numeric(series.reindex(allowed_dates), errors="coerce").to_numpy(
            dtype=np.float64
        )
        if not np.isfinite(values).all() or np.any(values < 0):
            raise FormalTargetError(f"incomplete training targets for basin {basin}")
        for date, value in zip(allowed_dates, values):
            writer.writerow((basin, date.strftime("%Y-%m-%d"), format(float(value), ".17g")))
temporary.replace(output_path)
```

真实命令入口中，只有此文件允许导入`load_camels_us_discharge`。它不得打印目标值、原始流量路径或流域统计，
也不得复制到未来正式评分扫描的候选源码包。

- [ ] **Step 4: 封存可信来源摘要**

可信模块在读取每个流域前，以递归搜索明确锁定唯一原始流量文件，并在同一可信模块内计算摘要：

```python
def find_streamflow_file_v09(data_dir: Path, basin: str) -> Path:
    matches = sorted(
        (data_dir / "usgs_streamflow").glob(f"**/{basin}_streamflow_qc.txt")
    )
    if len(matches) != 1:
        raise FormalTargetError(
            f"expected one trusted streamflow file for basin {basin}; found {len(matches)}"
        )
    return matches[0]


def trusted_source_digest_v09(data_dir: Path, basin: str) -> str:
    return sha256_file(find_streamflow_file_v09(data_dir, basin))


def trusted_load_one_v09(data_dir: Path, basin: str) -> pd.Series:
    _forcing, area = load_camels_us_forcings(data_dir, basin, "maurer")
    return load_camels_us_discharge(data_dir, basin, area)
```

真实入口只把`trusted_source_digest_v09`得到的`(basin, sha256)`对按冻结流域顺序交给
`digest_pairs_v09`组合为摘要树；
`load_camels_us_forcings`仅用于取得与现有可信加载器一致的流域面积，气象产品参数固定为`maurer`。
候选输入模块不接触上述函数，也不接收原始流量路径。

`targets.manifest.json`必须记录：

```python
{
    "status": "complete",
    "protocol_sha256": PROTOCOL_SHA256,
    "basin_count": 531,
    "dates_per_basin": 3288,
    "row_count": 1745928,
    "minimum_date": "1999-10-01",
    "maximum_date": "2008-09-30",
    "formal_evaluation_rows_emitted": 0,
    "trusted_raw_streamflow_files_read": 531,
    "candidate_raw_streamflow_files_read": 0,
    "source_streamflow_digest_tree_sha256": digest_tree,
    "target_bundle_sha256": sha256_file(output_path),
}
```

来源摘要只写组合哈希和文件数量，不写原始流量路径。测试必须覆盖流量文件缺失、重复和摘要漂移，
且确认531个源文件摘要按冻结流域顺序组合。

- [ ] **Step 5: 增加候选路径禁止读取测试**

```python
def test_candidate_input_modules_do_not_reference_raw_discharge():
    roots = (
        IDEA_ROOT / "data.py",
        IDEA_ROOT / "formal_forcing_store_v09.py",
    )
    forbidden = ("load_camels_us_discharge", "usgs_streamflow", "camels_hydro")
    for path in roots:
        source = path.read_text(encoding="utf-8")
        assert all(token not in source for token in forbidden)
```

- [ ] **Step 6: 运行目标和数据边界测试**

Run:
`pytest src/26_historical_band_experts/tests/test_prepare_formal_targets_v09.py src/26_historical_band_experts/tests/test_data.py -q`

Expected: PASS。

- [ ] **Step 7: 提交可信目标实现**

```powershell
git add src/26_historical_band_experts/prepare_formal_targets_v09.py `
  src/26_historical_band_experts/tests/test_prepare_formal_targets_v09.py `
  src/26_historical_band_experts/tests/test_data.py
git commit -m "Feat: Add trusted formal v09 target export"
```

---

### Task 5: 实现训练期归一化、输入重载和完整审核

**Files:**
- Create: `src/26_historical_band_experts/formal_input_v09.py`
- Create: `src/26_historical_band_experts/audit_formal_inputs_v09.py`
- Create: `src/26_historical_band_experts/build_formal_inputs_v09.py`
- Test: `src/26_historical_band_experts/tests/test_formal_input_v09.py`
- Test: `src/26_historical_band_experts/tests/test_audit_formal_inputs_v09.py`

**Interfaces:**
- Produces: `seal_formal_inputs_v09(input_root, protocol) -> dict`。
- Produces: `open_formal_inputs_v09(input_root, protocol) -> FormalInputPack`。
- Produces: `audit_formal_inputs_v09(input_root, protocol) -> dict`。
- Produces: `targets.npy`、`scaler.json`、`environment.json`、`manifest.json`、
  `input_audit.json`和最终`seal.json`。

- [ ] **Step 1: 写归一化日期和封存重载失败测试**

```python
def test_scaler_uses_indices_7213_through_10500_only(tmp_path):
    from formal_input_v09 import compute_scaler_v09

    forcing = np.full((2, 10_501, 5), 99.0, dtype=np.float32)
    forcing[:, 7_213:10_501] = 2.0
    targets = np.full((2, 3_288), 3.0, dtype=np.float32)
    statics = np.asarray([[0.0] * 27, [2.0] * 27], dtype=np.float32)
    scaler = compute_scaler_v09(forcing, targets, statics)
    np.testing.assert_array_equal(scaler["dynamic_center"], np.full(5, 2.0))
    assert scaler["q_center"] == 3.0
    np.testing.assert_array_equal(scaler["static_center"], np.full(27, 1.0))


def test_all_candidate_formal_input_modules_exclude_raw_discharge_reads():
    roots = (
        IDEA_ROOT / "formal_input_v09.py",
        IDEA_ROOT / "audit_formal_inputs_v09.py",
        IDEA_ROOT / "build_formal_inputs_v09.py",
    )
    forbidden = ("load_camels_us_discharge", "usgs_streamflow", "camels_hydro")
    for path in roots:
        source = path.read_text(encoding="utf-8")
        assert all(token not in source for token in forbidden)
```

- [ ] **Step 2: 运行输入测试并确认失败**

Run:
`pytest src/26_historical_band_experts/tests/test_formal_input_v09.py src/26_historical_band_experts/tests/test_audit_formal_inputs_v09.py -q`

Expected: FAIL，原因是正式输入和审核模块尚不存在。

- [ ] **Step 3: 将目标逗号分隔文件转换为小型内存映射矩阵**

```python
targets = np.lib.format.open_memmap(
    input_root / "targets.npy",
    mode="w+",
    dtype=np.float32,
    shape=(531, 3_288),
)
seen = np.zeros((531, 3_288), dtype=np.bool_)
for chunk in pd.read_csv(
    input_root / "targets.csv",
    dtype={"basin": "string", "date": "string"},
    chunksize=50_000,
):
    mapped_basins = chunk["basin"].map(basin_lookup)
    if mapped_basins.isna().any():
        raise FormalInputError("unknown basin in training target bundle")
    basin_index = mapped_basins.to_numpy(dtype=np.int64)
    parsed_dates = pd.to_datetime(chunk["date"], format="%Y-%m-%d", errors="coerce")
    if parsed_dates.isna().any():
        raise FormalInputError("invalid date in training target bundle")
    date_index = (
        parsed_dates - pd.Timestamp("1999-10-01")
    ).dt.days.to_numpy(dtype=np.int64)
    if np.any(date_index < 0) or np.any(date_index >= 3_288):
        raise FormalInputError("date outside the training target window")
    keys = pd.MultiIndex.from_arrays((basin_index, date_index))
    if keys.has_duplicates:
        raise FormalInputError("duplicate training target key within chunk")
    if seen[basin_index, date_index].any():
        raise FormalInputError("duplicate training target key")
    qobs = pd.to_numeric(chunk["qobs"], errors="coerce").to_numpy(dtype=np.float64)
    if not np.isfinite(qobs).all() or np.any(qobs < 0):
        raise FormalInputError("invalid training target value")
    targets[basin_index, date_index] = qobs.astype(np.float32)
    seen[basin_index, date_index] = True
if not seen.all():
    raise FormalInputError("incomplete training target coverage")
targets.flush()
```

- [ ] **Step 4: 以固定顺序计算训练期统计**

```python
def compute_scaler_v09(
    forcing: np.ndarray,
    targets: np.ndarray,
    statics: np.ndarray,
) -> dict:
    dynamic_sum = np.zeros(5, dtype=np.float64)
    for basin_index in range(531):
        values = np.asarray(
            forcing[basin_index, 7_213:10_501, :],
            dtype=np.float64,
        )
        dynamic_sum += values.sum(axis=0, dtype=np.float64)
    dynamic_count = 531 * 3_288
    dynamic_center = dynamic_sum / float(dynamic_count)
    dynamic_squared_deviation = np.zeros(5, dtype=np.float64)
    for basin_index in range(531):
        values = np.asarray(
            forcing[basin_index, 7_213:10_501, :],
            dtype=np.float64,
        )
        dynamic_squared_deviation += np.square(
            values - dynamic_center
        ).sum(axis=0, dtype=np.float64)
    dynamic_scale = np.sqrt(
        dynamic_squared_deviation / float(dynamic_count)
    )

    q_sum = np.float64(0.0)
    for basin_index in range(531):
        q_sum += np.asarray(
            targets[basin_index],
            dtype=np.float64,
        ).sum(dtype=np.float64)
    q_count = 531 * 3_288
    q_center = float(q_sum / float(q_count))
    q_squared_deviation = np.float64(0.0)
    per_basin_q_std = np.empty(531, dtype=np.float64)
    for basin_index in range(531):
        values = np.asarray(targets[basin_index], dtype=np.float64)
        q_squared_deviation += np.square(values - q_center).sum(dtype=np.float64)
        per_basin_q_std[basin_index] = values.std(ddof=0)
    q_scale = float(np.sqrt(q_squared_deviation / float(q_count)))

    static64 = np.asarray(statics, dtype=np.float64)
    return {
        "dynamic_center": dynamic_center.tolist(),
        "dynamic_scale": np.where(dynamic_scale < 1e-8, 1.0, dynamic_scale).tolist(),
        "q_center": q_center,
        "q_scale": q_scale if q_scale >= 1e-8 else 1.0,
        "per_basin_q_std": per_basin_q_std.tolist(),
        "static_center": static64.mean(axis=0).tolist(),
        "static_scale": np.where(
            static64.std(axis=0, ddof=0) < 1e-8,
            1.0,
            static64.std(axis=0, ddof=0),
        ).tolist(),
        "training_start_index": 7213,
        "training_end_index_inclusive": 10500,
}
```

上述两遍算法使峰值保持在一个流域的`3,288 × 5`数据以内。审核器使用独立的逐流域
Welford算法重算；动态、目标和静态统计最大绝对差不得超过`1e-9`。

- [ ] **Step 5: 实现只读输入重载**

```python
@dataclass(frozen=True)
class FormalInputPack:
    basins: tuple[str, ...]
    dates: np.ndarray
    forcing: np.ndarray
    statics: np.ndarray
    targets: np.ndarray
    scaler: dict
    manifest: dict
    seal: dict


def open_formal_inputs_v09(input_root: str | Path, protocol: Mapping) -> FormalInputPack:
    root = Path(input_root)
    seal = json.loads((root / "seal.json").read_text(encoding="utf-8"))
    if seal.get("status") != "complete_input_seal":
        raise FormalInputError("formal input directory has no complete seal")
    for name, expected in seal["artifacts"].items():
        if sha256_file(root / name) != expected:
            raise FormalInputError(f"sealed top-level artifact hash drift: {name}")
    input_audit = json.loads((root / "input_audit.json").read_text(encoding="utf-8"))
    if input_audit.get("status") != "complete_input_audit":
        raise FormalInputError("formal input audit status drift")
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("status") != "built_pending_audit":
        raise FormalInputError("formal input build manifest status drift")
    for name, expected in manifest["artifacts"].items():
        if sha256_file(root / name) != expected:
            raise FormalInputError(f"artifact hash drift: {name}")
    forcing = np.load(root / "forcing.npy", mmap_mode="r")
    targets = np.load(root / "targets.npy", mmap_mode="r")
    statics = np.load(root / "statics.npy", mmap_mode="r")
    dates = np.load(root / "dates.npy", mmap_mode="r")
    if forcing.shape != (531, 10_501, 5) or forcing.dtype != np.float32:
        raise FormalInputError("forcing layout drift")
    if targets.shape != (531, 3_288) or targets.dtype != np.float32:
        raise FormalInputError("target layout drift")
    return FormalInputPack(
        basins=tuple((root / "basins.txt").read_text(encoding="utf-8").splitlines()),
        dates=dates,
        forcing=forcing,
        statics=statics,
        targets=targets,
        scaler=json.loads((root / "scaler.json").read_text(encoding="utf-8")),
        manifest=manifest,
        seal=seal,
    )
```

顶层`manifest.json`必须是不可变的构建记录，状态为`built_pending_audit`。其`artifacts`字段必须
逐项包含：

```text
basins.txt
dates.npy
environment.json
forcing.npy
forcing_manifest.json
scaler.json
statics.npy
targets.csv
targets.manifest.json
targets.npy
```

它还必须记录输入尝试标识、固定输出根目录、协议哈希、授权凭据哈希、Git提交和树对象，
以及本阶段全部实现模块和配置文件的逐文件 SHA-256。不能使用目录修改时间或模糊版本标签替代文件哈希。

- [ ] **Step 6: 实现独立完整审核**

审核必须验证：

- 协议、流域文件和静态文件哈希；
- 531个流域及其冻结顺序；
- 10,501个气象日期和3,288个训练目标日期；
- 气象、静态属性和训练目标的唯一性、完整性、有限性；
- 5项动态和27项静态的精确列顺序；
- `Tmin(C)`与`Tmax(C)`的冻结逐元素相等事实；
- 目标包没有任何`1989-10-01`至`1999-09-30`行；
- 全部产物哈希、代码提交、干净工作区和环境指纹；
- 正式训练、预测和评分授权仍为`false`。

审核输出`input_audit.json`，状态只能是`complete_input_audit`或抛出异常；不得用警告替代失败。
审核成功后才写`seal.json`：

```python
{
    "status": "complete_input_seal",
    "attempt_id": "input_attempt_01",
    "protocol_sha256": PROTOCOL_SHA256,
    "authorization_receipt_sha256": authorization_receipt_sha256,
    "artifacts": {
        "manifest.json": sha256_file(input_root / "manifest.json"),
        "input_audit.json": sha256_file(input_root / "input_audit.json"),
    },
}
```

该两级结构避免`manifest.json`既包含自身或审核文件哈希又需要在审核后改写的循环。`seal.json`
不包含自身哈希；最终审计记录和 Git 登记负责固定`seal.json`哈希。

- [ ] **Step 7: 实现单一编排入口**

`build_formal_inputs_v09.py`按以下顺序调用：

1. 验证外部输入授权，并确认命令输出根目录与凭据绑定路径逐字一致；
2. 验证内存、工作区和协议；
3. 创建唯一`.building`目录；
4. 构建气象和静态存储；
5. 可信导出训练目标；
6. 构建`targets.npy`和`scaler.json`；
7. 写`environment.json`和状态为`built_pending_audit`的顶层`manifest.json`；
8. 独立算法重载并审核全部构建产物，写`input_audit.json`；
9. 写`seal.json`；
10. 通过正式只读接口再次重载封存输入；
11. 原子提升为`input_attempt_01`。

任何步骤失败都保留`.building/failure.json`，但没有
`seal.json::status=complete_input_seal`的目录不能被训练入口读取。

- [ ] **Step 8: 运行输入、审核和禁止读取测试**

Run:
`pytest src/26_historical_band_experts/tests/test_formal_input_v09.py src/26_historical_band_experts/tests/test_audit_formal_inputs_v09.py src/26_historical_band_experts/tests/test_data.py -q`

Expected: PASS。

- [ ] **Step 9: 提交输入重载和审核实现**

```powershell
git add src/26_historical_band_experts/formal_input_v09.py `
  src/26_historical_band_experts/audit_formal_inputs_v09.py `
  src/26_historical_band_experts/build_formal_inputs_v09.py `
  src/26_historical_band_experts/tests/test_formal_input_v09.py `
  src/26_historical_band_experts/tests/test_audit_formal_inputs_v09.py
git commit -m "Feat: Seal and audit formal v09 inputs"
```

---

### Task 6: 预注册、验证并一次性生成正式输入

**Files:**
- Create after direct approval: `src/26_historical_band_experts/configs/formal_v09_input_authorization.json`
- Modify: `src/26_historical_band_experts/registry.csv`
- Create: `docs/technical/historical_multiscale_formal_v09_input_audit.md`
- Generated, not tracked: `results/26_historical_band_experts/formal_v09/input_attempt_01/`
- Generated, not tracked:
  `results/26_historical_band_experts/formal_v09/input_attempt_01.external_audit.json`

**Interfaces:**
- Consumes: 已验证代码、精确授权凭据、原始 Maurer、冻结静态文件和可信训练目标源。
- Produces: 唯一正式输入目录和独立审核结论。

- [ ] **Step 1: 创建精确授权凭据**

只有收到Global Constraints中的逐字直接批准后，创建：

```json
{
  "receipt_id": "A09-INPUT-01",
  "attempt_id": "input_attempt_01",
  "output_root": "results/26_historical_band_experts/formal_v09/input_attempt_01",
  "maximum_attempts": 1,
  "data_root": "G:/github/pycharm/projects/neuralhydrology/data/camels_us",
  "forcing_root": "G:/github/pycharm/projects/neuralhydrology/data/camels_us/basin_mean_forcing/maurer",
  "forcing_source_digest_tree_sha256": "59665c3f34a42b6c6ba7f6dd7696481ef56a9ac0d30eacad116b4fee6bcb83fa",
  "protocol_id": "P09-FORMAL",
  "protocol_sha256": "b81bce8fc83aa8c4cad2d36475c6e6da553567f54b5f5f8d52457006fb446ed8",
  "action": "formal_target_bundle_generation",
  "authorized": true,
  "approval_source_thread_id": "019fa26d-11a6-7812-86ec-3812823cb9a8",
  "approval_text": "批准版本09正式输入生成阶段；不批准训练、正式预测或评分。",
  "approval_text_sha256": "a9ba69f6ee0fcd17bcfc5313140c98bdd483ad6b9f7a3ef3d7d3bcdfe46a4c7d",
  "training_authorized": false,
  "formal_prediction_generation_authorized": false,
  "official_scoring_authorized": false
}
```

- [ ] **Step 2: 新增输入登记行**

在`registry.csv`新增：

```text
I09-INPUT,input_bundle,The frozen formal inputs can be built without evaluation-observation leakage,configs/formal_v09_protocol.json,Build Maurer memmap and training-only target bundle,531 frozen basins; Maurer; 27 statics; sealed evaluation answers,not_applicable,authorized_not_started,results/26_historical_band_experts/formal_v09/input_attempt_01,,,Input-09,Training prediction and scoring remain unauthorized.
```

- [ ] **Step 3: 提交授权凭据和登记**

```powershell
git add src/26_historical_band_experts/configs/formal_v09_input_authorization.json `
  src/26_historical_band_experts/registry.csv
git commit -m "Phase: Authorize formal v09 input generation"
```

- [ ] **Step 4: 更新每小时审查规则**

将自动审查09更新为：仅在精确授权凭据
`src/26_historical_band_experts/configs/formal_v09_input_authorization.json`
存在、哈希匹配且动作是`formal_target_bundle_generation`时允许输入阶段；训练、正式预测和评分仍禁止。

- [ ] **Step 5: 运行全部局部测试**

启动前重新测量可用物理内存；低于`12.68 GiB`立即停止。

Run:
`pytest src/26_historical_band_experts/tests -q`

Expected: 全部测试通过，准确数量写入输入审计记录。由于代码已变化，不能复用
`2ed4a414`提交上的`378 passed`作为新提交证据。

- [ ] **Step 6: 运行只读真实输入预检**

预检必须证明：

- 531/531气象文件唯一存在；
- 气象文件只来自授权的`basin_mean_forcing/maurer`规范根目录，不能来自`full`副本或头文件备份；
- 531个规范源文件按冻结顺序的摘要树为
  `59665c3f34a42b6c6ba7f6dd7696481ef56a9ac0d30eacad116b4fee6bcb83fa`；
- 每个文件10,597行，日期`1980-01-01`至`2008-12-31`；
- 冻结静态表531行、28列、531个唯一测站；
- `G:`盘至少有`1 GiB`可用空间；
- 最终目录与同父目录的`input_attempt_01.building`均不存在；
- `input_authorization_consumed.json`不存在；
- 工作区干净；
- 协议、授权凭据和代码提交哈希一致；
- 授权凭据只绑定`input_attempt_01`、固定输出根目录和最多一次尝试；
- 可用物理内存至少`12.68 GiB`。

- [ ] **Step 7: 一次性生成正式输入**

```powershell
python src\26_historical_band_experts\build_formal_inputs_v09.py `
  --protocol src\26_historical_band_experts\configs\formal_v09_protocol.json `
  --authorization src\26_historical_band_experts\configs\formal_v09_input_authorization.json `
  --basin-file src\fair_benchmark\frozen\track0_forcing_only_basins.txt `
  --statics-file src\fair_benchmark\frozen\bundle\track0_statics.csv `
  --data-dir G:\github\pycharm\projects\neuralhydrology\data\camels_us `
  --output-root results/26_historical_band_experts/formal_v09/input_attempt_01
```

构建器在全部只读预检通过后、创建`input_attempt_01.building`之前，独占写入
`results/26_historical_band_experts/formal_v09/input_authorization_consumed.json`。
该文件一旦创建即表示本次授权已消耗。

运行中每个流域和每个50,000行目标块前检查内存。可用内存低于`8 GiB`、进程驻留内存超过
`6 GiB`、单次分配超过`512 MiB`或任何数据边界失败时立即停止。

- [ ] **Step 8: 独立重载输入**

Run:

```powershell
python src\26_historical_band_experts\audit_formal_inputs_v09.py `
  --protocol src\26_historical_band_experts\configs\formal_v09_protocol.json `
  --input-root results\26_historical_band_experts\formal_v09\input_attempt_01 `
  --report results\26_historical_band_experts\formal_v09\input_attempt_01.external_audit.json
```

外部报告路径必须位于封存输入目录之外且事先不存在；审核器不得修改封存目录。Expected:
`status=complete_input_audit`，531个流域、5,576,031个气象行和1,745,928个训练目标全部通过。

- [ ] **Step 9: 由独立上下文审核**

独立审查者从干净上下文执行以下只读任务：

1. 核对当前提交和工作区；
2. 重算协议、源清单和全部输入产物哈希；
3. 重载内存映射并独立重算覆盖、有限性和训练期统计；
4. 扫描候选输入模块，确认没有原始流量读取；
5. 确认没有训练、预测、评分或冻结目录改动；
6. 尝试以缺失、重复、越界、哈希漂移和低内存样本反驳输入审核。

独立审核未通过时，输入状态为`HOLD`，不得申请训练授权。

- [ ] **Step 10: 记录并提交输入结论**

`docs/technical/historical_multiscale_formal_v09_input_audit.md`必须区分：

- 事实：产物、覆盖、哈希和独立审核结果；
- 未知：尚未训练，因此没有任何531流域性能；
- 下一条件：单独批准严格嵌套训练；
- 禁止推断：输入审核通过不代表历史候选有效。

```powershell
git add docs/technical/historical_multiscale_formal_v09_input_audit.md `
  src/26_historical_band_experts/registry.csv
git commit -m "Phase: Record formal v09 input audit"
```

## Self-Review

- Spec coverage: 授权、Maurer、27项静态属性、3,561天最长滞后所需日期、训练期目标、内存、
  安全边界、顺序敏感来源摘要、完整环境快照、禁止输入和独立审核均有对应任务。
- Scope boundary: 本计划不包含训练、正式预测或评分；这些必须在输入独立审核后另写计划。
- Type consistency: 全部气象、静态和目标存储均为float32；统计累积为float64；流域和日期索引均为整数；训练读取接口只返回封存产物。
- Atomicity: 所有真实输出先写`input_attempt_01.building`，只有`input_audit.json`和
  `seal.json`完整后才能提升；既有最终目录和临时目录均拒绝覆盖。
- 未定字段检查：计划没有未定字段；授权值由Global Constraints中的精确用户回复唯一决定。

## Execution Handoff

Plan complete and saved to
`docs/superpowers/plans/2026-07-31-historical-multiscale-formal-v09-input-stage.md`.
在收到精确输入阶段批准后有两种执行方式：

1. **Subagent-Driven**：主上下文按Task 1至Task 6实现，独立上下文在每个组件和真实输入完成后审核。
2. **Inline Execution**：当前上下文按Task 1至Task 6执行，在Task 6 Step 9切换到独立上下文。

无论选择哪种方式，未收到精确批准文本前都不得执行本计划。
