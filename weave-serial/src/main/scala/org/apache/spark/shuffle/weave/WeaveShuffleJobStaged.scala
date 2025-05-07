package org.apache.spark.shuffle.weave

import org.apache.spark.rdd.RDD
import org.apache.spark.shuffle.weave.balancedshuffle._
import org.apache.spark.sql.SparkSession
import org.apache.spark.shuffle.weave.config.{ShufflePlanConfig, WeaveShuffleConf}
import org.apache.spark.shuffle.weave.fakepadding.RepeatRealPlanner
import org.apache.spark.TaskContext


import scala.collection.mutable
import scala.reflect.ClassTag

class WeaveShuffleJobStaged(config: WeaveShuffleConf) extends Serializable {
  
  debugConfig()
  //def runStepByStep(inputRDD: RDD[(String, Int)], spark: SparkSession): Map[K, V] = {
  def runStepByStep[K: Ordering : ClassTag, V: ClassTag](
  inputRDD: RDD[(K, V)],
  spark: SparkSession,
  merge: (V, V) => V,
  zero: V,
  transformKey: K => K = identity[K] _
  ): Map[K, V] = {

    val plan = ShufflePlanConfig(
      alpha = config.alpha,
      beta = config.beta,
      numBins = config.numWeavers,
      seed = config.globalSeed,
      isAssociative = config.fakePaddingStrategy.toLowerCase == "associative",
      binomialMode = config.binomialMode
    )

    val partitioned = inputRDD.mapPartitions { iter =>
	  Iterator(processPartition[K, V](iter, plan, identity[K]))
    }

    val globalHist = partitioned
      .map(_.histogram)
      .reduce(mergeHistograms[K])
      .real

    println("=== Global Histogram ===")
    globalHist.toSeq.sortBy(_._1).foreach { case (k, v) => println(f"$k%-20s -> $v") }

    val (keyToBin, brokenKeys, cutoffs) = assignKeysAndCutoffs(globalHist, plan.numBins, plan.isAssociative)

    println("=== Bin Assignment (Split-Aware) ===")
    keyToBin.toSeq.sortBy(_._1).foreach { case (k, b) =>
      val split = brokenKeys.get(k).map(_._2).getOrElse(1.0)
      println(f"$k%-20s -> Bin $b%-2d SplitRatio = $split%.2f")
    }

    println("=== Bin Cutoffs ===")
    cutoffs.zipWithIndex.foreach { case (k, i) => println(f"Bin $i%-2d cutoff -> $k") }

    val keyToBinBroadcast = spark.sparkContext.broadcast(keyToBin)
    val brokenKeysBroadcast = spark.sparkContext.broadcast(brokenKeys)

    val baseRecords = partitioned.flatMap(_.bins).flatMap {
      case (binId, records) => records.map((binId, _))
    }.map {
      case (_, (k, v)) =>
        brokenKeysBroadcast.value.get(k) match {
          case Some((bin, ratio)) if plan.isAssociative =>
            val r = new scala.util.Random(plan.seed ^ k.hashCode)
            val assigned = if (r.nextDouble() < ratio) bin else math.min(bin + 1, plan.numBins - 1)
            (assigned, (k, v))
          case _ =>
            (keyToBinBroadcast.value(k), (k, v))
        }
    }.partitionBy(new org.apache.spark.HashPartitioner(plan.numBins))

    println("=== Real Records by Bin ===")
    baseRecords.map { case (binId, _) => (binId, 1) }
      .reduceByKey(_ + _)
      .sortByKey()
      .collect()
      .foreach { case (binId, count) => println(f"Bin $binId%-2d -> $count records") }

    val augmentedRecords = if (!plan.isAssociative) {
      val rawCounts = baseRecords.map { case (binId, _) => (binId, 1) }
        .reduceByKey(_ + _)
        .collect()
        .toMap 
      val realCounts = (0 until plan.numBins).map { binId =>
  		rawCounts.getOrElse(binId, 0)
	}.toArray
      val d = realCounts.sum.toDouble / plan.numBins
      val planner = new RepeatRealPlanner(plan.alpha, plan.beta, plan.numBins, plan.seed, plan.binomialMode)
      val fakeCounts = planner.computeFakeCounts(realCounts, d)

      println("=== Fake Planning Result ===")
      fakeCounts.zipWithIndex.foreach { case (count, bin) =>
        println(f"Bin $bin%-2d: FakeCount = $count")
      }
      
      val fakeSamplers: Array[(K, V)] = extractFirstFromEachPartition(baseRecords.map(_._2))
      val fakeRDD: RDD[(Int, (K, V))] = spark.sparkContext.parallelize(0 until plan.numBins).flatMap { binId =>
         val sample = fakeSamplers.lift(binId)
         sample.map(s => (0 until fakeCounts(binId)).map(i => (binId, s))).getOrElse(Seq.empty)
      }
      

      baseRecords.union(fakeRDD).partitionBy(new org.apache.spark.HashPartitioner(plan.numBins))
    } else {
      baseRecords
    }
    
    val reduced = augmentedRecords.map { case (_, (k, v)) => (k, v) }.reduceByKey(merge, plan.numBins)

    val finalMerged = if (plan.isAssociative) reduced
    else mergePostReduce(reduced, brokenKeys, keyToBin, merge, zero, plan.numBins)

    println("=== Final Result ===")
    finalMerged.collect().sortBy(_._1.toString).foreach { case (k, v) => println(f"$k -> $v") }

    finalMerged.collect().toMap

  }

  case class SerializedHistogram[K](real: Map[K, Long], fake: List[(K, Long)])
  case class PartitionOutput[K, V](bins: Map[Int, Seq[(K, V)]], histogram: SerializedHistogram[K], localCount: Long)

  def processPartition[K, V](input: Iterator[(K, V)], config: ShufflePlanConfig, transformKey: K => K): PartitionOutput[K, V] = {
    val rng = new scala.util.Random(config.seed)
    val histCounts = mutable.Map[K, Long]()
    val fakeRecords = mutable.ListBuffer[(K, Long)]()
    val binBuffers = Array.fill(config.numBins)(mutable.ListBuffer.empty[(K, V)])

    while (input.hasNext) {
      val (k, v) = input.next()
      val bin = rng.nextInt(config.numBins)
      binBuffers(bin) += ((k, v))
      if (rng.nextDouble() < config.alpha) {
  	  val mapped = transformKey(k)
          if (histCounts.contains(mapped)) {
    	    histCounts(mapped) += 1L
    	    fakeRecords += ((mapped, 1L))
          } else {
    	    histCounts.update(mapped, 1L)
  	  }
      }
    } 
    val partitionId = TaskContext.getPartitionId()    
    if (partitionId == 0) {
    val localRealHist = histCounts.toSeq.sortBy(_._1.toString)
    println("=== Local Histogram ===")
    localRealHist.foreach { case (k, v) => println(f"$k%-20s -> $v")}
    }
    PartitionOutput(
      bins = binBuffers.zipWithIndex.map { case (buf, i) => i -> buf.toSeq }.toMap,
      histogram = SerializedHistogram(histCounts.toMap, fakeRecords.toList),
      localCount = binBuffers.map(_.size).sum
    )
  }

  def mergeHistograms[K](a: SerializedHistogram[K], b: SerializedHistogram[K]): SerializedHistogram[K] = {
    val real = (a.real.toSeq ++ b.real.toSeq).groupBy(_._1).map { case (k, v) => k -> v.map(_._2).sum }
    val fake = a.fake ++ b.fake
    SerializedHistogram(real, fake)
  }

  def mergePostReduce[K: ClassTag, V: ClassTag](
    primary: RDD[(K, V)],
    brokenKeys: Map[K, (Int, Double)],
    keyToBin: Map[K, Int],
    merge: (V, V) => V,
    zero: V,
    numBins: Int
  ): RDD[(K, V)] = {
    val partials = primary.filter { case (k, _) => brokenKeys.contains(k) && brokenKeys(k)._1 != keyToBin(k) }
    val base = primary
    base.union(partials).reduceByKey(merge, numBins)
  }

  def assignKeysAndCutoffs[K: Ordering : ClassTag](
  histogram: Map[K, Long],
  numBins: Int,
  isAssociative: Boolean
): (Map[K, Int], Map[K, (Int, Double)], Array[K]) = {
  if (!isAssociative) {
    val packer = new FirstFitBinPacking[K](numBins, orderBy = "hashcode")  // or "ordering"
    packer.fit(histogram)

    val keyToBin = histogram.keys.map(k => k -> packer.assignBin(k)).toMap
    val cutoffs = keyToBin.toSeq.groupBy(_._2).flatMap {
      case (_, keys) =>
        keys.map(_._1).sorted.lastOption.map(last => (last, ()))
    }.keys.toArray.sorted

    (keyToBin, Map.empty, cutoffs)
  } else {
    val result = org.apache.spark.shuffle.weave.balancedshuffle.SplitBinPacking
      .assignKeysWithSplitsFirstFit(histogram, numBins, allowSplits = true)
    val cutoffs = result.keyToBin.toSeq.groupBy(_._2)
      .mapValues(_.map(_._1).max)
      .toSeq.sortBy(_._1)
      .map(_._2).toArray
    (result.keyToBin, result.brokenKeys, cutoffs)
  }
 }
 def extractFirstFromEachPartition[K, V](rdd: RDD[(K, V)]): Array[(K, V)] = {
  rdd.mapPartitions { iter =>
    iter.take(1).toIterator // take(1) returns an Iterable, we convert it to Iterator
  }.collect()
 }

 def debugConfig(): Unit = {
  println("=== WeaveShuffleConf ===")
  println(f"alpha:              ${config.alpha}")
  println(f"beta:               ${config.beta}")
  println(f"numWeavers:         ${config.numWeavers}")
  println(f"globalSeed:         ${config.globalSeed}")
  println(f"isAssociative:      ${config.fakePaddingStrategy.toLowerCase == "associative"}")
  println(f"fakePaddingStrategy:${config.fakePaddingStrategy}")
  println(f"binomialMode:       ${config.binomialMode}")
  println("========================")
}


}
