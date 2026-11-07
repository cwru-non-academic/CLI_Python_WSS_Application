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

if __name__=='__main__': unittest.main()