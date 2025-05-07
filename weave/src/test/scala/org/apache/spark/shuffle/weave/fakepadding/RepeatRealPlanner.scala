package org.apache.spark.shuffle.weave.fakepadding

import org.scalatest.funsuite.AnyFunSuite

class RepeatRealPlannerTest extends AnyFunSuite {

  test("binomial draws yield fewer than or equal to total planned fakes") {
  val planner = new RepeatRealPlanner(alpha = 1.0, beta = 0.2, numBins = 4, seed = 42L)

  // r_i deliberately small so f_i is large
  val realCounts = Array(10, 10, 10, 10)
  val d = 100.0

  val fake = planner.computeFakeCounts(realCounts, d)

  // Ideal: Binomial draws yield less than total f_i
  val totalPlanned = Array.fill(4) {
    val f = (1 + 0.2) * ((2 * 4 - 1) / 4.0 * d - 10 / 1.0)
    f.toInt
  }.sum

  assert(fake.sum < totalPlanned, s"Draws should not equal total fakes: got ${fake.sum} vs $totalPlanned")
}
  

  test("adds fake records when real is far below ideal") {
    val planner = new RepeatRealPlanner(alpha = 1.0, beta = 0.1, numBins = 2, seed = 42L)
    val real = Array(10, 5)
    val d = 100.0
    val fake = planner.computeFakeCounts(real, d)
    assert(fake.sum > 50, s"Expected lots of fake records, got ${fake.mkString(",")}")
  }

  test("fake counts are deterministic with same seed") {
    val planner1 = new RepeatRealPlanner(1.0, 0.1, 2, 123L)
    val planner2 = new RepeatRealPlanner(1.0, 0.1, 2, 123L)
    val r = Array(20, 30)
    val d = 100.0
    assert(planner1.computeFakeCounts(r, d).sameElements(planner2.computeFakeCounts(r, d)))
  }
}
