import unittest
from scripts.utilities import milestone_heuristic as mh


class TestHeuristic(unittest.TestCase):

    def test_pick_single_keyword_low_confidence(self):
        # single keyword should be below default min_score=2
        res = mh.pick('deploy', [])
        self.assertIsNone(res[0])

    def test_pick_label_overrides(self):
        res = mh.pick('anything', ['area:secrets'])
        self.assertEqual(res[0], 'Secrets & Credential Management')

    def test_pick_prefers_high_score(self):
        text = 'terraform deploy canary'
        res = mh.pick(text, [])
        self.assertEqual(res[0], 'Deployment Automation & Migration')


if __name__ == '__main__':
    unittest.main()
