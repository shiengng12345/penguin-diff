#!/usr/bin/env python3
"""Negative tests for evidence gates. Imports do not launch App/server/Vault."""
import ast
import contextlib
import importlib.util
import io
import json
import os
import pathlib
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("network_verifier", ROOT/"scripts/check-network.py")
network = importlib.util.module_from_spec(spec)
spec.loader.exec_module(network)
manifest_spec = importlib.util.spec_from_file_location("local_verifier", ROOT/"scripts/verify-local.py")
local = importlib.util.module_from_spec(manifest_spec)
manifest_spec.loader.exec_module(local)
oracle_spec = importlib.util.spec_from_file_location("js_oracle", ROOT/"scripts/check-js-oracle.py")
oracle = importlib.util.module_from_spec(oracle_spec)
oracle_spec.loader.exec_module(oracle)
depth_spec = importlib.util.spec_from_file_location("depth_verifier", ROOT/"scripts/check-depth-guards.py")
depth = importlib.util.module_from_spec(depth_spec)
depth_spec.loader.exec_module(depth)
vendor_spec = importlib.util.spec_from_file_location("vendor_verifier", ROOT/"scripts/check-oxc-vendor.py")
vendor = importlib.util.module_from_spec(vendor_spec)
vendor_spec.loader.exec_module(vendor)
reports_spec = importlib.util.spec_from_file_location("report_verifier", ROOT/"scripts/check-reports.py")
reports = importlib.util.module_from_spec(reports_spec)
reports_spec.loader.exec_module(reports)


class LocalRunEvidenceTests(unittest.TestCase):
    @contextlib.contextmanager
    def fixture(self, code="pass", runner_error=None, missing_initial=False, old_pass=False, empty=False):
        with tempfile.TemporaryDirectory(prefix="config-compare-gate-") as temporary:
            root=pathlib.Path(temporary)
            for name in ["Cargo.toml","Cargo.lock","apps/macos/Package.swift","apps/macos/Package.resolved"]:
                path=root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text("synthetic")
            out=root/"verification";out.mkdir()
            if old_pass:(out/"results.json").write_text(json.dumps({"passed":True,"runID":"previous"}))
            if missing_initial:(root/"Cargo.lock").unlink()
            commands=[] if empty else [("synthetic-check",[sys.executable,"-c",code])]
            original=local.source_manifest
            with contextlib.ExitStack() as stack:
                for name,value in [("ROOT",root),("OUT",out),("COMMANDS",commands)]:
                    stack.enter_context(mock.patch.object(local,name,value))
                # Only redirect the manifest's default root to the owned fixture.
                # Hashing and the normal subprocess/file operations remain real.
                stack.enter_context(mock.patch.object(local,"source_manifest",lambda:original(root)))
                if runner_error is not None:
                    stack.enter_context(mock.patch.object(local.subprocess,"run",side_effect=runner_error))
                stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
                yield root,out

    def evidence(self,out):
        self.assertTrue((out/"results.json").is_file(),"Every failed run must record failed evidence")
        return json.loads((out/"results.json").read_text())

    def test_success_records_final_manifest_and_overall_pass(self):
        with self.fixture() as (_,out):
            local.main();result=self.evidence(out)
            self.assertIs(result.get("passed"),True)
            self.assertIs(result.get("finished"),True)
            self.assertIs(result.get("manifestStable"),True)
            self.assertEqual(result.get("finalManifestSHA256"),result["candidateSHA256"])
            self.assertEqual(result.get("expectedCommandCount"),1)
            self.assertIsNone(result.get("failure"))

    def test_source_change_after_all_exit_zero_is_never_pass(self):
        with self.fixture('import pathlib;pathlib.Path("Cargo.toml").write_text("changed")') as (_,out):
            with self.assertRaises(RuntimeError):local.main()
            result=self.evidence(out)
            self.assertEqual([row["exitCode"] for row in result["commands"]],[0])
            self.assertIs(result.get("passed"),False)
            self.assertIs(result.get("manifestStable"),False)
            self.assertIs(result.get("finished"),True)
            self.assertNotEqual(result.get("finalManifestSHA256"),result["candidateSHA256"])
            self.assertEqual(result.get("failure",{}).get("code"),"SOURCE_CHANGED")

    def test_command_failure_keeps_its_code_even_when_manifest_is_stable(self):
        with self.fixture("import sys;sys.exit(7)") as (_,out):
            with self.assertRaises(SystemExit) as caught:local.main()
            self.assertEqual(caught.exception.code,7)
            result=self.evidence(out)
            self.assertIs(result.get("passed"),False)
            self.assertIs(result.get("manifestStable"),True)
            self.assertEqual(result.get("failure",{}).get("code"),"COMMAND_FAILED")
            self.assertEqual(result["commands"][0]["exitCode"],7)

    def test_initial_manifest_failure_has_failed_result_instead_of_old_pass(self):
        with self.fixture(missing_initial=True,old_pass=True) as (_,out):
            with self.assertRaises(FileNotFoundError):local.main()
            result=self.evidence(out)
            self.assertIs(result.get("passed"),False)
            self.assertIsNone(result.get("candidateSHA256"))
            self.assertIsNone(result.get("finalManifestSHA256"))
            self.assertEqual(result.get("failure",{}).get("code"),"INITIAL_MANIFEST_UNAVAILABLE")
            self.assertNotEqual(result.get("runID"),"previous")

    def test_final_manifest_unavailable_does_not_accept_zero_exit_commands(self):
        with self.fixture('import pathlib;pathlib.Path("Cargo.lock").unlink()') as (_,out):
            with self.assertRaises(FileNotFoundError):local.main()
            result=self.evidence(out)
            self.assertIs(result.get("passed"),False)
            self.assertIs(result.get("manifestStable"),False)
            self.assertIsNone(result.get("finalManifestSHA256"))
            self.assertEqual(result.get("failure",{}).get("code"),"FINAL_MANIFEST_UNAVAILABLE")

    def test_timeout_records_failed_command_without_exception_payload(self):
        with self.fixture(runner_error=subprocess.TimeoutExpired(["PRIVATE_EXCEPTION_CANARY"],900)) as (_,out):
            with self.assertRaises(subprocess.TimeoutExpired):local.main()
            result=self.evidence(out)
            self.assertIs(result.get("passed"),False)
            self.assertEqual(result.get("failure",{}).get("code"),"COMMAND_TIMEOUT")
            self.assertEqual(len(result["commands"]),1)
            self.assertIsNone(result["commands"][0]["exitCode"])
            self.assertNotIn("PRIVATE_EXCEPTION_CANARY",json.dumps(result))

    def test_interrupt_records_failure_and_finishes_evidence(self):
        with self.fixture(runner_error=KeyboardInterrupt()) as (_,out):
            with self.assertRaises(KeyboardInterrupt):local.main()
            result=self.evidence(out)
            self.assertIs(result.get("passed"),False)
            self.assertIs(result.get("finished"),True)
            self.assertEqual(result.get("failure",{}).get("code"),"INTERRUPTED")
            self.assertEqual(len(result["commands"]),1)

    def test_empty_gate_list_is_not_a_successful_run(self):
        with self.fixture(empty=True) as (_,out):
            with self.assertRaises(RuntimeError):local.main()
            self.assertIs(self.evidence(out).get("passed"),False)
            self.assertEqual(self.evidence(out).get("failure",{}).get("code"),"NO_COMMANDS")

    def test_previous_pass_is_replaced_before_first_command_starts(self):
        code='import json,pathlib,sys;r=json.loads(pathlib.Path("verification/results.json").read_text());sys.exit(0 if r.get("passed") is False and r.get("finished") is False and r.get("runID")!="previous" else 19)'
        with self.fixture(code,old_pass=True) as (_,out):
            local.main()
            self.assertIs(self.evidence(out).get("passed"),True)

    def test_final_result_write_failure_does_not_emit_success_or_replace_unfinished_state(self):
        replace=local.os.replace
        calls=0
        def fail_final(*args,**kwargs):
            nonlocal calls
            calls+=1
            if calls==2:raise OSError("synthetic final evidence disk failure")
            return replace(*args,**kwargs)
        with self.fixture(old_pass=True) as (_,out):
            output=io.StringIO()
            with mock.patch.object(local.os,"replace",side_effect=fail_final),contextlib.redirect_stdout(output):
                with self.assertRaises(OSError):local.main()
            result=self.evidence(out)
            self.assertIs(result.get("passed"),False)
            self.assertIs(result.get("finished"),False)
            self.assertNotIn("LOCAL_AUTOMATED_GATE_OK",output.getvalue())
            self.assertEqual(list(out.glob(".results-*")),[])

    def test_spawn_failure_is_recorded_without_exception_payload(self):
        with self.fixture(runner_error=OSError("PRIVATE_EXCEPTION_CANARY")) as (_,out):
            with self.assertRaises(OSError):local.main()
            result=self.evidence(out)
            self.assertIs(result.get("passed"),False)
            self.assertEqual(result.get("failure",{}).get("code"),"COMMAND_ERROR")
            self.assertEqual(result["commands"][0].get("errorClass"),"OSError")
            self.assertNotIn("PRIVATE_EXCEPTION_CANARY",json.dumps(result))

    def test_changed_command_count_cannot_emit_success_with_failed_overall_state(self):
        real_run=subprocess.run
        def add_command(*args,**kwargs):
            if len(local.COMMANDS)==1:
                local.COMMANDS.append(("added-check",[sys.executable,"-c","pass"]))
            return real_run(*args,**kwargs)
        with self.fixture() as (_,out):
            output=io.StringIO()
            with mock.patch.object(local.subprocess,"run",side_effect=add_command),contextlib.redirect_stdout(output):
                with self.assertRaises(RuntimeError):local.main()
            result=self.evidence(out)
            self.assertIs(result.get("passed"),False)
            self.assertEqual(result.get("expectedCommandCount"),1)
            self.assertEqual(len(result["commands"]),2)
            self.assertEqual(result.get("failure",{}).get("code"),"VERIFICATION_INCOMPLETE")
            self.assertNotIn("LOCAL_AUTOMATED_GATE_OK",output.getvalue())


class NetworkRunEvidenceTests(unittest.TestCase):
    @contextlib.contextmanager
    def fixture(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory); (root / "build").mkdir()
            with mock.patch.object(network, "ROOT", root), contextlib.redirect_stdout(io.StringIO()):
                yield root / "build"

    def synthetic_swift(self, build, primary=0, discovery=0):
        binary = build / "bin/swift"
        binary.parent.mkdir()
        binary.write_text("""#!/usr/bin/env python3
import os,pathlib,sys
phase = 'discovery' if 'list' in sys.argv else 'primary'
pathlib.Path(os.environ['SYNTHETIC_EVENTS'] + '-' + phase).write_text('started')
sys.stdout.write('primary synthetic output' if phase == 'primary' else 'discovery output')
sys.stderr.write('primary diagnostic' if phase == 'primary' else 'discovery diagnostic')
raise SystemExit(int(os.environ['SYNTHETIC_' + phase.upper()]))
""")
        binary.chmod(0o700)
        return dict(os.environ, PATH=str(binary.parent)+os.pathsep+os.environ["PATH"],
                    SYNTHETIC_EVENTS=str(build / "event"), SYNTHETIC_PRIMARY=str(primary),
                    SYNTHETIC_DISCOVERY=str(discovery))

    def test_discovery_failure_preserves_primary_output_and_exit_code(self):
        with self.fixture() as build:
            environment = self.synthetic_swift(build, discovery=7)
            with self.assertRaises(SystemExit) as caught: network.run_swift_tests(environment)
            self.assertEqual(caught.exception.code, 7)
            self.assertEqual((build / "network-check.log").read_text(), "primary synthetic outputprimary diagnostic")
            self.assertEqual((build / "network-inventory.log").read_text(), "discovery outputdiscovery diagnostic")

    def test_failed_primary_run_is_saved_and_never_launches_discovery(self):
        with self.fixture() as build:
            environment = self.synthetic_swift(build, primary=9)
            with self.assertRaises(SystemExit) as caught: network.run_swift_tests(environment)
            self.assertEqual(caught.exception.code, 9)
            self.assertFalse((build/"event-discovery").exists())
            self.assertEqual((build / "network-check.log").read_text(), "primary synthetic outputprimary diagnostic")

    def test_timeout_preserves_partial_primary_output(self):
        with self.fixture() as build:
            script = "import sys,time; sys.stdout.write('partial output'); sys.stdout.flush(); sys.stderr.write('partial diagnostic'); sys.stderr.flush(); time.sleep(1)"
            with self.assertRaises(subprocess.TimeoutExpired):
                network.captured_run(["rtk","proxy",sys.executable,"-c",script],dict(os.environ),build/"network-check.log",0.2)
            self.assertEqual((build / "network-check.log").read_text(), "partial outputpartial diagnostic")

    def test_failed_new_run_replaces_old_pass_without_exception_payload(self):
        with self.fixture() as build:
            (build / "network-check.json").write_text('{"passed":true}')
            (build / "network-check.log").write_text("previous run")
            for error in [RuntimeError("PRIVATE_EXCEPTION_CANARY"), KeyboardInterrupt(), SystemExit(7)]:
                with mock.patch.object(network, "run_matrix", side_effect=error):
                    with self.assertRaises(type(error)): network.main()
                evidence = json.loads((build / "network-check.json").read_text())
                self.assertIs(evidence["passed"], False); self.assertIs(evidence["finished"], True)
                self.assertNotIn("PRIVATE_EXCEPTION_CANARY", json.dumps(evidence))
                self.assertEqual((build / "network-check.log").read_text(), "")

    def test_timeout_stops_owned_descendants_and_preserves_partial_output(self):
        with self.fixture() as build:
            stopped = build / "child-stopped"
            parent_id, child_id = build / "parent.json", build / "child.json"
            child = ("import os,signal,time,pathlib; "
                     f"signal.signal(signal.SIGTERM,lambda *_:(pathlib.Path({str(stopped)!r}).write_text('stopped'),os._exit(0))); "
                     f"pathlib.Path({str(child_id)!r}).write_text(str(os.getpid())); "
                     "print('synthetic child ready',flush=True); time.sleep(5)")
            parent = ("import os,pathlib,subprocess,sys,time; "
                      f"subprocess.Popen(['rtk','proxy',sys.executable,'-c',{child!r}]); "
                      f"pathlib.Path({str(parent_id)!r}).write_text(str(os.getpid())); "
                      "print('synthetic primary ready',flush=True); time.sleep(5)")
            began = time.monotonic()
            with self.assertRaises(subprocess.TimeoutExpired):
                network.captured_run(["rtk","proxy",sys.executable,"-c",parent],dict(os.environ),build/"output.log",1)
            self.assertLess(time.monotonic()-began,3.5,"A one-second timeout must not wait five seconds for inherited pipes")
            self.assertTrue(parent_id.is_file() and child_id.is_file(),"Both owned processes must actually start")
            self.assertOwnedProcessesStopped({int(parent_id.read_text()),int(child_id.read_text())})
            self.assertTrue(stopped.is_file(),"Owned descendants must receive termination")
            output = (build/"output.log").read_text()
            self.assertIn("synthetic primary ready",output)
            self.assertIn("synthetic child ready",output)

    def test_timeout_kills_owned_descendants_that_ignore_termination(self):
        with self.fixture() as build:
            parent_id, child_id = build / "parent.json", build / "child.json"
            child = ("import os,pathlib,signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); "
                     f"pathlib.Path({str(child_id)!r}).write_text(str(os.getpid())); "
                     "print('synthetic ignoring child ready',flush=True); time.sleep(5)")
            parent = ("import os,pathlib,signal,subprocess,sys,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); "
                      f"subprocess.Popen(['rtk','proxy',sys.executable,'-c',{child!r}]); "
                      f"pathlib.Path({str(parent_id)!r}).write_text(str(os.getpid())); "
                      "print('synthetic ignoring primary ready',flush=True); time.sleep(5)")
            began = time.monotonic()
            with self.assertRaises(subprocess.TimeoutExpired):
                network.captured_run(["rtk","proxy",sys.executable,"-c",parent],dict(os.environ),build/"output.log",1)
            self.assertLess(time.monotonic()-began,3.5,"SIGTERM-resistant inherited pipes must not extend the deadline")
            self.assertTrue(parent_id.is_file() and child_id.is_file(),"Both owned processes must actually start")
            self.assertOwnedProcessesStopped({int(parent_id.read_text()),int(child_id.read_text())})
            self.assertIn("synthetic ignoring child ready",(build/"output.log").read_text())

    def assertOwnedProcessesStopped(self, pids):
        # Only inspect PIDs published by our finite synthetic children. No args
        # are read and no other process, App or process group is signalled.
        deadline = time.monotonic()+1
        while True:
            rows = subprocess.check_output(["rtk","proxy","ps","-axo","pid,stat"],text=True).splitlines()
            alive = [int(parts[0]) for line in rows if len(parts:=line.split())==2
                     and parts[0].isdigit() and int(parts[0]) in pids and not parts[1].startswith("Z")]
            if not alive or time.monotonic()>=deadline:break
            time.sleep(0.02)
        self.assertEqual(alive,[],"Owned descendants must be stopped before captured_run returns")

    def test_successful_primary_exit_cannot_leave_an_owned_child_running(self):
        with self.fixture() as build:
            child_id = build / "child.pid"
            child = ("import os,pathlib,time; "
                     f"pathlib.Path({str(child_id)!r}).write_text(str(os.getpid())); time.sleep(5)")
            parent = ("import pathlib,subprocess,sys,time; "
                      f"subprocess.Popen(['rtk','proxy',sys.executable,'-c',{child!r}],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,stdin=subprocess.DEVNULL); "
                      f"record=pathlib.Path({str(child_id)!r}); deadline=time.monotonic()+2; "
                      "\nwhile not record.exists() and time.monotonic()<deadline:time.sleep(0.01)\n"
                      "print('synthetic primary complete',flush=True)")
            result = network.captured_run(["rtk","proxy",sys.executable,"-c",parent],dict(os.environ),build/"output.log",3)
            self.assertEqual(result.returncode,0)
            self.assertTrue(child_id.is_file(),"The owned child must actually start")
            self.assertOwnedProcessesStopped({int(child_id.read_text())})

    def test_keyboard_interrupt_stops_owned_children_and_keeps_partial_log(self):
        with self.fixture() as build:
            child_id = build / "child.pid"
            parent = ("import os,pathlib,time; "
                      f"pathlib.Path({str(child_id)!r}).write_text(str(os.getpid())); "
                      "print('synthetic interrupted child ready',flush=True);time.sleep(5)")
            timer = threading.Timer(1,lambda:os.kill(os.getpid(),signal.SIGINT))
            timer.start()
            try:
                with self.assertRaises(KeyboardInterrupt):
                    network.captured_run(["rtk","proxy",sys.executable,"-c",parent],dict(os.environ),build/"output.log",8)
            finally:
                timer.cancel(); timer.join(timeout=2)
            self.assertTrue(child_id.is_file())
            self.assertOwnedProcessesStopped({int(child_id.read_text())})
            self.assertIn("synthetic interrupted child ready",(build/"output.log").read_text())

    def test_primary_failure_records_stage_and_actual_suite_exit(self):
        with self.fixture() as build:
            environment = self.synthetic_swift(build,primary=9)
            with mock.patch.dict(os.environ,environment):
                with self.assertRaises(SystemExit):network.main()
            report = json.loads((build/"network-check.json").read_text())
            self.assertEqual(report["failure"].get("stage"),"primary")
            self.assertEqual(report["suiteExitCode"],9)

    def test_discovery_failure_keeps_the_successful_primary_exit(self):
        with self.fixture() as build:
            environment = self.synthetic_swift(build,discovery=7)
            with mock.patch.dict(os.environ,environment):
                with self.assertRaises(SystemExit):network.main()
            report = json.loads((build/"network-check.json").read_text())
            self.assertEqual(report["failure"].get("stage"),"discovery")
            self.assertEqual(report["suiteExitCode"],0)

    def test_validation_failure_cannot_erase_successful_process_exit_codes(self):
        with self.fixture() as build:
            environment = self.synthetic_swift(build)
            with mock.patch.dict(os.environ,environment):
                with self.assertRaises(RuntimeError):network.main()
            report = json.loads((build/"network-check.json").read_text())
            self.assertEqual(report["failure"].get("stage"),"validation")
            self.assertEqual(report["suiteExitCode"],0)


class EvidenceGateTests(unittest.TestCase):
    def test_csv_gate_rejects_missing_rows_wrong_columns_bad_quotes_and_changed_values(self):
        good = 'path,status,a_type,b_type,a_value,b_value\r\n"$.x","ONLY_A","Number","Missing","\'-42","<不存在>"\r\n'
        expected = [["$.x","ONLY_A","Number","Missing","'-42","<不存在>"]]
        self.assertEqual(reports.validate_csv(good, expected), 1)
        for broken in ["", good.splitlines(keepends=True)[0], good.replace(',"Missing"', ''),
                       good.replace("'-42", "-42"), good.replace("\r\n", "\n"),
                       good.replace('"$.x"', '"$.x"bad'), good + good.splitlines(keepends=True)[1]]:
            with self.assertRaises(RuntimeError): reports.validate_csv(broken, expected)

    def test_report_runner_rejects_crashes_stderr_empty_and_failed_responses(self):
        good = json.dumps({"ok":True}) + "\n"
        self.assertEqual(reports.validate_run(0, good, "", 1), [{"ok":True}])
        for status, text, stderr, count in [(1,good,"",1),(0,good,"private",1),(0,"","",1),
                    (0,good,"",2),(0,'{"ok":false}\n',"",1),(0,"[]\n","",1)]:
            with self.assertRaises(RuntimeError): reports.validate_run(status,text,stderr,count)

    def test_report_gate_optimization_does_not_remove_checks(self):
        function = next(n for n in ast.parse((ROOT/"scripts/check-reports.py").read_text()).body
                        if isinstance(n,ast.FunctionDef) and n.name=="require")
        result = subprocess.run(["rtk","proxy",sys.executable,"-O","-c",
                                 ast.unparse(function)+"\nrequire(False,'report negative fixture')\n"],capture_output=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn(b"report negative fixture", result.stderr)

    def test_typed_report_gate_rejects_lost_nested_types_units_and_redaction(self):
        case = reports.corpus()[1]
        report = {"ok":True,"schemaVersion":1,"policyVersion":1,"complete":True,
                  "includesValues":True,"exportedCount":1,"summary":reports.summary(case["rows"]),
                  "rows":json.loads(json.dumps(case["rows"])),"warnings":[],"warningCount":0,
                  "hasMoreWarnings":False,"incompleteRanges":[]}
        report["rows"][0].update(id=0)
        report["rows"][0]["a"].update(line=1,column=1)
        reports.validate_json(report,case["rows"],report["summary"],True,True)
        for damage in ["rows","includesValues","summary","units","number","type"]:
            broken = json.loads(json.dumps(report))
            if damage=="rows": broken["rows"]=[]
            elif damage=="includesValues": broken["includesValues"]=False
            elif damage=="summary": broken["summary"]["total"]=200
            elif damage=="units": broken["rows"][0]["a"]["entries"][1]["value"]["units"]=[65533]
            elif damage=="number": broken["rows"][0]["a"]["entries"][0]["value"]["items"][1]["literal"]="9007199254740992"
            else: del broken["rows"][0]["a"]["entries"][0]["value"]["items"][0]["type"]
            with self.assertRaises(RuntimeError): reports.validate_json(broken,case["rows"],report["summary"],True,True)
        redacted = json.loads(json.dumps(report))
        redacted["includesValues"]=False
        for side in ["a","b"]:
            original=redacted["rows"][0][side]
            redacted["rows"][0][side]={"type":original["type"],"present":original["present"],"display":"<值未导出>"}
        reports.validate_json(redacted,case["rows"],report["summary"],True,False)
        redacted["rows"][0]["a"]["literal"]="private"
        with self.assertRaises(RuntimeError): reports.validate_json(redacted,case["rows"],report["summary"],True,False)
    def test_vendor_gate_rejects_upstream_changes_missing_files_and_patch_tampering(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=pathlib.Path(temporary)
            copy=root/"vendor/oxc_parser"
            shutil.copytree(ROOT/"vendor/oxc_parser",copy)
            self.assertTrue(vendor.validate(root)["passed"])
            for name in ["src/js/expression.rs","src/cursor.rs","stack-budget.patch","LICENSE"]:
                file=copy/name;before=file.read_bytes();file.write_bytes(before+b"\nchanged\n")
                with self.assertRaises(RuntimeError): vendor.validate(root)
                file.write_bytes(before)
            original=copy/"README.md";before=original.read_bytes();original.unlink()
            with self.assertRaises(RuntimeError): vendor.validate(root)
            original.write_bytes(before)
            (copy/"unexpected.rs").write_text("synthetic")
            with self.assertRaises(RuntimeError): vendor.validate(root)
    def test_depth_probe_rejects_crash_stderr_wrong_error_and_missing_recovery(self):
        accepted=json.dumps({"ok":False,"error":{"code":"RESOURCE_LIMIT"}})
        recovered=json.dumps({"ok":True,"complete":True,"summary":{"same":1}})
        good=accepted+"\n"+recovered+"\n"
        self.assertTrue(depth.validate_run(0,good,"","synthetic")["recoveryPassed"])
        for status,output,error in [(134,"",""),(0,good,"private"),(0,accepted,""),
            (0,good.replace("RESOURCE_LIMIT","WORKER_INTERRUPTED"),""),
            (0,good.replace('"same": 1','"same": 0'),""),
            (0,json.dumps({"ok":False,"error":{"code":"RESOURCE_LIMIT"},"rows":[]})+"\n"+recovered,""),
            (0,"{}\n"+recovered,"")]:
            with self.assertRaises(RuntimeError): depth.validate_run(status,output,error,"synthetic")
    def test_trusted_js_corpus_covers_every_comparable_status(self):
        generated = subprocess.run(["rtk", "proxy", "node", "--input-type=commonjs", "-e", oracle.ORACLE],
                                   capture_output=True, text=True, check=True, timeout=60)
        cases = json.loads(generated.stdout)
        covered = {row["status"] for case in cases for row in case["rows"]}
        self.assertEqual(covered, {"SAME", "VALUE_CHANGED", "TYPE_CHANGED", "ONLY_A", "ONLY_B"})

    def test_oracle_rejects_missing_or_incorrect_core_replies(self):
        validator = getattr(oracle, "validate_cases", None)
        self.assertTrue(callable(validator), "oracle must independently validate each build profile")
        case = {"template":0,"iteration":0,"rows":[]}
        for lines in [[], [json.dumps({"ok":False})], [json.dumps({"ok":True,"complete":True,"rows":[],"summary":{"total":9}})]]:
            with self.assertRaises(RuntimeError): validator([case], lines)
        valid = {"ok":True,"complete":True,"rows":[],"summary":dict.fromkeys(["total","notComparable","same","valueChanged","typeChanged","onlyA","onlyB","differences"],0),"warnings":[],"warningCount":0,"hasMoreWarnings":False}
        self.assertEqual(validator([case],[json.dumps(valid)])["rowsChecked"],0)
        for key,value in [("warningCount",None),("warningCount",False),("warningCount",1),("hasMoreWarnings",True),("warnings",None)]:
            changed=valid | {key:value}
            with self.assertRaises(RuntimeError):validator([case],[json.dumps(changed)])

    def fixture(self):
        names = [f"discoveredTest{index}" for index in range(9)]
        inventory = "\n".join(f"CompareTests.HTTPTransportIntegration/{name}()" for name in names)
        output = "◇ Test run started.\n◇ Suite HTTPTransportIntegration started.\n" + "\n".join(f"◇ Test {name}() started.\n✔ Test {name}() passed after 0.01 seconds." for name in names) + "\n✔ Suite HTTPTransportIntegration passed after 0.1 seconds.\n✔ Test run with 9 tests in 1 suite passed after 0.1 seconds."
        paths = ["/redirect", "/cookie", "/echo", "/raw", "/disconnect", "/slow",
                 "/declared-large", "/chunked-large", "/cancel", "/v1/sys/internal/ui/mounts/kv-a",
                 "/v1/sys/internal/ui/mounts/kv-b", "/v1/kv-a/auth/uat-swim", "/v1/kv-b/data/auth/qat-other",
                 "/v1/kv-b/data/auth/deleted", "/v1/kv-b/data/auth/destroyed"] + [f"/echo-id/{n}" for n in range(40)]
        records = [{"path":p,"method":"GET","cookiePresent":False,"tokenPresent":True} for p in paths]
        return records, output, inventory

    def test_http_suite_without_whole_run_completion_is_never_pass(self):
        records, output, inventory = self.fixture()
        output = output.rsplit("\n", 1)[0]
        with self.assertRaises(RuntimeError): network.validate_evidence(records, output, inventory)

    def test_missing_frontend_test_cannot_hide_behind_complete_http_suite(self):
        records, output, inventory = self.fixture()
        inventory += "\nCompareTests.VaultViewportTests/nativeBindingsMustComplete()"
        output = output.replace("with 9 tests in 1 suite", "with 10 tests in 2 suites")
        with self.assertRaises(RuntimeError): network.validate_evidence(records, output, inventory)

    def test_false_whole_run_count_is_rejected_even_when_http_suite_passes(self):
        records, output, inventory = self.fixture()
        output = output.replace("with 9 tests", "with 8 tests")
        with self.assertRaises(RuntimeError): network.validate_evidence(records, output, inventory)

    def test_complete_evidence_measures_counts(self):
        records, output, inventory = self.fixture()
        result = network.validate_evidence(records,output,inventory)
        self.assertEqual(len(result["httpTestsPassed"]),len(network.http_test_inventory(inventory)))
        self.assertEqual(result["redirectSinkRequests"],0)
        self.assertEqual(result["cookieRequests"],0)
        self.assertEqual(result["swiftTestsPassed"], 9)
        self.assertEqual(result["swiftSuitesPassed"], 1)

    def test_root_tests_and_same_named_methods_require_independent_completion(self):
        records, output, inventory = self.fixture()
        inventory += "\nCompareTests.discoveredTest0()\nCompareTests.OtherSuite/discoveredTest0()"
        extra = ("◇ Test discoveredTest0() started.\n✔ Test discoveredTest0() passed after 0.1 seconds.\n"
                 "◇ Suite OtherSuite started.\n◇ Test discoveredTest0() started.\n"
                 "✔ Test discoveredTest0() passed after 0.1 seconds.\n✔ Suite OtherSuite passed after 0.1 seconds.\n")
        output = output.replace("✔ Test run with 9 tests in 1 suite", extra + "✔ Test run with 11 tests in 2 suites")
        self.assertEqual(network.validate_evidence(records, output, inventory)["swiftTestsPassed"], 11)
        for broken in [output.replace(extra, ""), output.replace("✔ Suite OtherSuite passed after 0.1 seconds.\n", ""),
                       output.replace("✔ Test discoveredTest0() passed", "↷ Test discoveredTest0() skipped")]:
            with self.assertRaises(RuntimeError): network.validate_evidence(records, broken, inventory)

    def test_duplicate_completion_or_events_after_footer_are_rejected(self):
        records, output, inventory = self.fixture()
        for broken in [output + "\n" + output, output + "\n✔ Test discoveredTest0() passed after 0.1 seconds.",
                       output.replace("◇ Test discoveredTest1() started.", "◇ Test discoveredTest0() started.")]:
            with self.assertRaises(RuntimeError): network.validate_evidence(records, broken, inventory)

    def test_passed_duration_cannot_hide_known_issues_or_warnings(self):
        records, output, inventory = self.fixture()
        for suffix in [" with 1 known issue", " with 1 warning"]:
            for target in ["✔ Test discoveredTest0() passed after 0.01 seconds.",
                           "✔ Suite HTTPTransportIntegration passed after 0.1 seconds.",
                           "✔ Test run with 9 tests in 1 suite passed after 0.1 seconds."]:
                damaged = output.replace(target, target[:-1] + suffix + ".")
                with self.subTest(target=target, suffix=suffix):
                    with self.assertRaises(RuntimeError): network.validate_evidence(records, damaged, inventory)

    def test_invalid_duration_is_not_a_successful_completion(self):
        records, output, inventory = self.fixture()
        for duration in ["nan", "infinity", "-1", "1.2.3", "unverified"]:
            damaged = output.replace("after 0.01 seconds", "after " + duration + " seconds")
            with self.subTest(duration=duration):
                with self.assertRaises(RuntimeError): network.validate_evidence(records, damaged, inventory)

    def test_known_issue_event_after_an_ordinary_success_is_rejected(self):
        records, output, inventory = self.fixture()
        output += "\n━ Test unexpected() recorded a known issue: synthetic probe."
        with self.assertRaises(RuntimeError): network.validate_evidence(records, output, inventory)

    def test_empty_wire_evidence_is_never_pass(self):
        _, output, inventory = self.fixture()
        with self.assertRaises(RuntimeError): network.validate_evidence([],output,inventory)

    def test_skipped_or_missing_http_suite_is_never_pass(self):
        records, output, inventory = self.fixture()
        for broken in ["",output.splitlines()[0],output.replace(" passed "," skipped ")]:
            with self.assertRaises(RuntimeError): network.validate_evidence(records,broken,inventory)

    def test_missing_concurrent_request_is_never_pass(self):
        records, output, inventory = self.fixture()
        with self.assertRaises(RuntimeError): network.validate_evidence(records[:-1],output,inventory)

    def test_redirect_cookie_and_mutation_are_rejected(self):
        records, output, inventory = self.fixture()
        sink=dict(records[0],path="/sink")
        with self.assertRaises(RuntimeError): network.validate_evidence(records+[sink],output,inventory)
        for field,value in [("cookiePresent",True),("method","PUT")]:
            broken=[dict(record) for record in records];broken[0][field]=value
            with self.assertRaises(RuntimeError): network.validate_evidence(broken,output,inventory)

    def test_python_optimization_cannot_disable_network_gate(self):
        code="""import importlib.util,sys
s=importlib.util.spec_from_file_location('network_verifier',sys.argv[1]);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
try:m.validate_evidence([], '', '')
except RuntimeError:sys.exit(17)
sys.exit(0)
"""
        result=subprocess.run(["rtk","proxy",sys.executable,"-O","-c",code,str(ROOT/"scripts/check-network.py")],capture_output=True)
        self.assertEqual(result.returncode,17)

    def test_mcp_gate_has_no_optimizable_asserts_and_require_always_executes(self):
        tree=ast.parse((ROOT/"scripts/check-mcp.py").read_text())
        self.assertFalse(any(isinstance(n,ast.Assert) for n in ast.walk(tree)))
        function=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=="require")
        body=ast.unparse(function)+"\nrequire(False,'negative fixture')\n"
        result=subprocess.run(["rtk","proxy",sys.executable,"-O","-c",body],capture_output=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn(b"negative fixture",result.stderr)

    def test_new_deleted_and_changed_sources_change_candidate_manifest(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=pathlib.Path(temporary)
            for name in ["Cargo.toml","Cargo.lock","apps/macos/Package.swift","apps/macos/Package.resolved"]:
                path=root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text("synthetic")
            source=root/"crates/core/src/lib.rs";source.parent.mkdir(parents=True);source.write_text("before")
            initial=local.source_manifest(root)
            added=source.with_name("new.rs");added.write_text("new")
            self.assertNotEqual(initial,local.source_manifest(root))
            added.unlink();self.assertEqual(initial,local.source_manifest(root))
            source.write_text("after");self.assertNotEqual(initial,local.source_manifest(root))
            source.unlink();self.assertNotEqual(initial,local.source_manifest(root))
            vendored=root/"vendor/parser/src/lib.rs";vendored.parent.mkdir(parents=True);vendored.write_text("upstream")
            before=local.source_manifest(root)
            vendored.write_text("patched");self.assertNotEqual(before,local.source_manifest(root))
            vendored.unlink();self.assertNotEqual(before,local.source_manifest(root))

    def test_evidence_verifiers_do_not_use_optimizable_asserts(self):
        for name in ["check-network.py","check-mcp.py","check-js-oracle.py","check-depth-guards.py","check-oxc-vendor.py","check-reports.py","verify-local.py"]:
            tree=ast.parse((ROOT/"scripts"/name).read_text())
            self.assertFalse(any(isinstance(node,ast.Assert) for node in ast.walk(tree)),name)

    def test_new_runtime_discovered_test_cannot_be_silently_omitted(self):
        records, output, inventory = self.fixture()
        added="attributedAndMultilineTest"
        inventory += f"\nCompareTests.HTTPTransportIntegration/{added}()"
        with self.assertRaises(RuntimeError): network.validate_evidence(records,output,inventory)
        output=output.replace("✔ Suite HTTPTransportIntegration passed",f"◇ Test {added}() started.\n✔ Test {added}() passed after 0.1 seconds.\n✔ Suite HTTPTransportIntegration passed").replace("with 9 tests", "with 10 tests")
        measured=network.validate_evidence(records,output,inventory)
        self.assertIn(added,measured["httpTestsPassed"])

    def test_empty_or_ambiguous_runtime_inventory_is_rejected(self):
        records, output, inventory = self.fixture()
        for broken in ["",inventory+"\n"+inventory.splitlines()[0],inventory+"\nCompareTests.HTTPTransportIntegration/overloaded(_:)"]:
            with self.assertRaises(RuntimeError): network.validate_evidence(records,output,broken)

    def test_mixed_vault_read_wire_evidence_cannot_be_silently_omitted(self):
        records, output, inventory = self.fixture()
        for missing in ["/v1/sys/internal/ui/mounts/kv-a", "/v1/sys/internal/ui/mounts/kv-b", "/v1/kv-a/auth/uat-swim", "/v1/kv-b/data/auth/qat-other", "/v1/kv-b/data/auth/deleted", "/v1/kv-b/data/auth/destroyed"]:
            with self.assertRaises(RuntimeError):
                network.validate_evidence([record for record in records if record["path"] != missing], output, inventory)

    def test_same_named_method_in_another_suite_does_not_prove_http_test_passed(self):
        records, output, inventory = self.fixture()
        line="✔ Test discoveredTest0() passed after 0.01 seconds."
        output=output.replace(line,"")+"\n◇ Suite OtherSuite started.\n"+line+"\n✔ Suite OtherSuite passed after 0.1 seconds."
        with self.assertRaises(RuntimeError): network.validate_evidence(records,output,inventory)


if __name__ == "__main__":
    unittest.main()
