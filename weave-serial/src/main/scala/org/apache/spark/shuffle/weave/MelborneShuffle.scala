package org.apache.spark.shuffle.weave

import scala.util.Random
import org.apache.spark.rdd.RDD
import org.apache.spark.shuffle.weave.balancedshuffle._
import org.apache.spark.sql.SparkSession
import org.apache.spark.shuffle.weave.config.{ShufflePlanConfig, WeaveShuffleConf}
import org.apache.spark.shuffle.weave.fakepadding.RepeatRealPlanner
import scala.collection.mutable
import scala.reflect.ClassTag

case class TaggedRecord[K, V](key: K, value: V, tag: Long, isFake: Boolean = false)

class MelbourneShuffle(config: WeaveShuffleConf) extends Serializable {

  def runStepByStep[K: Ordering : ClassTag, V: ClassTag](
    inputRDD: RDD[(K, V)],
    spark: SparkSession,
    merge: (V, V) => V,
    zero: V,
    bufferPaddingFactor: Int,
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

    println("📦 [Stage 1] Starting Melbourne Shuffle")
    val partitionInput = melShuffle(inputRDD, spark, bufferPaddingFactor, plan)

    println("🧩 [Stage 2] Partitioning Data")
    val partitioned = partitionInput.mapPartitions { iter =>
      Iterator(processPartition[K, V](iter, plan, identity[K]))
    }

    println("📊 [Stage 3] Merging Histograms")
    val globalHist = partitioned.map(_.histogram).reduce(mergeHistograms[K]).real
    globalHist.toSeq.sortBy(_._1).foreach { case (k, v) => println(f"$k%-20s -> $v") }

    println("🎯 [Stage 4] Key Bin Assignment")
    val (_, brokenKeys, cutoffs) = assignKeysAndCutoffs(globalHist, plan.numBins, plan.isAssociative)
    println("Cutoffs: " + cutoffs.mkString(", "))

    val cutoffsBroadcast = spark.sparkContext.broadcast(cutoffs)
    val brokenKeysBroadcast = spark.sparkContext.broadcast(brokenKeys)

    println("📤 [Stage 5] Assigning Records to Bins")
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
            val bin = cutoffs.indexWhere(cutoff => implicitly[Ordering[K]].lteq(k, cutoff))
            val assignedBin = if (bin == -1) cutoffs.length else bin
            (assignedBin, (k, v))
        }
    }.partitionBy(new org.apache.spark.HashPartitioner(plan.numBins))

    println("🎭 [Stage 6] Padding with Fake Records")
    val augmentedRecords = if (!plan.isAssociative) {
      val rawCounts = baseRecords
        .map { case (binId, _) => (binId, 1) }
        .reduceByKey(_ + _)
        .collect()
        .toMap

      val realCounts = (0 until plan.numBins).map(binId => rawCounts.getOrElse(binId, 0)).toArray
      println("Real counts per bin: " + realCounts.mkString(", "))

      val d = realCounts.sum.toDouble / plan.numBins
      val planner = new RepeatRealPlanner(plan.alpha, plan.beta, plan.numBins, plan.seed, plan.binomialMode)
      val fakeCounts = planner.computeFakeCounts(realCounts, d)
      println("Fake counts per bin: " + fakeCounts.mkString(", "))

      val fakeSamplers = extractFirstFromEachPartition(baseRecords.map(_._2))
      val fakeRDD = spark.sparkContext.parallelize(0 until plan.numBins).flatMap { binId =>
        val sample = fakeSamplers.lift(binId)
        sample.map(s => (0 until fakeCounts(binId)).map(i => (binId, s))).getOrElse(Seq.empty)
      }

      baseRecords.union(fakeRDD).partitionBy(new org.apache.spark.HashPartitioner(plan.numBins))
    } else baseRecords

    println("🧮 [Stage 7] Reducing Output")
    val reduced = augmentedRecords.map { case (_, (k, v)) => (k, v) }.reduceByKey(merge, plan.numBins)

    val finalMerged = if (plan.isAssociative) reduced
    else mergePostReduce(reduced, brokenKeys, cutoffs, merge, zero, plan.numBins)

    println("✅ [Stage 8] Final Result:")
    val finalResult = finalMerged.collect().toMap
    finalResult.toSeq.sortBy(_._1).foreach { case (k, v) => println(f"$k -> $v") }

    finalResult
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

  def mergePostReduce[K: ClassTag: Ordering, V: ClassTag](
    primary: RDD[(K, V)],
    brokenKeys: Map[K, (Int, Double)],
    cutoffs: Array[K],
    merge: (V, V) => V,
    zero: V,
    numBins: Int
  ): RDD[(K, V)] = {
    val partials = primary.filter { case (k, _) =>
      brokenKeys.contains(k) && {
        val actualBin = cutoffs.indexWhere(cutoff => implicitly[Ordering[K]].lteq(k, cutoff))
        brokenKeys(k)._1 != actualBin
      }
    }
    primary.union(partials).reduceByKey(merge, numBins)
  }

  def assignKeysAndCutoffs[K: Ordering : ClassTag](
    histogram: Map[K, Long],
    numBins: Int,
    isAssociative: Boolean
  ): (Map[K, Int], Map[K, (Int, Double)], Array[K]) = {
    if (!isAssociative) {
      val packer = new FirstFitBinPacking[K](numBins, orderBy = "hashcode")
      packer.fit(histogram)

      val keyToBin = histogram.keys.map(k => k -> packer.assignBin(k)).toMap
      val cutoffs = keyToBin.toSeq.groupBy(_._2).flatMap {
        case (_, keys) => keys.map(_._1).sorted.lastOption.map(last => (last, ()))
      }.keys.toArray.sorted

      (keyToBin, Map.empty, cutoffs)
    } else {
      val result = SplitBinPacking.assignKeysWithSplitsFirstFit(histogram, numBins, allowSplits = true)
      val cutoffs = result.keyToBin.toSeq.groupBy(_._2)
        .mapValues(_.map(_._1).max)
        .toSeq.sortBy(_._1)
        .map(_._2).toArray
      (result.keyToBin, result.brokenKeys, cutoffs)
    }
  }

  def extractFirstFromEachPartition[K, V](rdd: RDD[(K, V)]): Array[(K, V)] = {
    rdd.mapPartitions(_.take(1)).collect()
  }

  def melShuffle[K: Ordering : ClassTag, V: ClassTag](
    input: RDD[(K, V)],
    spark: SparkSession,
    bufferPaddingFactor: Int,
    plan: ShufflePlanConfig
  ): RDD[(K, V)] = {
    val tagged = input.mapPartitionsWithIndex { (pid, iter) =>
      val rng = new Random(plan.seed ^ pid)
      iter.map { case (k, v) =>
        val tag = rng.nextLong()
        val bin = (tag % plan.numBins).toInt.abs
        (bin, TaggedRecord(k, v, tag))
      }
    }.groupByKey(plan.numBins).flatMapValues { records =>
      val recList = records.toArray
      val paddedSize = (bufferPaddingFactor * recList.size.toDouble).ceil.toInt
      val rng = new Random(plan.seed ^ recList.hashCode())
      val fakesNeeded = paddedSize - recList.length
      val fakes = (0 until fakesNeeded).map(_ =>
        TaggedRecord[K, V](null.asInstanceOf[K], null.asInstanceOf[V], rng.nextLong(), isFake = true)
      )
      rng.shuffle((recList ++ fakes).toSeq).iterator
    }.map(_._2)
    
    tagged.collect()
    tagged.persist()
    tagged.count()

    println(s"🎲 [Stage Shuffle] Tagged ${tagged.count()} records with padding")

    val filtered = tagged.filter(!_.isFake)
    filtered.collect()
    filtered.persist()
    filtered.count()

    val sorted = filtered.sortBy(_.tag).map(r => (r.key, r.value))
    sorted.persist()
    sorted.collect()
    sorted.count()
    println(s"✅ [Stage Shuffle] Retained ${sorted.count()} real records after filtering")
    sorted
  }
}
