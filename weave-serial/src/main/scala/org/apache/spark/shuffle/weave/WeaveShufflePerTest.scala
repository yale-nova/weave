package org.apache.spark.shuffle.weave

import org.apache.spark.shuffle.weave.config.WeaveShuffleConf
import org.apache.spark.sql.{SparkSession}
import org.apache.spark.{SparkConf}
import org.apache.log4j.{Level, Logger}

import scala.util.Random

object WeaveShufflePerfTest {

  def main(args: Array[String]): Unit = {
    Logger.getLogger("org").setLevel(Level.ERROR)
    Logger.getLogger("akka").setLevel(Level.ERROR)

    val sparkConf = new SparkConf()
      .setMaster("local[4]")
      .setAppName("WeaveShufflePerfTest")
      .set("spark.weave.fakePadding", "non-associative") // Non-associative
      .set("spark.weave.alpha", "0.05")
      .set("spark.weave.numWeavers", "10")

    val spark = SparkSession.builder().config(sparkConf).getOrCreate()
    val conf = WeaveShuffleConf.fromSparkConf(sparkConf)

    val numRecords = 1000000
    val numKeys = 200

    // Generate 1M records with mild skew across 200 keys
    val keys = (1 to numKeys).map(i => f"key$i%03d")
    val input = (0 until numRecords).map { i =>
      val k = keys(Random.nextInt(keys.length))
      (k, 1)
    }

    val inputRDD = spark.sparkContext.parallelize(Random.shuffle(input), 10).persist()
    inputRDD.count() // force materialization

    val job = new WeaveShuffleJobSerialized(conf)

    val t0 = System.nanoTime()
    val result = job.runStepByStep[String, Int](
      inputRDD,
      spark,
      _ + _,
      0
    )
    val t1 = System.nanoTime()

    println(f"⏱️ Weave shuffle completed: ${result.size} keys in ${(t1 - t0) / 1e9}%.2f seconds")

    spark.stop()
  }
}
