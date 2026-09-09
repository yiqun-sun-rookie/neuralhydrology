"""Standard-library-only evaluator source boundary; execute this file as source.

Controller launchers hash this file against their externally pinned code manifest,
compile those same bytes, then call install before any family module import.
"""
import hashlib
import importlib.abc
import importlib.machinery
import importlib.util
from pathlib import Path
import stat
import sys


def _check(condition, message):
    if not condition:
        raise ValueError(message)


def _file(root, relative):
    _check(isinstance(relative, str) and relative.endswith('.py') and '\\' not in relative
           and ':' not in relative and all(p not in ('', '.', '..') for p in relative.split('/')),
           'Invalid evaluator source identity')
    path = root / relative
    for item in (path, *path.parents):
        _check(not item.is_symlink(), 'Symlink evaluator source')
        if item.exists():
            _check(not (getattr(item.lstat(), 'st_file_attributes', 0)
                        & getattr(stat, 'FILE_ATTRIBUTE_REPARSE_POINT', 0x400)), 'Reparse evaluator source')
    _check(path.is_file() and path.resolve().is_relative_to(root), 'Missing/outside evaluator source')
    return path


class _Source(importlib.machinery.SourceFileLoader):
    def __init__(self, fullname, path, boundary, relative):
        super().__init__(fullname, str(path))
        self.boundary, self.relative = boundary, relative

    def get_code(self, fullname):
        data = _file(self.boundary.root, self.relative).read_bytes()
        sha = hashlib.sha256(data).hexdigest()
        _check(sha == self.boundary.expected[self.relative], 'Evaluator source changed before import')
        self.boundary.executed[fullname] = sha
        return compile(data, self.path, 'exec', dont_inherit=True)


class EvaluatorSources(importlib.abc.MetaPathFinder):
    _family_evaluator_boundary = True

    def __init__(self, family, expected):
        root = Path(family)
        _check(root.is_absolute() and '..' not in root.parts and not root.is_symlink(), 'Invalid evaluator family')
        self.root, self.expected, self.executed = root.resolve(), dict(expected), {}
        _check(self.expected, 'Empty evaluator code inventory')
        self.modules = {}
        for relative, sha in self.expected.items():
            path = _file(self.root, relative)
            _check(hashlib.sha256(path.read_bytes()).hexdigest() == sha, 'Evaluator code hash mismatch')
            package = relative.endswith('/__init__.py')
            name = relative[:-12].replace('/', '.') if package else relative[:-3].replace('/', '.')
            _check(name not in self.modules and name not in sys.modules, 'Preloaded/duplicate evaluator module: ' + name)
            self.modules[name] = (relative, package)
        for name in self.modules:
            parents = name.split('.')[:-1]
            _check(all('.'.join(parents[:i]) in self.modules for i in range(1, len(parents)+1)),
                   'Evaluator package initializer missing from code lock')

    def find_spec(self, fullname, path=None, target=None):
        if fullname not in self.modules:
            _check(fullname.split('.')[0] not in {n.split('.')[0] for n in self.modules},
                   'Unregistered evaluator module: ' + fullname)
            return None
        relative, package = self.modules[fullname]
        location = _file(self.root, relative)
        loader = _Source(fullname, location, self, relative)
        return importlib.util.spec_from_file_location(fullname, location, loader=loader,
            submodule_search_locations=[str(location.parent)] if package else None)

    def verify(self, expected):
        _check(dict(expected) == self.expected, 'Evaluator execution inventory changed')
        for name, (relative, _) in self.modules.items():
            path = _file(self.root, relative)
            _check(hashlib.sha256(path.read_bytes()).hexdigest() == self.expected[relative], 'Evaluator source changed')
            if name in sys.modules:
                module = sys.modules[name]
                _check(isinstance(module.__loader__, _Source) and module.__loader__.boundary is self
                       and self.executed.get(name) == self.expected[relative]
                       and Path(module.__file__).resolve() == path, 'Unverified executed evaluator bytes: ' + name)


def install(family, expected_code):
    """Freeze one explicit evaluator inventory (including reviewed Task4c files).

    expected_code maps all relative .py paths, including package initializers,
    to externally pinned SHA-256 values. No late registration or source edits.
    """
    _check(sys.dont_write_bytecode, 'Python -B required')
    _check(not any(getattr(item, '_family_evaluator_boundary', False) for item in sys.meta_path),
           'Evaluator boundary already installed')
    boundary = EvaluatorSources(family, expected_code)
    sys.meta_path.insert(0, boundary)
    return boundary
