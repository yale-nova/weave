package org.apache.spark.shuffle.weave

import org.apache.spark.shuffle.weave.WeaveShuffleJobSerialized
import org.apache.spark.shuffle.weave.config.WeaveShuffleConf
import org.apache.spark.sql.SparkSession
import org.apache.spark.{SparkConf, SparkContext}
import org.apache.log4j.{Level, Logger}

object TestDriverSkewed {

  def main(args: Array[String]): Unit = {
    Logger.getLogger("org").setLevel(Level.ERROR)
    Logger.getLogger("akka").setLevel(Level.ERROR)
    val sparkConf = new SparkConf()
      .setMaster("local[2]")
      .setAppName("WeaveSkewedNonAssociativeTest")
      .set("spark.weave.fakePadding", "associative")
      .set("spark.weave.alpha", "1.0")
      .set("spark.weave.numWeavers", "10")

    val spark = SparkSession.builder().config(sparkConf).getOrCreate()
    
    val conf = WeaveShuffleConf.fromSparkConf(spark.sparkContext.getConf)

    // Generate 500 records skewed over 20 keys, max 90 per key
    val keys = (1 to 20).map(i => f"key$i%02d")
    val skewedCounts = Seq(
      90, 75, 60, 50, 40, 30, 25, 20, 20, 15, 15, 15, 10, 10, 10, 5, 5, 3, 2
    )
    assert(skewedCounts.sum == 500)

    val input: Seq[(String, Int)] = keys.zip(skewedCounts).flatMap {
      case (k, n) => Seq.fill(n)((k, 1))
    }

    val inputRDD = spark.sparkContext.parallelize(scala.util.Random.shuffle(input), 4)

    val job = new WeaveShuffleJobSerialized(conf)
    val result = job.runStepByStep[String, Int](
      inputRDD,
      spark,
      _ + _,
      0
    )

    println("=== Final Output ===")
    result.toSeq.sortBy(_._1).foreach { case (k, v) => println(f"$k -> $v") }

    // Check result
    val expected = input.groupBy(_._1).mapValues(_.map(_._2).sum).toMap
    val mismatches = expected.filter { case (k, v) => result.getOrElse(k, -9999) != v }

    if (mismatches.isEmpty) {
      println("✅ Final result matches expected output!")
    } else {
      println("❌ Mismatches found:")
      mismatches.foreach { case (k, expectedV) =>
        val actualV = result.getOrElse(k, 0)
        println(f"$k%-10s -> Expected: $expectedV, Got: $actualV")
      }
    }

    spark.stop()
  }
}
