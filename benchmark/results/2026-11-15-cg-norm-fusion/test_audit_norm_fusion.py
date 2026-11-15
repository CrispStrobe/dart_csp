"""Meaningful rule-boundary tests using synthetic per-process-pair summaries.

No solver, compiler, benchmark or archived timing audit is executed.
"""
import copy
import importlib.util
import itertools
import math
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('norm_audit_rules',Path(__file__).with_name('audit_norm_fusion.py'))
audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)


def pairs(values, p95=None):
    p95 = p95 or [1.0]*4
    return [{'round':i+1,'first':'before' if i%2==0 else 'after',
             'p50_ratio':value,'p95_ratio':p95[i]} for i,value in enumerate(values)]


def passing_input():
    keys=itertools.product(audit.FIXTURES,audit.ENGINES,audit.MODES)
    candidate={key:pairs([1.0]*4) for key in keys}
    aa=copy.deepcopy(candidate)
    candidate[audit.PRIMARY]=pairs([.93,.94,.94,.93])
    return candidate,aa


def failures(candidate,aa):
    return audit.decide(candidate,aa)['failed_gates']


class DecisionBoundaryTests(unittest.TestCase):
    def test_clean_predeclared_success(self):
        c,a=passing_input();result=audit.decide(c,a)
        self.assertTrue(result['passed'])
        self.assertEqual(result['recommendation'],'retain')
        self.assertFalse(result['failed_gates'])

    def test_exact_five_percent_primary_boundary_is_inclusive(self):
        c,a=passing_input();c[audit.PRIMARY]=pairs([.95]*4)
        self.assertTrue(audit.decide(c,a)['passed'])
        c[audit.PRIMARY]=pairs([.95000001]*4)
        self.assertEqual(failures(c,a),['primary_p50_improvement'])

    def test_both_order_strata_must_improve(self):
        c,a=passing_input();c[audit.PRIMARY]=pairs([1.0,.8,1.0,.8])
        self.assertIn('primary_improves_in_both_orders',failures(c,a))

    def test_two_improving_pairs_do_not_suffice_even_with_good_medians(self):
        c,a=passing_input();c[audit.PRIMARY]=pairs([.8,1.05,1.05,.8])
        self.assertEqual(failures(c,a),['primary_three_improving_pairs'])

    def test_aa_median_bounds_are_inclusive(self):
        for ratio in (.95,1.05):
            with self.subTest(ratio=ratio):
                c,a=passing_input();a[audit.PRIMARY]=pairs([ratio]*4)
                self.assertTrue(audit.decide(c,a)['passed'])
        for ratio in (.94999,1.05001):
            with self.subTest(ratio=ratio):
                c,a=passing_input();a[audit.PRIMARY]=pairs([ratio]*4)
                self.assertIn('aa_primary_median_stability',failures(c,a))

    def test_aa_order_bounds_are_inclusive_and_detect_cancellation(self):
        c,a=passing_input();a[audit.PRIMARY]=pairs([.9,1.1,.9,1.1])
        self.assertTrue(audit.decide(c,a)['passed'])
        a[audit.PRIMARY]=pairs([.89,1.11,.89,1.11])
        self.assertEqual(failures(c,a),['aa_primary_order_stability'])

    def test_cg_adverse_gate_strict_threshold(self):
        row=('ladder_25_components_1','dart_2d_analytic','cold')
        c,a=passing_input();c[row]=pairs([1.05]*4)
        self.assertTrue(audit.decide(c,a)['passed'])
        c[row]=pairs([1.050001]*4)
        self.assertEqual(failures(c,a),['no_repeated_adverse_p50_gate'])

    def test_cg_overall_median_alone_is_not_both_order_adverse_gate(self):
        c,a=passing_input();c[('laman_free_500','dart_2d_analytic','cold')]=pairs([1.2,.96,1.2,.96])
        self.assertTrue(audit.decide(c,a)['passed'])

    def test_untouched_control_uses_ten_percent_strict_boundary(self):
        row=('axis_rectangle','dart_2d_analytic','cold')
        c,a=passing_input();c[row]=pairs([1.10]*4)
        self.assertTrue(audit.decide(c,a)['passed'])
        c[row]=pairs([1.100001]*4)
        self.assertEqual(failures(c,a),['no_repeated_adverse_p50_gate'])

    def test_control_noise_cannot_excuse_candidate_adversity(self):
        row=('ladder_25_components_1','dart_2d_analytic','cold')
        c,a=passing_input();c[row]=pairs([1.08]*4);a[row]=pairs([1.8,.3,1.9,.2])
        self.assertIn('no_repeated_adverse_p50_gate',failures(c,a))

    def test_target_tail_exact_boundary_does_not_reject(self):
        c,a=passing_input();c[audit.PRIMARY]=pairs([.94]*4,[1.25]*4)
        self.assertTrue(audit.decide(c,a)['passed'])

    def test_three_target_tail_regressions_spanning_orders_reject(self):
        c,a=passing_input();c[audit.PRIMARY]=pairs([.94]*4,[1.25001,1.25001,1.25001,1.0])
        self.assertEqual(failures(c,a),['no_repeated_target_tail_gate'])

    def test_two_tail_regressions_are_reported_but_do_not_trigger_three_round_gate(self):
        c,a=passing_input();c[audit.PRIMARY]=pairs([.94]*4,[1.4,1.0,1.4,1.0])
        self.assertTrue(audit.decide(c,a)['passed'])

    def test_control_tails_are_not_misclassified_as_target_gate(self):
        c,a=passing_input();c[('axis_rectangle','dart_3d_ad','warm')]=pairs([1.0]*4,[1.8]*4)
        self.assertTrue(audit.decide(c,a)['passed'])

    def test_missing_or_extra_case_rejected(self):
        c,a=passing_input();c.pop(('axis_rectangle','dart_2d_analytic','cold'))
        with self.assertRaisesRegex(ValueError,'matrix'):audit.decide(c,a)
        c,a=passing_input();a[('new_fixture','dart_2d_analytic','cold')]=pairs([1.0]*4)
        with self.assertRaisesRegex(ValueError,'matrix'):audit.decide(c,a)

    def test_missing_duplicate_or_unbalanced_rounds_rejected(self):
        c,a=passing_input();c[audit.PRIMARY]=c[audit.PRIMARY][:3]
        with self.assertRaisesRegex(ValueError,'four distinct'):audit.decide(c,a)
        c,a=passing_input();c[audit.PRIMARY][0]['round']=2
        with self.assertRaisesRegex(ValueError,'four distinct'):audit.decide(c,a)
        c,a=passing_input();c[audit.PRIMARY][1]['first']='before'
        with self.assertRaisesRegex(ValueError,'two pairs'):audit.decide(c,a)

    def test_nonfinite_zero_negative_or_missing_ratio_rejected(self):
        for value in (math.nan,math.inf,0.0,-.1,None,True):
            with self.subTest(value=value):
                c,a=passing_input();c[audit.PRIMARY][0]['p50_ratio']=value
                with self.assertRaisesRegex(ValueError,'finite and strictly positive'):audit.decide(c,a)


if __name__=='__main__':
    unittest.main()
