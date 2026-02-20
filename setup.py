from pathlib import Path

from setuptools import setup

def _load_requirements(path: Path):
    reqs = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith(("-", "--")):
            # Skip include/index directives; install_requires should contain package specs only.
            continue
        reqs.append(line)
    return reqs

# read the description from the README.md
readme_file = Path(__file__).absolute().parent / "README.md"
with readme_file.open("r", encoding="utf-8") as fp:
    long_description = fp.read()
install_requires = _load_requirements(Path(__file__).absolute().parent / "requirements.txt") + ["torch"]

about = {}
with open("neuralhydrology/__about__.py", "r", encoding="utf-8") as fp:
    exec(fp.read(), about)

setup(name='neuralhydrology',
      version=about["__version__"],
      packages=[
          'neuralhydrology', 'neuralhydrology.datasetzoo', 'neuralhydrology.datautils', 'neuralhydrology.utils',
          'neuralhydrology.modelzoo', 'neuralhydrology.training', 'neuralhydrology.evaluation'
      ],
      url='https://neuralhydrology.readthedocs.io',
      project_urls={
          'Documentation': 'https://neuralhydrology.readthedocs.io',
          'Source': 'https://github.com/neuralhydrology/neuralhydrology',
          'Research Blog': 'https://neuralhydrology.github.io/'
      },
      author='Frederik Kratzert, Daniel Klotz, Martin Gauch',
      author_email='neuralhydrology@googlegroups.com',
      description='Library for training deep learning models with environmental focus',
      long_description=long_description,
      long_description_content_type='text/markdown',
      entry_points={
          'console_scripts': [
              'nh-schedule-runs=neuralhydrology.nh_run_scheduler:_main', 'nh-run=neuralhydrology.nh_run:_main',
              'nh-results-ensemble=neuralhydrology.utils.nh_results_ensemble:_main'
          ]
      },
      python_requires='>=3.8',
      install_requires=install_requires,
      classifiers=[
          'Programming Language :: Python :: 3',
          'Operating System :: OS Independent',
          'Topic :: Scientific/Engineering :: Artificial Intelligence',
          'Topic :: Scientific/Engineering :: Hydrology',
          'License :: OSI Approved :: BSD License',
      ],
      keywords='deep learning hydrology lstm neural network streamflow discharge rainfall-runoff')
