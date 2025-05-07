package org.apache.spark.shuffle.baseline

import org.apache.spark.sql.{DataFrame, SparkSession, Row}
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types._
import org.apache.spark.sql.expressions.Window
import scala.util.Random

object ColumnSortUtil {
  def columnSort(df: DataFrame, numWorkers: Int, spark: SparkSession): DataFrame = {
    import spark.implicits._
    val t0 = System.nanoTime()

    val input = df.select(col("key").cast("string")).repartition(numWorkers)
    val numRecords = input.count
    val numRowsTmp = math.ceil(numRecords.toFloat / numWorkers).toInt
    val numRows = math.ceil(numRowsTmp.toFloat / numWorkers).toInt * numWorkers
    val halfRows = numRows / 2
    val numPadRows = numRows * numWorkers - numRecords

    val realDF = input.withColumn("realRecord", lit(true))
    val fakeDF = realDF.limit(1).withColumn("realRecord", lit(false))
      .crossJoin(Seq.fill(numPadRows.toInt)(1).toDF("dummy")).drop("dummy")

    val fullDF = realDF.union(fakeDF).persist()
    fullDF.count()
    println(s"✅ sorted1 took ${(System.nanoTime() - t0) / 1e9} sec")

    def sortByKey(df: DataFrame): DataFrame = {
      val rdd = df.rdd.mapPartitions(_.toSeq.sortBy(_.getAs[String]("key")).iterator, preservesPartitioning = true)
      spark.createDataFrame(rdd, df.schema)
    }

    val sorted1 = sortByKey(fullDF).persist(); sorted1.collect()
    sorted1.count()
    println(s"✅ sorted1 took ${(System.nanoTime() - t0) / 1e9} sec")

    val transposedRDD = sorted1.rdd.mapPartitionsWithIndex { case (index, iter) =>
      var counter = index * numRows
      iter.map { row =>
  	val result = Row.fromSeq(row.toSeq :+ (counter % numWorkers))
  	counter += 1
  	result
	}

    }
    val transposedSchema = sorted1.schema.add("transposePartitionId", IntegerType)
    val transposed = spark.createDataFrame(transposedRDD, transposedSchema)
      .repartitionByRange(numWorkers, col("transposePartitionId")).drop("transposePartitionId").persist()
    transposed.collect()
    transposed.count()
    println(s"✅ transposed1 took ${(System.nanoTime() - t0) / 1e9} sec")

    val sorted2 = sortByKey(transposed).persist(); sorted2.collect()
    sorted2.count()
    println(s"✅ sorted2 took ${(System.nanoTime() - t0) / 1e9} sec") 
    
    val invTransposedRDD = sorted2.rdd.mapPartitionsWithIndex { case (index, iter) =>
      val rowsPerWorker = numRows / numWorkers
      var counter = 0
      iter.map { row =>
        val result = Row.fromSeq(row.toSeq :+ (counter / numWorkers))
        counter += 1
        result
      }

    }
    val invTransposedSchema = sorted2.schema.add("transposePartitionId", IntegerType)
    val invTransposed = spark.createDataFrame(invTransposedRDD, invTransposedSchema)
      .repartitionByRange(numWorkers, col("transposePartitionId")).drop("transposePartitionId").persist()
    invTransposed.collect()
    invTransposed.count()
    println(s"✅ Inv transposed took ${(System.nanoTime() - t0) / 1e9} sec") 

    val sorted3 = sortByKey(invTransposed).persist(); sorted3.collect()
    sorted3.count()
    println(s"✅ Sorted3 took ${(System.nanoTime() - t0) / 1e9} sec")

    val downShiftedRDD = sorted3.rdd.mapPartitionsWithIndex { case (index, iter) =>
      var counter = index * numRows + halfRows
      iter.map { row =>
        val result = Row.fromSeq(row.toSeq :+ (counter / numWorkers))
        counter += 1
        result
        }

    }
    val shiftSchema = sorted3.schema.add("downShiftPartitionId", IntegerType)
    val downShifted = spark.createDataFrame(downShiftedRDD, shiftSchema)
      .repartitionByRange(numWorkers, col("downShiftPartitionId") % lit(numWorkers)).persist()
    downShifted.collect()
    downShifted.count()
    println(s"✅ downShifted took ${(System.nanoTime() - t0) / 1e9} sec")

    val colIndex = downShifted.columns.length - 1
    val sorted4RDD = downShifted.rdd.mapPartitions(_.toSeq.sortBy(row =>
      row.getInt(colIndex).toString + row.getAs[String]("key")).iterator)
    val sorted4 = spark.createDataFrame(sorted4RDD, downShifted.schema).persist()
    sorted4.collect()
    sorted4.count()
    println(s"✅ Sorted4 took ${(System.nanoTime() - t0) / 1e9} sec")

    val upShiftedRDD = sorted4.rdd.mapPartitionsWithIndex { case (index, iter) =>
      var counter = index * numRows - halfRows
      iter.map { row =>
        val newReducerId = if (index == 0)
          (row.getInt(colIndex) / numWorkers) * (numWorkers - 1)
        else
          counter / numRows
        counter += 1
        Row.fromSeq(row.toSeq :+ newReducerId)
      }
    }
    val reducerSchema = sorted4.schema.add("reducerId", IntegerType)
    val upShifted = spark.createDataFrame(upShiftedRDD, reducerSchema)
      .drop("downShiftPartitionId").repartitionByRange(numWorkers, col("reducerId")).persist()
    upShifted.collect()
    upShifted.count()
    println(s"✅ Upshifted took ${(System.nanoTime() - t0) / 1e9} sec")

    val sorted5 = sortByKey(upShifted).persist(); sorted5.collect()
    sorted5.count()
    println(s"✅ Sorted5 took ${(System.nanoTime() - t0) / 1e9} sec")

    val result = sorted5.filter("realRecord = true").drop("realRecord").persist()

    val checkDF = result.withColumn("monotonicId", monotonically_increasing_id())
      .withColumn("previous_key", lag("key", 1).over(Window.orderBy("monotonicId")))
    val errors = checkDF.filter(col("key") < col("previous_key")).count()

    if (errors == 0) println("✅ ColumnSort verification passed.")
    else println(s"❌ ColumnSort failed with $errors disorder(s).")

    result
  }
}
