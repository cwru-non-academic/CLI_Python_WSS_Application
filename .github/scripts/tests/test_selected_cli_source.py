import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
p = Path(__file__).resolve().parents[1] / 'invoke_selected_cli_tests.py'
s = importlib.util.spec_from_file_location('selected_cli', p)
m = importlib.util.module_from_spec(s)
s.loader.exec_module(m)
class BindingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='wss-cli-test-binding-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        (self.root/'conformance').mkdir()
        (self.root/'conformance/test_modeled_commands.py').write_text('# fixture\n')
        self.contract = {'schema':'wss-python-cli-tests/v1','test_files':['test_modeled_commands.py']}
        self.write_contract(); self.git('init','--quiet'); self.commit()
        self.product = self.root.parent/'different-product'
    def git(self,*args):
        return subprocess.check_output(['git','-C',str(self.root),'-c','user.name=Test','-c','user.email=test@example.invalid',*args],text=True).strip()
    def write_contract(self): (self.root/'conformance/test-contract.json').write_text(json.dumps(self.contract))
    def commit(self):
        self.git('add','.'); self.git('commit','--quiet','-m','fixture'); self.sha=self.git('rev-parse','HEAD')
    def resolve(self,**kwargs):
        a=dict(root=self.root,sha=self.sha,repository=m.REPOSITORY,selection='a'*64,product=self.product); a.update(kwargs)
        return m.resolve_tests(**a)
    def test_distinct(self): m.recheck_tests(self.resolve(),self.product)
    def test_bad_sha(self):
        with self.assertRaises(ValueError): self.resolve(sha='f'*40)
    def test_bad_repo(self):
        with self.assertRaises(ValueError): self.resolve(repository='other/repo')
    def test_bad_selection(self):
        with self.assertRaises(ValueError): self.resolve(selection='latest')
    def test_same_root(self):
        with self.assertRaises(ValueError): self.resolve(product=self.root)
    def test_nested(self):
        with self.assertRaises(ValueError): self.resolve(root=self.root/'conformance')
    def test_changed(self):
        a=self.resolve(); (self.root/'conformance/test_modeled_commands.py').write_text('changed')
        with self.assertRaises(ValueError): m.recheck_tests(a,self.product)
    def test_untracked(self):
        (self.root/'conformance/test_extra.py').write_text('# extra')
        with self.assertRaises(ValueError): self.resolve()
    def test_ignored(self):
        (self.root/'.git/info/exclude').write_text('conformance/test_extra.py\n')
        (self.root/'conformance/test_extra.py').write_text('# ignored')
        with self.assertRaises(ValueError): self.resolve()
    def test_product_flag(self):
        self.contract['baseline_ready']=True; self.write_contract(); self.commit()
        with self.assertRaises(ValueError): self.resolve()
    def test_escape(self):
        self.contract['test_files'].append('../src/other.py'); self.write_contract(); self.commit()
        with self.assertRaises(ValueError): self.resolve()
    def test_missing_matrix(self):
        self.contract['test_files']=['test_other.py']; self.write_contract(); self.commit()
        with self.assertRaises(ValueError): self.resolve()
    def test_ignored_unchecked_hash_bytecode(self):
        import py_compile
        (self.root/'src').mkdir()
        source=self.root/'src/probe.py'
        source.write_text('value=1\n')
        (self.root/'.gitignore').write_text('__pycache__/\n*.pyc\n')
        self.commit()
        py_compile.compile(str(source),doraise=True,invalidation_mode=py_compile.PycInvalidationMode.UNCHECKED_HASH)
        with self.assertRaises(ValueError): m.checkout(self.root,self.sha,('src',))
    def test_assume_unchanged(self):
        self.git('update-index','--assume-unchanged','conformance/test_modeled_commands.py')
        with self.assertRaises(ValueError): self.resolve()
    def test_skip_worktree(self):
        self.git('update-index','--skip-worktree','conformance/test_modeled_commands.py')
        with self.assertRaises(ValueError): self.resolve()
class ExecutionCompletenessTests(unittest.TestCase):
    def test_complete_inventory(self):
        tests = [unittest.FunctionTestCase(lambda: None) for _ in range(2)]
        self.assertEqual(m.run_selected_suite(tests).testsRun, 2)

    def test_successful_early_stop_is_rejected(self):
        class StopAfterSuccess(unittest.FunctionTestCase):
            def run(self, result=None):
                super().run(result)
                result.stop()
                return result
        def inventory():
            return [StopAfterSuccess(lambda: None), unittest.FunctionTestCase(lambda: None)]
        incomplete = unittest.TestResult()
        unittest.TestSuite(inventory()).run(incomplete)
        self.assertTrue(incomplete.wasSuccessful())
        self.assertEqual(incomplete.skipped, [])
        self.assertEqual(incomplete.testsRun, 1)
        with self.assertRaisesRegex(ValueError, 'discovered inventory'):
            m.run_selected_suite(inventory())

class StandaloneSourceTupleTests(unittest.TestCase):
    def sources(self):
        from pathlib import Path
        root=Path(__file__).resolve().parents[3]
        return ((root/'.github/workflows/standalone-selected-runtime.yml').read_text(),
                (root/'.github/scripts/Invoke-StandalonePythonCliProof.ps1').read_text())

    def validate(self, workflow, runner):
        import re
        expected={'CLI_SOURCE':'628647e111c4b9976d28ff97e537abed0b8b0200','TEST_SOURCE':'76680d8c0698f1a028fa214d95bd8dc6d9098bc6','WRAPPER_SOURCE':'9c375d7d39b7fe212483112effcdcdd5b61cf381'}
        for name, sha in expected.items():
            self.assertEqual(re.findall(r'^  '+name+r': ([a-f0-9]{40})$',workflow,re.M),[sha])
        self.assertIn('ref: ${{ env.TEST_SOURCE }}\n          path: selected-tests',workflow)
        self.assertIn("$cliSha='628647e111c4b9976d28ff97e537abed0b8b0200'",runner)
        self.assertIn("$testSha='76680d8c0698f1a028fa214d95bd8dc6d9098bc6'",runner)
        self.assertIn("$wrapperSha='9c375d7d39b7fe212483112effcdcdd5b61cf381'",runner)
        self.assertIn("'--test-sha',$testSha",runner)
        self.assertNotIn("'--test-sha',$cliSha",runner)
        self.assertEqual(workflow.count('ref: 1f3d691d2a5ecbd7aaaf46b1deb8955acd078d3a'),2)
        self.assertIn('Get-OrdinaryPythonToolsSha $cli $cliSha',runner)
        self.assertIn('Assert-OrdinaryPythonToolsCheckout $tools $toolsSha',runner)

    def test_separate_frozen_product_test_and_tool_sources(self):
        self.validate(*self.sources())

    def test_coupled_or_wrong_source_tuple_rejected(self):
        workflow,runner=self.sources()
        for bad_workflow,bad_runner in [
            (workflow.replace('TEST_SOURCE: 76680d8c0698f1a028fa214d95bd8dc6d9098bc6','TEST_SOURCE: 628647e111c4b9976d28ff97e537abed0b8b0200'),runner),
            (workflow.replace('CLI_SOURCE: 628647e111c4b9976d28ff97e537abed0b8b0200','CLI_SOURCE: 76680d8c0698f1a028fa214d95bd8dc6d9098bc6'),runner),
            (workflow,runner.replace("'--test-sha',$testSha","'--test-sha',$cliSha")),
            (workflow,runner.replace('Assert-OrdinaryPythonToolsCheckout $tools $toolsSha','# omitted')) ,
            (workflow,runner.replace('Get-OrdinaryPythonToolsSha $cli $cliSha',"'1f3d691d2a5ecbd7aaaf46b1deb8955acd078d3a'")),
            (workflow.replace('ref: 1f3d691d2a5ecbd7aaaf46b1deb8955acd078d3a','ref: dev'),runner)]:
            with self.assertRaises(AssertionError): self.validate(bad_workflow,bad_runner)

if __name__=='__main__': unittest.main()