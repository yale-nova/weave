import org.apache.spark.rdd.RDD
import org.apache.spark.sql.SparkSession
import org.apache.spark.shuffle.weave.config.{ShufflePlanConfig, WeaveShuffleConf}
import org.apache.spark.shuffle.weave.fakepadding.RepeatRealPlanner
import org.apache.spark.shuffle.weave.randomshuffle.PRGShuffle
import org.apache.spark.TaskContext

import scala.collection.mutable
import scala.reflect.ClassTag

class WeaveShuffleJob(config: WeaveShuffleConf) extends Serializable {

  def run(inputRDD: RDD[(String, Int)], spark: SparkSession): Map[String, Int] = {
    val plan = ShufflePlanConfig(
      alpha = config.alpha,
      beta = config.beta,
      numBins = config.numWeavers,
      seed = config.globalSeed,
      isAssociative = config.fakePaddingStrategy.toLowerCase == "associative",
      binomialMode = config.binomialMode
    )
    val (flatRecords, keyToBin, brokenKeys, partitionCutoffs) = postMap(inputRDD, plan, spark)
    postReduce(flatRecords, keyToBin, brokenKeys, plan)
  }

  def postMap(
    inputRDD: RDD[(String, Int)],
    config: ShufflePlanConfig,
    spark: SparkSession
  ): (RDD[(Int, (String, Int))], Map[String, Int], Map[String, (Int, Double)], Array[String]) = {
    val partitioned = inputRDD.mapPartitions { iter =>
      Iterator(processPartition[String, Int](iter, config, identity[String]))
    }

    val globalHist = partitioned
      .map(_.histogram)
      .reduce(mergeHistograms[String])
      .real

    println("=== Global Histogram ===")
    globalHist.toSeq.sortBy(_._1).foreach { case (k, v) => println(f"$k%-20s -> $v") }

    val (keyToBin, brokenKeys, cutoffs) = {
      require(TaskContext.get() == null, "Key assignment must be done on the driver")
      assignKeysAndCutoffs[String](globalHist, config.numBins, config.isAssociative)
    }

    println("=== Bin Assignment (Split-Aware) ===")
    keyToBin.toSeq.sortBy(_._1).foreach { case (k, b) =>
      val split = brokenKeys.get(k).map(_._2).getOrElse(1.0)
      println(f"$k%-20s -> Bin $b%-2d SplitRatio = $split%.2f")
    }

    println("=== Bin Cutoffs ===")
    cutoffs.zipWithIndex.foreach { case (k, i) => println(f"Bin $i%-2d cutoff -> $k") }

    val keyToBinBroadcast = spark.sparkContext.broadcast(keyToBin)
    val brokenKeysBroadcast = spark.sparkContext.broadcast(brokenKeys)

    val baseRecords: RDD[(Int, (String, Int))] = partitioned.flatMap(_.bins).flatMap {
      case (binId, records) => records.map((binId, _))
    }.map {
      case (_, (k, v)) =>
        brokenKeysBroadcast.value.get(k) match {
          case Some((bin, ratio)) if config.isAssociative =>
            val r = new scala.util.Random(config.seed ^ k.hashCode)
            val assigned = if (r.nextDouble() < ratio) bin else math.min(bin + 1, config.numBins - 1)
            (assigned, (k, v))
          case _ =>
            (keyToBinBroadcast.value(k), (k, v))
        }
    }.partitionBy(new org.apache.spark.HashPartitioner(config.numBins))

    if (!config.isAssociative) {
      val realCounts = baseRecords.map { case (binId, _) => (binId, 1) }
        .reduceByKey(_ + _)
        .sortByKey()
        .map(_._2)
        .collect()

      val d = realCounts.sum.toDouble / config.numBins
      val planner = new RepeatRealPlanner(config.alpha, config.beta, config.numBins, config.seed, config.binomialMode)
      val fakeCounts = planner.computeFakeCounts(realCounts.toArray, d)

      println("=== Fake Planning Result ===")
      fakeCounts.zipWithIndex.foreach { case (count, bin) =>
        println(f"Bin $bin%-2d: FakeCount = $count")
      }

      val fakeRDD = spark.sparkContext.parallelize(0 until config.numBins).flatMap { binId =>
        (0 until fakeCounts(binId)).map(i => (binId, (s"fake-$binId-$i", -1)))
      }

      val augmentedRecords = baseRecords.union(fakeRDD).partitionBy(new org.apache.spark.HashPartitioner(config.numBins))
      return (augmentedRecords, keyToBin, brokenKeys, cutoffs)
    }

    (baseRecords, keyToBin, brokenKeys, cutoffs)
  }

  def postReduce(
    flatRecords: RDD[(Int, (String, Int))],
    keyToBin: Map[String, Int],
    brokenKeys: Map[String, (Int, Double)],
    config: ShufflePlanConfig
  ): Map[String, Int] = {
    val reduced: RDD[(String, Int)] = flatRecords.map {
      case (_, (k, _)) => (k, 1)
    }.reduceByKey(_ + _, config.numBins)

    val finalMerged =
      if (config.isAssociative) reduced
      else mergePostReduce(reduced, brokenKeys, keyToBin, (a: Int, b: Int) => a + b, 0, config.numBins)

    finalMerged.collect().toMap
  }

  case class SerializedHistogram[K](real: Map[K, Long], fake: List[(K, Long)])
  case class PartitionOutput[K, V](bins: Map[Int, Seq[(K, V)]], histogram: SerializedHistogram[K], localCount: Long)

  def processPartition[K, V](
    input: Iterator[(K, V)],
    config: ShufflePlanConfig,
    transformKey: K => K
  ): PartitionOutput[K, V] = {
    val rng = new scala.util.Random(config.seed)
    val histCounts = mutable.Map[K, Long]()
    val fakeRecords = mutable.ListBuffer[(K, Long)]()
    val binBuffers = Array.fill(config.numBins)(mutable.ListBuffer.empty[(K, V)])

    while (input.hasNext) {
      val (k, v) = input.next()
      val bin = rng.nextInt(config.numBins)
      binBuffers(bin) += ((k, v))
      if (!config.isAssociative && rng.nextDouble() < config.alpha) {
        val mapped = transformKey(k)
        if (histCounts.contains(mapped)) fakeRecords += ((mapped, 1L))
        else histCounts.update(mapped, 1L)
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
      val orderedKeys = histogram.keys.toSeq.sorted
      val binLoads = Array.fill(numBins)(0L)
      val assignment = mutable.HashMap.empty[K, Int]
      for (key <- orderedKeys) {
        val target = binLoads.indices.minBy(binLoads)
        binLoads(target) += histogram(key)
        assignment.update(key, target)
      }
      val cutoffs = orderedKeys.grouped(math.ceil(orderedKeys.size / numBins.toDouble).toInt).map(_.last).toArray
      (assignment.toMap, Map.empty, cutoffs)
    } else {
      val result = org.apache.spark.shuffle.weave.balancedshuffle.SplitBinPacking.assignKeysWithSplits(histogram, numBins, allowSplits = true)
      val cutoffs = result.keyToBin.toSeq.groupBy(_._2).mapValues(_.map(_._1).max).toSeq.sortBy(_._1).map(_._2).toArray
      (result.keyToBin, result.brokenKeys, cutoffs)
    }
  }
}
