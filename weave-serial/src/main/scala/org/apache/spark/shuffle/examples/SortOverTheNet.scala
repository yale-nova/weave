package org.apache.spark.shuffle.examples

import scala.util.Random
import org.apache.spark.shuffle.baseline.ColumnSortUtil.columnSort
import org.apache.spark.sql.{SparkSession, DataFrame}
import org.apache.spark.SparkConf

object ColumnSortRemoteBench {
  def main(args: Array[String]): Unit = {
    val master = if (args.length > 0) args(0) else "local[4]"
    val numRecords = if (args.length > 1) args(1).toInt else 1000000

    val sparkConf = new SparkConf()
      .setAppName("ColumnSortTest")

    val spark = SparkSession.builder().config(sparkConf).getOrCreate()
    import spark.implicits._

    val numWorkers = 10
    val df = spark.sparkContext.parallelize(0 until numRecords)
      .map(i => (Random.alphanumeric.take(10).mkString, i))
      .toDF("key", "value")

    df.cache()
    println(s"🚀 Starting ColumnSort with $numRecords records and $numWorkers workers...")

    val startTime = System.nanoTime()
    val sortedDF: DataFrame = columnSort(df, numWorkers, spark)
    val duration = (System.nanoTime() - startTime) / 1e9

    println(f"⏱️  ColumnSort completed in $duration%.2f seconds.")
    sortedDF.show(10, truncate = false)

    spark.stop()
  }
}
