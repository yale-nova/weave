package org.apache.spark.shuffle.baseline

import scala.util.Random
import org.apache.spark.shuffle.baseline.ColumnSortUtil.columnSort
import org.apache.spark.sql.{SparkSession, DataFrame}
import org.apache.spark.SparkConf

object TestColumnSort {
  def main(args: Array[String]): Unit = {
    val sparkConf = new SparkConf()
      .setAppName("ColumnSortTest")
      .setMaster("local[4]") // adjust parallelism
    val spark = SparkSession.builder().config(sparkConf).getOrCreate()

    import spark.implicits._

    // Generate synthetic data
    val numRecords = 1000000
    val numWorkers = 10
    val df = spark.sparkContext.parallelize(0 until numRecords)
      .map(i => (Random.alphanumeric.take(10).mkString, i))
      .toDF("key", "value")

    df.cache()
    println(s"🚀 Starting ColumnSort with $numRecords records and $numWorkers workers...")

    val startTime = System.nanoTime()
    val sortedDF: DataFrame = columnSort(df, numWorkers, spark)
    val duration = (System.nanoTime() - startTime) / 1e9

    println(f"⏱️ ColumnSort completed in $duration%.2f seconds.")
    sortedDF.show(10, truncate = false)

    spark.stop()
  }
}
