package org.apache.spark.shuffle.examples

import org.apache.spark.sql.SparkSession
import org.apache.spark.shuffle.weave.WeaveShuffleJobSerialized
import org.apache.spark.shuffle.weave.config.WeaveShuffleConf
import org.apache.spark.{SparkConf, SparkContext}
import org.apache.log4j.{Level, Logger}
import scala.util.Random

object WeaveShuffleRemoteBench {

  def main(args: Array[String]): Unit = {
    Logger.getLogger("org").setLevel(Level.ERROR)

    //val master = if (args.length > 0) args(0) else "local[2]"
    val numRecords = if (args.length > 1) args(1).toInt else 1000000

    val sparkConf = new SparkConf()
      .setAppName("WeaveWordCountTest")
      .set("spark.weave.alpha", "0.2")
      .set("spark.weave.numWeavers", 10))
      .set("spark.weave.fakePadding", "associative")

    val spark = SparkSession.builder().config(sparkConf).getOrCreate()
    val conf = WeaveShuffleConf.fromSparkConf(sparkConf)

    // Simulated input: random words
    val inputRDD = spark.sparkContext.parallelize(0 until numRecords).map { _ =>
      val word = f"key${Random.nextInt(50)}%02d"
      (word, 1)
    }

    val job = new WeaveShuffleJobSerialized(conf)
    val finalResult: Map[String, Int] = job.runStepByStep(
      inputRDD,
      spark,
      (a: Int, b: Int) => a + b,
      0
    )

    // Baseline for validation
    val baseline = inputRDD.reduceByKey(_ + _).collect().toMap

    val top20Weave = finalResult.toSeq.sortBy(-_._2).take(20)
    println("=== Top 20 Words (Weave) ===")
    top20Weave.foreach { case (word, count) =>
      println(f"$word%-15s -> $count")
    }

    val mismatches = baseline.filter {
      case (k, v) => finalResult.getOrElse(k, -1) != v
    }

    if (mismatches.isEmpty) {
      println("✅ Final result matches standard Spark word count.")
    } else {
      println(s"❌ ${mismatches.size} mismatches found:")
      mismatches.toSeq.sortBy(-_._2).take(20).foreach {
        case (word, expected) =>
          val actual = finalResult.getOrElse(word, 0)
          println(f"$word%-15s => Expected: $expected, Got: $actual")
      }
    }

    spark.stop()
  }
}
