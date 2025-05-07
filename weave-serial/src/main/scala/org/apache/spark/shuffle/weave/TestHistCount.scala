package org.apache.spark.shuffle.weave

import org.apache.spark.sql.SparkSession
import org.apache.spark.shuffle.weave.WeaveShuffleJobSerialized
import org.apache.spark.shuffle.weave.config.WeaveShuffleConf
import org.apache.spark.{SparkConf, SparkContext}
import org.apache.log4j.{Level, Logger}
import scala.io.Source

object TestDriverHistCount {

  def main(args: Array[String]): Unit = {
    Logger.getLogger("org").setLevel(Level.ERROR)

    val sparkConf = new SparkConf()
      .setMaster("local[2]")
      .setAppName("WeaveWordCountTest")
      .set("spark.weave.alpha", "0.2")
      .set("spark.weave.numWeavers", "10")
      .set("spark.weave.fakePadding", "associative") // Set non-associative mode
    val spark = SparkSession.builder().config(sparkConf).getOrCreate()

    val conf = WeaveShuffleConf.fromSparkConf(sparkConf)

    // Load the downloaded book
    val bookPath = "data/beyond-the-pleasure-principle.txt"
    val textRDD = spark.sparkContext.textFile(bookPath)

    // Preprocess text: split into words
    val wordsRDD = textRDD
      .flatMap(_.toLowerCase.replaceAll("[^a-z0-9 ]", " ").split("\\s+"))
      .filter(_.nonEmpty)
      .map(word => (word, 1))

    // Run Weave Shuffle
    val job = new WeaveShuffleJobSerialized(conf)
    val finalResult: Map[String, Int] = job.runStepByStep(
      wordsRDD,
      spark,
      (a: Int, b: Int) => a + b,
      0
    )

    // Print top 20 most frequent words
    val top20Weave = finalResult.toSeq.sortBy(-_._2).take(20)

    val baseline = wordsRDD
    .reduceByKey(_ + _)
    .collect()
    .toMap
   

    println("=== Top 20 Words ===")
    top20Weave.foreach {
      case (word, count) => println(f"$word%-15s -> $count")
    }

   // === Compare results ===
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
  }}
    spark.stop()
  }
}
