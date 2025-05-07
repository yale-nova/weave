package org.apache.spark.shuffle.weave

import org.apache.spark.sql.SparkSession
import org.apache.spark.SparkConf
import org.apache.spark.shuffle.weave.config.WeaveShuffleConf
import org.apache.spark.shuffle.weave.WeaveShuffleJobSerialized
import org.apache.log4j.{Level, Logger}

object TestMelbourneDriver {
  def main(args: Array[String]): Unit = {
    // Suppress Spark and Akka logs for clarity
    Logger.getLogger("org").setLevel(Level.ERROR)
    Logger.getLogger("akka").setLevel(Level.ERROR)

    // Local Spark setup for test/dev use
    val sparkConf = new SparkConf()
      .setAppName("WeaveTest")
      .setMaster("local[*]") // Run locally with all CPU cores
      .set("spark.weave.alpha", "1.0")
      .set("spark.weave.fakePadding", "nonapplicable")
      .set("spark.weave.numWeavers", "10")

    val spark = SparkSession.builder().config(sparkConf).getOrCreate()

    // Extract config
    val conf = WeaveShuffleConf.fromSparkConf(sparkConf)

    // Sample input: skewed key distribution
    val input = Seq.fill(500000) {
      val word = f"key${(scala.util.Random.nextInt(100) + 1)}%02d"
      (word, 1)
    }

    val inputRDD = spark.sparkContext.parallelize(input, 10)

    // Run Weave shuffle job
    val job = new MelbourneShuffle(conf)
    val result = job.runStepByStep[String, Int](
  		inputRDD,
  		spark,
  		merge = _ + _,
  		zero = 0, 
                5
     )

  println("=== Final Result ===")
  result.toSeq.sortBy(_._1).foreach { case (k, v) => println(f"$k -> $v") }

  val expected = input.groupBy(_._1).mapValues(_.map(_._2).sum).toMap
  val mismatches = expected.filter { case (k, v) => result.getOrElse(k, -9999) != v }

  if (mismatches.isEmpty) {
  println("✅ [Melbourne Shuffle]: Final result matches expected output!")
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
