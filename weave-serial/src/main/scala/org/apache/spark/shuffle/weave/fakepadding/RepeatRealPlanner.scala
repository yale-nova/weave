package org.apache.spark.shuffle.weave.fakepadding

import org.apache.spark.shuffle.weave.utils.BinomialSampler
import scala.math._

class RepeatRealPlanner(
    alpha: Double,
    beta: Double,
    numBins: Int,
    seed: Long,
    binomialMode: String = "exact"
) extends FakePaddingPlanner {

  private val sampler = new BinomialSampler(seed, binomialMode)

  override def computeFakeCounts(realCounts: Array[Int], d: Double): Array[Int] = {
    require(realCounts.length == numBins, "realCounts length must match numBins")

    val fakeCounts = Array.ofDim[Int](numBins)

    for (i <- 0 until numBins) {
      val r_i = realCounts(i).toDouble
      val adjusted_r = r_i / alpha
      val ideal = ((2.0 * numBins - 1) / numBins) * d
      val f_i = max(0.0, (1 + beta) * (ideal - adjusted_r))
      fakeCounts(i) = sampler.sample(floor(f_i).toInt, 1.0 / numBins)
    }

    fakeCounts
  }
}

case class FakePlan(binToReducer: Array[Array[Int]]) // shape: [mapperBin][reducerBin]

class CentralizedRepeatRealPlanner(
    alpha: Double,
    beta: Double,
    numBins: Int,
    seed: Long,
    binomialMode: String = "exact"
) {

  private val sampler = new BinomialSampler(seed, binomialMode)

  def drawGlobalFakePlan(realCounts: Array[Int], d: Double): FakePlan = {
    require(realCounts.length == numBins, "realCounts length must match numBins")

    val plan = Array.ofDim[Int](numBins, numBins)

    for (i <- 0 until numBins) {
      val r_i = realCounts(i).toDouble
      val adjusted_r = r_i / alpha
      val ideal = ((2.0 * numBins - 1) / numBins) * d
      val f_i = max(0.0, (1 + beta) * (ideal - adjusted_r))
      val totalFake = floor(f_i).toInt

      // Randomly assign totalFake items across all bins, but ensure sum = totalFake
      val draws = Array.fill(numBins)(0)
      var remaining = totalFake

      for (j <- 0 until numBins - 1) {
        val draw = sampler.sample(remaining, 1.0 / (numBins - j))
        draws(j) = draw
        remaining -= draw
      }
      draws(numBins - 1) = remaining // whatever is left

      plan(i) = draws
    }

    FakePlan(plan)
  }
}
