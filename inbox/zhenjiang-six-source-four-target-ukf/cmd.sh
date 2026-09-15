#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'TEMPORAL_REMOTE_PY'
"""Import-safe authenticated archive and exclusive remote deployment helpers.

The controller uses temporal_encrypted_release.py to generate commands. This
module never performs deployment, key generation or submission at import time.
"""
from __future__ import annotations

import base64
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tarfile

EXPERIMENT = "zhenjiang_temporal_validation_2024_20260915_001"
REMOTE = "/data1/home/sunyiq/zhenjiang_temporal_validation_2024_20260915_001"
CONTRACT_SHA = "bf3696871e2b05bde03f5cb942e007e6e69f4a78e00228eed3afaac9cf124628"
SCHEDULER_SHA = "a2abb8494c06ae37b3e795871fe0ea36aba90779803ec1d022fe46916d114d5a"
PYTHON = "/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python"
MAX_PACKED = 11_000_000
MAX_PLAIN_TAR = 20_000_000
MAX_ENVELOPE = 15_000_000
MAX_RECEIPT = 12_000_000
SOURCE_NAMES = (
    "temporal_runtime_io.py", "run_temporal_evaluation.py", "temporal_evaluation_core.py",
    "aligned_reencoding_core.py", "evaluate.slurm", "frozen_evaluation_inputs.json",
    "contracts/data_authorization.json", "contracts/execution_authorization.json",
    "contracts/execution_contract.json", "evaluation_protocol.md",
)
META_KEYS = {"experiment_id", "remote_root", "execution_contract_sha256",
             "public_key_sha256", "bundle_manifest_sha256"}
ENVELOPE_KEYS = {"schema", "metadata", "plaintext_sha256", "plaintext_size",
                 "wrapped_key", "nonce", "ciphertext"}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n").encode()


def document(raw):
    def unique(pairs):
        out = {}
        for key, value in pairs:
            if key in out:
                raise ValueError("duplicate JSON key")
            out[key] = value
        return out
    return json.loads(raw, object_pairs_hook=unique,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError("nonfinite JSON")))


def safe_name(name):
    if (not isinstance(name, str) or not name or len(name) > 240 or "\\" in name or ":" in name
            or any(ord(c) < 32 for c in name) or any(p in ("", ".", "..") for p in name.split("/"))):
        raise ValueError("unsafe archive name")
    return name


def safe_path(path):
    path = Path(path)
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError("absolute non-traversing path required")
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError("symlink path rejected")
    if path.exists() and not (path.is_file() or path.is_dir()):
        raise ValueError("special path rejected")
    return path


def read_regular(path, maximum=MAX_PLAIN_TAR):
    path = safe_path(path)
    before = path.stat()
    if not stat.S_ISREG(before.st_mode) or before.st_size > maximum or before.st_nlink != 1:
        raise ValueError("nonregular, multiply linked or oversized file")
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0))
    with os.fdopen(fd, "rb") as handle:
        info = os.fstat(handle.fileno())
        if (info.st_dev, info.st_ino, info.st_size) != (before.st_dev, before.st_ino, before.st_size):
            raise ValueError("file identity changed during open")
        raw = handle.read(maximum + 1)
    if len(raw) != before.st_size:
        raise ValueError("file size changed during read")
    return raw


def write_new(path, raw, root):
    root, path = safe_path(root), safe_path(path)
    if root not in path.parents or not isinstance(raw, bytes):
        raise ValueError("write outside isolated root or non-bytes")
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    safe_path(path)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_BINARY", 0)
                 | getattr(os, "O_NOFOLLOW", 0), 0o600)
    with os.fdopen(fd, "wb", buffering=0) as handle:
        offset = 0
        while offset < len(raw):
            count = handle.write(memoryview(raw)[offset:])
            if type(count) is not int or not 0 < count <= len(raw) - offset:
                raise OSError("exclusive write made no progress")
            offset += count
        os.fsync(handle.fileno())


def put(path, value, root):
    write_new(path, canonical(value), root)


def validate_metadata(metadata):
    if not isinstance(metadata, dict) or set(metadata) != META_KEYS:
        raise ValueError("metadata keys differ")
    if any(not isinstance(value, str) for value in metadata.values()):
        raise ValueError("metadata must be strings")
    if (metadata["experiment_id"] != EXPERIMENT or metadata["remote_root"] != REMOTE
            or metadata["execution_contract_sha256"] != CONTRACT_SHA):
        raise ValueError("metadata experiment/contract differs")
    if any(not re.fullmatch("[0-9a-f]{64}", metadata[key]) for key in META_KEYS if key.endswith("sha256")):
        raise ValueError("metadata digest invalid")


def crypto_imports():
    import cryptography
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding, rsa
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    # Access every required primitive before a remote root can be created.
    return cryptography, hashes.SHA256, serialization, padding.OAEP, padding.MGF1, rsa, AESGCM


def public_identity(public_pem):
    _, _, serialization, _, _, rsa, _ = crypto_imports()
    key = serialization.load_pem_public_key(public_pem)
    if not isinstance(key, rsa.RSAPublicKey) or key.key_size != 4096 or key.public_numbers().e != 65537:
        raise ValueError("RSA4096 exponent65537 public key required")
    encoded = key.public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
    if encoded != public_pem:
        raise ValueError("canonical public PEM required")
    return key


def encrypt_bundle(packed, public_pem, metadata):
    """Return only an authenticated JSON envelope; random AES key stays in memory."""
    validate_metadata(metadata)
    if not isinstance(packed, bytes) or not 0 < len(packed) <= MAX_PACKED:
        raise ValueError("packed payload bounds")
    if sha(public_pem) != metadata["public_key_sha256"]:
        raise ValueError("public fingerprint differs")
    public = public_identity(public_pem)
    _, SHA256, _, OAEP, MGF1, _, AESGCM = crypto_imports()
    key, nonce = AESGCM.generate_key(bit_length=256), os.urandom(12)
    envelope = {"schema": "zhenjiang-rsa4096-aes256gcm-v1", "metadata": dict(metadata),
                "plaintext_sha256": sha(packed), "plaintext_size": len(packed)}
    aad = canonical(envelope)
    envelope.update(wrapped_key=base64.b64encode(public.encrypt(key, OAEP(
        mgf=MGF1(SHA256()), algorithm=SHA256(), label=None))).decode(),
        nonce=base64.b64encode(nonce).decode(),
        ciphertext=base64.b64encode(AESGCM(key).encrypt(nonce, packed, aad)).decode())
    encoded = canonical(envelope)
    if len(encoded) > MAX_ENVELOPE:
        raise ValueError("envelope bounds")
    return encoded


def strict_b64(value, maximum):
    if not isinstance(value, str) or len(value) > (maximum + 2) // 3 * 4:
        raise ValueError("base64 bounds")
    raw = base64.b64decode(value, validate=True)
    if len(raw) > maximum or base64.b64encode(raw).decode() != value:
        raise ValueError("noncanonical base64")
    return raw


def decrypt_bundle(envelope, private_pem, expected_metadata):
    validate_metadata(expected_metadata)
    if not isinstance(envelope, bytes) or len(envelope) > MAX_ENVELOPE:
        raise ValueError("envelope bounds")
    obj = document(envelope)
    if not isinstance(obj, dict) or set(obj) != ENVELOPE_KEYS or obj["schema"] != "zhenjiang-rsa4096-aes256gcm-v1":
        raise ValueError("envelope schema differs")
    validate_metadata(obj["metadata"])
    if obj["metadata"] != expected_metadata:
        raise ValueError("authenticated metadata differs")
    if type(obj["plaintext_size"]) is not int or not 0 < obj["plaintext_size"] <= MAX_PACKED:
        raise ValueError("plaintext bounds")
    if not isinstance(obj["plaintext_sha256"], str) or not re.fullmatch("[0-9a-f]{64}", obj["plaintext_sha256"]):
        raise ValueError("plaintext digest invalid")
    wrapped, nonce, ciphertext = (strict_b64(obj["wrapped_key"], 512), strict_b64(obj["nonce"], 12),
                                  strict_b64(obj["ciphertext"], MAX_PACKED + 16))
    if len(wrapped) != 512 or len(nonce) != 12 or len(ciphertext) != obj["plaintext_size"] + 16:
        raise ValueError("cipher component size differs")
    _, SHA256, serialization, OAEP, MGF1, rsa, AESGCM = crypto_imports()
    private = serialization.load_pem_private_key(private_pem, password=None)
    if not isinstance(private, rsa.RSAPrivateKey) or private.key_size != 4096:
        raise ValueError("RSA4096 private key required")
    public = private.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
    public_identity(public)
    if sha(public) != expected_metadata["public_key_sha256"]:
        raise ValueError("private key fingerprint differs")
    key = private.decrypt(wrapped, OAEP(mgf=MGF1(SHA256()), algorithm=SHA256(), label=None))
    if len(key) != 32:
        raise ValueError("AES256 key required")
    aad = canonical({k: obj[k] for k in ("schema", "metadata", "plaintext_sha256", "plaintext_size")})
    raw = AESGCM(key).decrypt(nonce, ciphertext, aad)
    if len(raw) != obj["plaintext_size"] or sha(raw) != obj["plaintext_sha256"]:
        raise ValueError("decrypted identity differs")
    return raw


def manifest_files(manifest_raw):
    if len(manifest_raw) > 100_000:
        raise ValueError("manifest bounds")
    manifest = document(manifest_raw)
    if (set(manifest) != {"schema", "experiment_id", "remote_root", "source_files", "data_files"}
            or manifest["schema"] != "zhenjiang-temporal-encrypted-bundle-v1"
            or manifest["experiment_id"] != EXPERIMENT or manifest["remote_root"] != REMOTE):
        raise ValueError("manifest schema differs")
    registered = {}
    for group in ("source_files", "data_files"):
        if not isinstance(manifest[group], list) or len(manifest[group]) > 40:
            raise ValueError("manifest member count")
        for spec in manifest[group]:
            if set(spec) != {"relative_path", "byte_count", "sha256"}:
                raise ValueError("manifest member schema")
            name = safe_name(spec["relative_path"])
            if (name in registered or type(spec["byte_count"]) is not int or not 0 <= spec["byte_count"] <= MAX_PLAIN_TAR
                    or not isinstance(spec["sha256"], str) or not re.fullmatch("[0-9a-f]{64}", spec["sha256"])):
                raise ValueError("duplicate or invalid manifest member")
            if name.startswith("inputs/") != (group == "data_files"):
                raise ValueError("source/data separation differs")
            if group == "data_files" and not name.startswith("inputs/2024/"):
                raise ValueError("data outside 2024")
            registered[name] = spec
    if sum(row["byte_count"] for row in registered.values()) > MAX_PLAIN_TAR:
        raise ValueError("manifest total bounds")
    return manifest, registered


def unpack_bundle(packed, manifest_raw):
    _, registered = manifest_files(manifest_raw)
    if len(packed) > MAX_PACKED:
        raise ValueError("packed size bounds")
    with gzip.GzipFile(fileobj=io.BytesIO(packed)) as handle:
        unpacked = handle.read(MAX_PLAIN_TAR + 1)
    if len(unpacked) > MAX_PLAIN_TAR:
        raise ValueError("uncompressed archive bounds")
    files = {}
    with tarfile.open(fileobj=io.BytesIO(unpacked), mode="r:") as archive:
        for member in archive:
            name = safe_name(member.name)
            if (not member.isfile() or member.type not in (tarfile.REGTYPE, tarfile.AREGTYPE)
                    or member.pax_headers or name in files or name not in registered
                    or member.size != registered[name]["byte_count"]):
                raise ValueError("unsafe, duplicate or unexpected tar member")
            raw = archive.extractfile(member).read(member.size + 1)
            if len(raw) != member.size or sha(raw) != registered[name]["sha256"]:
                raise ValueError("tar member identity differs")
            files[name] = raw
    if set(files) != set(registered):
        raise ValueError("tar exact member set differs")
    return files


def prepare_root(root, parent):
    """Generate a key only after dependency and exclusive-root checks; synthetic callers supply their root."""
    root, parent = safe_path(root), safe_path(parent)
    if root.parent != parent or root.name != EXPERIMENT or not parent.is_dir():
        raise ValueError("unexpected parent/root")
    if root.exists():
        raise FileExistsError("candidate root already exists")
    cryptography, _, serialization, _, _, rsa, _ = crypto_imports()
    root.mkdir(mode=0o700, exist_ok=False)
    for name in ("logs", "evidence", "tmp", "transport_private"):
        (root / name).mkdir(mode=0o700)
    private = rsa.generate_private_key(public_exponent=65537, key_size=4096)
    public = private.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
    private_raw = private.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                        serialization.NoEncryption())
    write_new(root / "transport_private/private.pem", private_raw, root)
    write_new(root / "transport_private/public.pem", public, root)
    preparation = {"experiment_id": EXPERIMENT, "remote_root": str(root),
                   "execution_contract_sha256": CONTRACT_SHA, "public_key_sha256": sha(public),
                   "owner_uid": root.stat().st_uid, "cryptography_version": cryptography.__version__}
    prep_raw = canonical(preparation)
    write_new(root / "evidence/key_preparation.json", prep_raw, root)
    return dict(preparation, public_pem=public.decode(), key_preparation_sha256=sha(prep_raw))


def verify_prepared(root, receipt):
    root = safe_path(root)
    if root.name != EXPERIMENT or str(root) != receipt["remote_root"]:
        raise ValueError("prepared root binding differs")
    if not root.is_dir() or (hasattr(os, "getuid") and root.stat().st_uid != os.getuid()):
        raise ValueError("root ownership differs")
    if os.name != "nt" and stat.S_IMODE(root.stat().st_mode) != 0o700:
        raise ValueError("root permissions differ")
    if set(p.name for p in root.iterdir()) != {"logs", "evidence", "tmp", "transport_private"}:
        raise ValueError("unexpected/preexisting deployment target")
    allowed = {"logs": set(), "tmp": set(), "evidence": {"key_preparation.json"},
               "transport_private": {"private.pem", "public.pem"}}
    for name, children in allowed.items():
        directory = safe_path(root / name)
        if not directory.is_dir() or set(p.name for p in directory.iterdir()) != children:
            raise ValueError("unexpected prepared directory content")
        if os.name != "nt" and (stat.S_IMODE(directory.stat().st_mode) != 0o700 or directory.stat().st_uid != os.getuid()):
            raise ValueError("prepared directory permissions/owner differ")
    prep_raw = read_regular(root / "evidence/key_preparation.json", 10_000)
    preparation = document(prep_raw)
    expected = {k: receipt[k] for k in ("experiment_id", "remote_root", "execution_contract_sha256",
                "public_key_sha256", "owner_uid", "cryptography_version")}
    if (preparation != expected or sha(prep_raw) != receipt["key_preparation_sha256"]
            or preparation["experiment_id"] != EXPERIMENT or preparation["execution_contract_sha256"] != CONTRACT_SHA
            or preparation["owner_uid"] != root.stat().st_uid):
        raise ValueError("key preparation receipt differs")
    public = read_regular(root / "transport_private/public.pem", 2000)
    public_identity(public)
    if sha(public) != receipt["public_key_sha256"] or public.decode() != receipt["public_pem"]:
        raise ValueError("prepared public key differs")
    private = safe_path(root / "transport_private/private.pem")
    if not private.is_file() or private.stat().st_nlink != 1:
        raise ValueError("private key target differs")
    if os.name != "nt" and (stat.S_IMODE(private.stat().st_mode) != 0o600 or private.stat().st_uid != os.getuid()):
        raise ValueError("private key permissions/owner differ")


def validate_release(files, manifest_raw):
    manifest, _ = manifest_files(manifest_raw)
    if {spec["relative_path"] for spec in manifest["source_files"]} != set(SOURCE_NAMES):
        raise ValueError("runtime source set differs")
    if sha(files["evaluate.slurm"]) != SCHEDULER_SHA:
        raise ValueError("fixed scheduler resource/cache script differs")
    contract_raw = files["contracts/execution_contract.json"]
    if sha(contract_raw) != CONTRACT_SHA:
        raise ValueError("frozen execution contract differs")
    contract = document(contract_raw)
    auth_raw = files["contracts/execution_authorization.json"]
    auth = document(auth_raw)
    for obj in (contract, auth):
        for key, expected in {"experiment_id": EXPERIMENT, "remote_root": REMOTE,
                "maximum_sbatch_submissions": 1, "gpus": 1, "cpus_per_task": 4,
                "maximum_walltime_hours": 1, "partition": "hgpu2p", "automatic_requeue": False,
                "automatic_retry": False, "noise_training_allowed": False}.items():
            if type(obj[key]) is not type(expected) or obj[key] != expected:
                raise ValueError("execution resource authority differs")
    if contract["model_training_allowed"] is not False or auth["parameter_updates_allowed"] is not False:
        raise ValueError("inference-only authority differs")
    for key, name in (("data_authorization", "contracts/data_authorization.json"),
                      ("execution_authorization", "contracts/execution_authorization.json"),
                      ("frozen_evaluation_inputs", "frozen_evaluation_inputs.json")):
        if sha(files[name]) != contract[key]["sha256"] or len(files[name]) != contract[key]["size_bytes"]:
            raise ValueError("bound metadata identity differs")
    expected_data = {"inputs/2024/" + row["relative_path"]: (row["size_bytes"], row["sha256"])
                     for row in contract["inputs_2024"]}
    actual_data = {row["relative_path"]: (row["byte_count"], row["sha256"]) for row in manifest["data_files"]}
    if actual_data != expected_data or len(actual_data) != 11 or sum(v[0] for v in actual_data.values()) != 8618387:
        raise ValueError("formal input set/budget differs")
    for spec in contract["runtime_dependencies"]:
        name = Path(spec["path"]).name
        if sha(files[name]) != spec["sha256"] or len(files[name]) != spec["size_bytes"]:
            raise ValueError("runtime dependency identity differs")


def submit_once(root, manifest_sha, run=None):
    root = safe_path(root)
    if not re.fullmatch("[0-9a-f]{64}", manifest_sha):
        raise ValueError("manifest digest required")
    attempt = safe_path(root / "evidence/submission/attempt_001")
    attempt.mkdir(mode=0o700, parents=True, exist_ok=False)
    command = ["sbatch", str(root / "evaluate.slurm"), manifest_sha]
    put(attempt / "requested.json", {"status": "one_submission_reserved", "command": command,
                                    "manifest_sha256": manifest_sha}, root)
    run = subprocess.run if run is None else run
    try:
        response = run(command, cwd=root, capture_output=True, check=False, timeout=35)
        write_new(attempt / "stdout.txt", response.stdout, root)
        write_new(attempt / "stderr.txt", response.stderr, root)
        put(attempt / "exit_status.json", {"returncode": response.returncode}, root)
        match = re.fullmatch(rb"Submitted batch job ([1-9][0-9]*)\n?", response.stdout)
        if response.returncode != 0 or not match:
            raise RuntimeError("submission failed or uncertain")
        receipt = {"status": "submitted", "job_id": match.group(1).decode(), "remote_root": str(root),
                   "manifest_sha256": manifest_sha, "submissions": 1, "automatic_retry": False,
                   "evaluation_complete": False}
        put(attempt / "submission_receipt.json", receipt, root)
        return receipt
    except BaseException as error:
        if isinstance(error, subprocess.TimeoutExpired):
            write_new(attempt / "stdout.txt", error.stdout or b"", root)
            write_new(attempt / "stderr.txt", error.stderr or b"", root)
            put(attempt / "exit_status.json", {"returncode": None, "timeout_seconds": 35}, root)
        else:
            if not (attempt / "stdout.txt").exists():
                write_new(attempt / "stdout.txt", b"", root)
            if not (attempt / "stderr.txt").exists():
                write_new(attempt / "stderr.txt", b"", root)
            if not (attempt / "exit_status.json").exists():
                put(attempt / "exit_status.json", {"returncode": None, "error_type": type(error).__name__}, root)
        put(attempt / "failure.json", {"status": "stopped_no_retry", "error_type": type(error).__name__,
                                       "automatic_retry": False}, root)
        raise


def deploy(root, envelope, manifest_raw, receipt, expected_envelope_sha, run=None):
    root = safe_path(root)
    if str(root) != REMOTE or sha(envelope) != expected_envelope_sha:
        raise ValueError("deployment root/cipher identity differs")
    verify_prepared(root, receipt)
    metadata = {"experiment_id": EXPERIMENT, "remote_root": REMOTE,
                "execution_contract_sha256": CONTRACT_SHA, "public_key_sha256": receipt["public_key_sha256"],
                "bundle_manifest_sha256": sha(manifest_raw)}
    attempt = root / "evidence/deployment_attempt_001"
    attempt.mkdir(mode=0o700, exist_ok=False)
    put(attempt / "requested.json", {"envelope_sha256": expected_envelope_sha, **metadata}, root)
    try:
        packed = decrypt_bundle(envelope, read_regular(root / "transport_private/private.pem", 5000), metadata)
        files = unpack_bundle(packed, manifest_raw)
        validate_release(files, manifest_raw)
        # Every eventual target is checked before the first plaintext extraction.
        for name in (*files, "bundle_manifest.json", "results", "evidence/submission"):
            if safe_path(root / safe_name(name)).exists():
                raise FileExistsError("deployment output collision")
        put(attempt / "decryption.json", {"authenticated": True, "packed_bytes": len(packed),
                "packed_sha256": sha(packed), "member_count": len(files),
                "decrypted_input_bytes": sum(len(v) for k, v in files.items() if k.startswith("inputs/")),
                "disk_formal_read_count": 0}, root)
        for name, raw in files.items():
            write_new(root / name, raw, root)
        write_new(root / "bundle_manifest.json", manifest_raw, root)
        for name in ("xdg", "matplotlib", "numba", "cuda", "torch_extensions", "torchinductor", "triton"):
            (root / "tmp" / name).mkdir(mode=0o700, exist_ok=False)
        return submit_once(root, sha(manifest_raw), run)
    except BaseException as error:
        put(attempt / "failure.json", {"status": "stopped_no_retry", "error_type": type(error).__name__}, root)
        raise



if __name__ == '__main__':
    crypto_imports()
    try:
        partition = subprocess.run(['sinfo', '-h', '-p', 'hgpu2p', '-o', '%P|%a|%D|%t'], capture_output=True, check=False, timeout=10)
        status = {'returncode': partition.returncode, 'stdout': partition.stdout[:4000].decode(errors='replace')}
    except (OSError, subprocess.TimeoutExpired) as error:
        status = {'unavailable': type(error).__name__}
    print('TEMPORAL_PARTITION_JSON_BEGIN')
    print(canonical(status).decode(), end='')
    print('TEMPORAL_PARTITION_JSON_END')
    receipt = prepare_root(Path(REMOTE), Path('/data1/home/sunyiq'))
    print('TEMPORAL_KEY_JSON_BEGIN')
    print(canonical(receipt).decode(), end='')
    print('TEMPORAL_KEY_JSON_END')

TEMPORAL_REMOTE_PY
