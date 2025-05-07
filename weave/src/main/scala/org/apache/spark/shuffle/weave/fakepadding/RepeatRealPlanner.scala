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