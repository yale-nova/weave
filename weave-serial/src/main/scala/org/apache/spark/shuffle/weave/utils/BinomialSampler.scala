package org.apache.spark.shuffle.weave.utils

import org.apache.commons.math3.distribution.BinomialDistribution
import org.apache.commons.math3.random.JDKRandomGenerator

class BinomialSampler(seed: Long, mode: String = "exact") {
  private val rng = new scala.util.Random(seed)

  // Apache Commons Math RNG
  private val libraryRng = new JDKRandomGenerator()
  libraryRng.setSeed(seed)

  private var distOpt: Option[BinomialDistribution] = None

  def sample(n: Int, p: Double): Int = {
    if (n <= 0 || p <= 0.0) return 0
    if (p >= 1.0) return n

    mode match {
      case "exact" =>
        var count = 0
        for (_ <- 0 until n) {
          if (rng.nextDouble() < p) count += 1
        }
        count

      case "normal" | "fast" =>
        val mean = n * p
        val stddev = math.sqrt(n * p * (1 - p))
        val result = (mean + rng.nextGaussian() * stddev).round.toInt
        result.max(0).min(n)

      case "library" =>
        val dist = distOpt match {
          case Some(d) if d.getNumberOfTrials == n && d.getProbabilityOfSuccess == p => d
          case _ =>
            val newDist = new BinomialDistribution(libraryRng, n, p)
            distOpt = Some(newDist)
            newDist
        }
        dist.sample()

      case unknown =>
        throw new IllegalArgumentException(s"Unknown binomial mode: $unknown")
    }
  }
}
