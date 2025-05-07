package org.apache.spark.shuffle.baseline

import org.apache.spark.shuffle.baseline.ColumnSortUtil.columnSort

import org.apache.log4j.{Level, Logger}
import org.apache.spark.sql.{SparkSession, DataFrame, Row}
import org.apache.spark.sql.functions._
import org.apache.spark.sql.expressions.Window
import org.apache.spark.sql.types._
import scala.util.Random

object ColumnSortVsHistTest {

  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("ColumnSortVsHistTest")
      .master("local[4]")
      .getOrCreate()

    Logger.getLogger("org").setLevel(Level.ERROR)
    Logger.getLogger("akka").setLevel(Level.ERROR)
    Logger.getLogger("org.apache.spark").setLevel(Level.ERROR)
    Logger.getLogger("org.apache.hadoop").setLevel(Level.ERROR)

    import spark.implicits._

    val numRecords = 1000000
    val numWorkers = 10

    // Generate dummy key-value data
    val df = spark.sparkContext.parallelize(0 until numRecords).map { i =>
      val key = Random.alphanumeric.take(10).mkString
      (key, 1)
    }.toDF("key", "value").repartition(numWorkers).persist()

    println("✅ Data generation complete.")
    df.count() // Force materialization

    // Histogram count timing (groupBy)
    val t0 = System.nanoTime()
    val hist = df.groupBy("key").agg(sum("value").as("count")).persist()
    val histCount = hist.count()
    val t1 = System.nanoTime()
    println(f"⏱️ Histogram count completed: $histCount keys in ${(t1 - t0) / 1e9}%.2f seconds")

    // ColumnSort timing
    val t2 = System.nanoTime()
    val sortedDF = columnSort(df.select("key"), numWorkers, spark).persist()
    val sortCount = sortedDF.count()
    val t3 = System.nanoTime()
    println(f"⏱️ columnSort completed: $sortCount rows in ${(t3 - t2) / 1e9}%.2f seconds")

    // Native Spark sort timing
    val t4 = System.nanoTime()
    val nativeSorted = df.select("key").orderBy("key").persist()
    val nativeSortCount = nativeSorted.count()
    val t5 = System.nanoTime()
    println(f"⏱️ Native Spark sort completed: $nativeSortCount rows in ${(t5 - t4) / 1e9}%.2f seconds")

    spark.stop()
  }
}
