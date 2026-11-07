"""Trusted CLI test bootstrap; Core authenticates selection before invocation.

The selectable bundle supplies tests only. Product, payload, configuration and
mandatory wrapper/canonical release gates are independently fixed by the caller.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import unittest
sys.dont_write_bytecode = True
REPOSITORY = "cwru-non-academic/CLI_Python_WSS_Application"


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def checkout(root: Path, sha: str, paths: tuple[str, ...] = ()) -> None:
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise ValueError("Expected immutable full source SHA")
    if Path(git(root, "rev-parse", "--show-toplevel")).resolve() != root or git(root, "rev-parse", "HEAD") != sha:
        raise ValueError("Checkout root or SHA differs from frozen source")
    if any(not line.startswith("H ") for line in git(root, "ls-files", "-v", "--", *paths).splitlines()):
        raise ValueError("Source index flags may hide changes")
    if git(root, "status", "--porcelain", "--untracked-files=all", "--ignored", "--", *paths):
        raise ValueError("Changed or untracked source files")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def resolve_tests(root: Path, sha: str, repository: str, selection: str, product: Path) -> dict:
    if not all((str(root), sha, repository, selection)) or repository != REPOSITORY or not re.fullmatch(r"[0-9a-f]{64}", selection):
        raise ValueError("Incomplete or invalid immutable test binding")
    if root == product:
        raise ValueError("Selected tests require their own checkout")
    checkout(root, sha)
    if git(root, "status", "--porcelain", "--untracked-files=all", "--ignored", "--", "conformance"):
        raise ValueError("Selected conformance contains ignored/untracked overrides")
    modes = git(root, "ls-files", "--stage", "--", "conformance").splitlines()
    if any(not line.startswith("100644 ") for line in modes):
        raise ValueError("Tests must be regular tracked files")
    path = root / "conformance/test-contract.json"
    contract = json.loads(path.read_text(encoding="utf-8-sig"))
    if set(contract) != {"schema", "test_files"} or contract["schema"] != "wss-python-cli-tests/v1":
        raise ValueError("Invalid test-only contract")
    files = contract["test_files"]
    if not isinstance(files, list) or not files or len(files) != len(set(files)) or "test_modeled_commands.py" not in files:
        raise ValueError("Mandatory command matrix missing or duplicated")
    if any(not isinstance(name, str) or not re.fullmatch(r"test_[A-Za-z0-9_]+\.py", name) for name in files):
        raise ValueError("Unsafe selected test path")
    selected = [(root / "conformance" / name).resolve() for name in files]
    if any(not file.is_relative_to(root / "conformance") or not file.is_file() for file in selected):
        raise ValueError("Selected test escaped its bundle")
    return {"root": root, "sha": sha, "repository": repository, "selection": selection,
            "contract_hash": sha256(path), "files": selected,
            "hashes": {str(file): sha256(file) for file in selected}}


def recheck_tests(tests: dict, product: Path) -> None:
    fresh = resolve_tests(tests["root"], tests["sha"], tests["repository"], tests["selection"], product)
    if fresh != tests:
        raise ValueError("Test source changed during execution")


def inventory(payload: Path) -> dict[str, str]:
    files = sorted(path for path in payload.rglob("*") if path.is_file())
    if not (payload / "WSS_Core_Interface.dll").is_file():
        raise ValueError("Missing exact selected Core payload")
    return {str(path.relative_to(payload)): sha256(path) for path in files}


def flatten(suite):
    for item in suite:
        if isinstance(item, unittest.TestSuite):
            yield from flatten(item)
        else:
            yield item


def run(args) -> None:
    product, wrapper, payload, test_root = (Path(value).resolve() for value in (args.product_root, args.wrapper_root, args.payload_root, args.test_root))
    checkout(product, args.product_sha, ("src", "Config", ".github"))
    checkout(wrapper, args.wrapper_sha, ("src", ".github"))
    config = json.loads((product / ".github/python-ci.json").read_text(encoding="utf-8-sig"))
    if config.get("baseline_ready") is not True:
        raise ValueError("Product readiness is not selectable")
    tests = resolve_tests(test_root, args.test_sha, args.test_repository, args.test_selection_id, product)
    payload_before = inventory(payload)
    evidence = Path(args.evidence).resolve()
    if any(evidence.is_relative_to(root) for root in (product, wrapper, test_root, payload)):
        raise ValueError("Evidence must be outside immutable input roots")
    if evidence.exists():
        raise ValueError("Evidence must be new")
    evidence.parent.mkdir(parents=True, exist_ok=True)
    os.environ["WSS_TEST_PAYLOAD"] = str(payload)
    sys.path[:0] = [str(product / "src"), str(wrapper / "src")]
    modules = []
    suites = []
    for index, file in enumerate(tests["files"]):
        spec = importlib.util.spec_from_file_location(f"wss_selected_cli_{index}", file)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        modules.append(module)
        suites.append(unittest.defaultTestLoader.loadTestsFromModule(module))
    def assert_product_modules():
        cli = importlib.import_module("wss_cli.main")
        implementation = importlib.import_module("wss_py_wrapper")
        if not Path(cli.__file__).resolve().is_relative_to(product / "src") or not Path(implementation.__file__).resolve().is_relative_to(wrapper / "src"):
            raise ValueError("Selected tests changed production Python module roots")
        import clr
        from Wss.Testing import WssStimulationSequences
        if Path(str(clr.GetClrType(WssStimulationSequences).Assembly.Location)).resolve() != payload / "WSS_Core_Interface.dll":
            raise ValueError("Tests loaded a different Core payload")
    assert_product_modules()
    required = {"test_analog_multichannel-isolation", "test_analog_multidevice-isolation"}
    required |= {f"test_modeled_{model}_{mode}_{stage}" for model in ("p", "pd") for mode in ("pw", "pa") for stage in ("single", "multi")}
    all_tests = list(flatten(unittest.TestSuite(suites)))
    canonical = [test for test in all_tests if test.__class__.__name__ == "ModeledCommandTests"]
    names = [test._testMethodName for test in canonical]
    if len(names) != 10 or set(names) != required:
        raise ValueError("Mandatory production command inventory changed")
    result = run_selected_suite(all_tests)
    recheck_tests(tests, product)
    checkout(product, args.product_sha, ("src", "Config", ".github"))
    checkout(wrapper, args.wrapper_sha, ("src", ".github"))
    assert_product_modules()
    if inventory(payload) != payload_before:
        raise ValueError("Selected payload changed during test execution")
    record = {"schema": "wss-selected-python-cli-tests/v1", "product_root": str(product), "product_sha": args.product_sha,
              "wrapper_root": str(wrapper), "wrapper_sha": args.wrapper_sha, "payload_root": str(payload),
              "test_root": str(test_root), "test_sha": tests["sha"], "test_repository": tests["repository"],
              "test_selection_id": tests["selection"], "test_contract_sha256": tests["contract_hash"],
              "tests_run": result.testsRun, "mandatory_cases": sorted(required), "passed": True}
    with evidence.open("x", encoding="utf-8") as stream:
        json.dump(record, stream, indent=2)
        stream.write("\n")


def run_selected_suite(all_tests):
    expected_count = len(all_tests)
    result = unittest.TextTestRunner(verbosity=2).run(unittest.TestSuite(all_tests))
    if result.testsRun != expected_count:
        raise ValueError("Selected CLI test execution did not complete the discovered inventory")
    if not result.wasSuccessful() or result.skipped or result.expectedFailures or result.unexpectedSuccesses:
        raise ValueError("Selected CLI tests failed, skipped, or expected failure")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("product-root", "product-sha", "wrapper-root", "wrapper-sha", "payload-root", "test-root", "test-sha", "test-repository", "test-selection-id", "evidence"):
        parser.add_argument("--" + name, required=True)
    run(parser.parse_args())


if __name__ == "__main__":
    main()