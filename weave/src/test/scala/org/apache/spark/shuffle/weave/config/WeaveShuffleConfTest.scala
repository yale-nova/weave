package org.apache.spark.shuffle.weave.config

import org.scalatest.funsuite.AnyFunSuite
import org.apache.spark.SparkConf

class WeaveShuffleConfTest extends AnyFunSuite {

  test("WeaveShuffleConf loads all provided values correctly") {
    val sparkConf = new SparkConf()
      .set("spark.weave.c", "2")
      .set("spark.weave.alpha", "0.02")
      .set("spark.weave.delta", "0.01")
      .set("spark.weave.beta", "0.2")
      .set("spark.weave.randomShuffle", "Hierarchical")
      .set("spark.weave.histogram", "DirectCount")
      .set("spark.weave.balancedShuffle", "SimpleGreedyBinPacking")
      .set("spark.weave.balancedShuffleOrder", "hashcode")
      .set("spark.weave.fakePadding", "RepeatReal")
      .set("spark.weave.shuffleMode", "TaggedBatch")
      .set("spark.weave.globalSeed", "1234")
      .set("spark.weave.batchSize", "200")
      .set("spark.weave.numWeavers", "128")
      .set("spark.weave.bufferSize", (8 * 1024 * 1024).toString) // 8MB
      .set("spark.weave.enableProfiling", "false")

    val conf = WeaveShuffleConf.fromSparkConf(sparkConf)

    assert(conf.c == 2)
    assert(conf.alpha == 0.02)
    assert(conf.delta == 0.01)
    assert(conf.beta == 0.2)
    assert(conf.randomShuffleStrategy == "Hierarchical")
    assert(conf.histogramStrategy == "DirectCount")
    assert(conf.balancedShuffleStrategy == "SimpleGreedyBinPacking")
    assert(conf.fakePaddingStrategy == "RepeatReal")
    assert(conf.shuffleMode == "TaggedBatch")
    assert(conf.globalSeed == 1234L)
    assert(conf.batchSize == 200)
    assert(conf.numWeavers == 128)
    assert(conf.bufferSize == 8 * 1024 * 1024)
    assert(!conf.enableProfiling)
  }

  test("WeaveShuffleConf falls back to default values when missing") {
    val sparkConf = new SparkConf()

    val conf = WeaveShuffleConf.fromSparkConf(sparkConf)

    assert(conf.c == 1)
    assert(conf.alpha == 0.01)
    assert(conf.delta == 0.05)
    assert(conf.beta == 0.1)
    assert(conf.randomShuffleStrategy == "PRG")
    assert(conf.histogramStrategy == "DirectCount")
    assert(conf.balancedShuffleStrategy == "SimpleGreedyBinPacking")
    assert(conf.fakePaddingStrategy == "RepeatReal")
    assert(conf.shuffleMode == "TaggedBatch")
    assert(conf.globalSeed == 1337L)
    assert(conf.batchSize == 100)
    assert(conf.numWeavers == 64)
    assert(conf.bufferSize == 4 * 1024 * 1024)
    assert(conf.enableProfiling)
  }
}
