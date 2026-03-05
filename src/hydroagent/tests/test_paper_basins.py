"""Test that paper preset basins can be loaded from CAMELS-US data.

Skips gracefully if data is not available locally.

Run:  python -m pytest src/hydroagent/tests/test_paper_basins.py -v
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

from hydroagent.data_loading import load_camels_basin

# Import the preset directly
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..')))

PAPER_BASINS = [
    '01022500', '01547700', '02064000', '03015500', '01169000', '04056500',
    '11264500', '06623800', '07083000',
    '10259200', '09447800', '08271000',
    '02177000', '05393500', '06452000',
    '12010000', '10348850', '13313000',
]


class TestPaperBasinsLoad(unittest.TestCase):
    """Verify each paper preset basin can be loaded."""

    @classmethod
    def setUpClass(cls):
        # Quick check: try loading one basin to see if data exists at all
        try:
            load_camels_basin('01022500')
            cls.data_available = True
        except Exception:
            cls.data_available = False

    def test_paper_preset_has_18_basins(self):
        self.assertEqual(len(PAPER_BASINS), 18)

    def test_all_gauge_ids_are_8_digits(self):
        for bid in PAPER_BASINS:
            self.assertEqual(len(bid), 8, f"Basin {bid} is not 8 digits")
            self.assertTrue(bid.isdigit(), f"Basin {bid} is not all digits")

    def test_load_each_basin(self):
        if not self.data_available:
            self.skipTest('CAMELS-US data not available locally')
        failed = []
        for bid in PAPER_BASINS:
            try:
                forcing, obs, area = load_camels_basin(bid)
                self.assertGreater(len(forcing), 100,
                                   f"Basin {bid}: too few forcing records ({len(forcing)})")
                self.assertGreater(area, 0, f"Basin {bid}: area <= 0")
            except Exception as e:
                failed.append(f"{bid}: {e}")
        if failed:
            self.fail(f"Failed to load {len(failed)} basins:\n" + "\n".join(failed))


if __name__ == '__main__':
    unittest.main()
