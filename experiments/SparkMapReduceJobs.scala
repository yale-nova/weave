import org.apache.spark.{SparkConf, SparkContext}
import scala.util.Random

object SparkMapReduceJobs {

  def main(args: Array[String]): Unit = {
    val conf = new SparkConf().setAppName("SparkMapReduceJobs")
    val sc = new SparkContext(conf)

    val input = args(0)
    val job = args(1).toLowerCase
    val output = args(2)

    job match {
      case "hist" => histogram(sc, input, output)
      case "median" => median(sc, input, output)
      case "terasort" => teraSort(sc, input, output)
      case "invertedindex" => invertedIndex(sc, input, output)
      case "hist_median" => histMedianCombined(sc, input, output)
      case _ =>
        println(s"Unknown job: $job")
    }

    sc.stop()
  }

  def histogram(sc: SparkContext, input: String, output: String): Unit = {
    val data = sc.textFile(input)
    val hist = data
      .flatMap(_.split("\\s+"))
      .map(word => (word, 1))
      .reduceByKey(_ + _)
    hist.saveAsTextFile(output)
  }

  def median(sc: SparkContext, input: String, output: String): Unit = {
    val data = sc.textFile(input)
    // Input: "key<TAB>value"
    val kvPairs = data.map { line =>
      val Array(k, v) = line.split("\t")
      (k, v.toDouble)
    }

    val grouped = kvPairs
      .map { case (k, v) => (k, List(v)) }
      .reduceByKey(_ ++ _)
      .mapValues { values =>
        val sorted = values.sorted
        val n = sorted.size
        if (n % 2 == 1) sorted(n / 2)
        else (sorted(n / 2 - 1) + sorted(n / 2)) / 2
      }

    grouped.saveAsTextFile(output)
  }

  def teraSort(sc: SparkContext, input: String, output: String): Unit = {
    val raw = sc.textFile(input)
    val sampleFraction = 0.1

    val samples = raw
      .map(_.take(10)) // first 10 chars as key
      .sample(withReplacement = false, sampleFraction)
      .distinct()
      .collect()
      .sorted

    val numPartitions = samples.length + 1

    val data = raw.map { line =>
      val key = line.take(10)
      val value = line.drop(10)
      val partition = samples.indexWhere(sampleKey => key < sampleKey) match {
        case -1 => samples.length
        case idx => idx
      }
      (partition, (key, value))
    }

    val sorted = data
      .groupByKey(numPartitions)
      .flatMap { case (_, records) =>
        records.toList.sortBy(_._1).map { case (k, v) => s"$k$v" }
      }

    sorted.saveAsTextFile(output)
  }

  def invertedIndex(sc: SparkContext, input: String, output: String): Unit = {
    val data = sc.textFile(input)
    // Format: "docId<TAB>text"
    val pairs = data.flatMap { line =>
      val Array(docId, content) = line.split("\t", 2)
      content.split("\\s+").map(word => (word, Set(docId)))
    }

    val index = pairs
      .reduceByKey(_ ++ _)
      .mapValues(_.toList.sorted.mkString(","))

    index.saveAsTextFile(output)
  }

  def histMedianCombined(sc: SparkContext, input: String, output: String): Unit = {
    val data = sc.textFile(input)
    val words = data.flatMap(_.split("\\s+")).map(word => (word, 1.0))

    val stats = words
      .map { case (w, v) => (w, List(v)) }
      .reduceByKey(_ ++ _)
      .mapValues { values =>
        val count = values.size
        val sorted = values.sorted
        val median = if (count % 2 == 1) sorted(count / 2)
        else (sorted(count / 2 - 1) + sorted(count / 2)) / 2
        (count, median)
      }

    stats.map { case (w, (c, m)) => s"$w\tcount=$c\tmedian=$m" }
      .saveAsTextFile(output)
  }
}


def pageRank(sc: SparkContext, input: String, output: String, numIter: Int): Unit = {
  val links = sc.textFile(input)
    .map { line =>
      val parts = line.split("\\s+")
      (parts(0), parts.tail)
    }
    .mapValues(_.toList)
    .cache()

  var ranks = links.mapValues(_ => 1.0)

  for (_ <- 1 to numIter) {
    val contribs = links.join(ranks).flatMap {
      case (pageId, (neighbors, rank)) =>
        val size = neighbors.size
        neighbors.map(dest => (dest, rank / size))
    }

    ranks = contribs
      .map { case (page, contrib) => (page, contrib) }
      .reduceByKey(_ + _)
      .mapValues(v => 0.15 + 0.85 * v)
  }

  ranks.saveAsTextFile(output)
}
