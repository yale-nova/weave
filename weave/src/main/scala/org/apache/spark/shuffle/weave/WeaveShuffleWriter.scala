package org.apache.spark.shuffle.weave

//import org.apache.spark.shuffle.MapStatus		
import org.apache.spark.shuffle._
import org.apache.spark.{TaskContext, SparkEnv}
import org.apache.spark.shuffle.weave.config.WeaveShuffleConf
import org.apache.spark.shuffle.weave.histogram._
import org.apache.spark.shuffle.weave.balancedshuffle._
import org.apache.spark.shuffle.weave.fakepadding._
import org.apache.spark.shuffle.weave.randomshuffle._
import org.apache.spark.shuffle.weave.utils._

import java.io.OutputStream

class WeaveShuffleWriter[K: Ordering, V](
    handle: BaseShuffleHandle[K, V, _],
    mapId: Int,
    context: TaskContext,
    conf: WeaveShuffleConf
) extends ShuffleWriter[K, V] {

  private var stopping = false

  override def write(records: Iterator[Product2[K, V]]): Unit = {
    val (buffered, localHistogram, totalLocalCount) = readAndSampleMapOutput(records)
    val (globalHistogram, globalInputSize) = syncAndMergeHistogram(localHistogram, totalLocalCount)
    val binPacking = planBinAssignment(globalHistogram)
    val fakeCounts = planFakePadding(binPacking, globalInputSize, buffered)
    tagAndSend(buffered, binPacking, fakeCounts)
  }

  override def stop(success: Boolean): Option[Nothing] = {
    stopping = true
    None // TBD: Return real MapStatus
  }

  // ------------------ Pipeline Stages ------------------

  private def readAndSampleMapOutput(records: Iterator[Product2[K, V]]): (Seq[(K, V)], Map[K, Long], Int) = {
    val hist = new HistogramBuilder[K](conf.alpha, conf.globalSeed + mapId, conf.histogramStrategy)
    val buffer = scala.collection.mutable.Buffer[(K, V)]()
    var count = 0
    while (records.hasNext) {
      val record = records.next()
      val k = record._1
      val v = record._2
      buffer += ((k, v))
      hist.maybeAdd(k)
      count += 1
    }
    (buffer.toSeq, hist.snapshot(), count)
  }

  private def syncAndMergeHistogram(localHist: Map[K, Long], localCount: Int): (Map[K, Long], Int) = {
    // TODO: implement centralized or decentralized merge strategy
    // For now, assume centralized merge via driver
    (localHist, localCount) // stub return
  }

  

  private def planBinAssignment(globalHist: Map[K, Long]): BalancedShuffleStrategy[K] = {
    new SimpleGreedyBinPacking[K](globalHist, conf.numWeavers, orderBy = conf.balancedShuffleStrategy)
  }

  private def planFakePadding(
      binning: BalancedShuffleStrategy[K],
      totalInput: Int,
      data: Seq[(K, V)]
  ): Array[Int] = {
    val realBinCounts = new Array[Int](conf.numWeavers)
    data.foreach { case (k, _) =>
      val bin = binning.assignBin(k)
      realBinCounts(bin) += 1
    }
    val d = (conf.c.toDouble * totalInput) / conf.numWeavers
    val planner = new RepeatRealPlanner(conf.alpha, conf.beta, conf.numWeavers, conf.globalSeed + mapId, conf.binomialMode)
    planner.computeFakeCounts(realBinCounts, d)
  }

  private def tagAndSend(
      data: Seq[(K, V)],
      binning: BalancedShuffleStrategy[K],
      fakeCounts: Array[Int]
  ): Unit = {
    // TODO: implement sender + buffering logic
    // Simulate output tagging for now
    println(s"[Writer] Sending ${data.size} real records and ${fakeCounts.sum} fake records")
  }
  override def getPartitionLengths(): Array[Long] = {
  // Placeholder: Spark requires this, but we aren't tracking real partition sizes yet
  Array.fill(conf.numWeavers)(0L)
  }
}  
