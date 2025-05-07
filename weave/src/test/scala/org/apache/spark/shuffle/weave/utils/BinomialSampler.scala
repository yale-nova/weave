package org.apache.spark.shuffle.weave.utils

import org.scalatest.funsuite.AnyFunSuite

class BinomialSamplerTest extends AnyFunSuite {

  test("returns 0 when trials = 0") {
    val sampler = new BinomialSampler(seed = 42L)
    assert(sampler.sample(0, 0.5) == 0)
  }

  test("returns exactly trials when p = 1") {
    val sampler = new BinomialSampler(seed = 42L)
    assert(sampler.sample(100, 1.0) == 100)
  }

  test("is deterministic with same seed") {
    val s1 = new BinomialSampler(1337L)
    val s2 = new BinomialSampler(1337L)
    val results1 = (1 to 5).map(_ => s1.sample(100, 0.5))
    val results2 = (1 to 5).map(_ => s2.sample(100, 0.5))
    assert(results1 == results2)
  }
}
