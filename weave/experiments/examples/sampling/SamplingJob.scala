import org.apache.spark.{SparkConf, SparkContext}
import scala.util.Random

object SamplingJob {
  def main(args: Array[String]): Unit = {
    val input = args(0)
    val output = args(1)
    val scale = args(2).toDouble

    val conf = new SparkConf().setAppName("SamplingJob")
    val sc = new SparkContext(conf)

    val lines = sc.textFile(input)

    val sampled = lines.mapPartitions { iter =>
      val all = iter.toArray
      val n = all.length

      val result = if (scale < 1.0) {
        Random.shuffle(all.toList).take((scale * n).toInt)
      } else if (scale > 1.0) {
        val intPart = all.toList.flatMap(x => List.fill(scale.toInt)(x))
        val fracPart = Random.shuffle(all.toList).take(((scale % 1) * n).toInt)
        intPart ++ fracPart
      } else {
        all.toList
      }

      result.iterator
    }

    sampled.saveAsTextFile(output)
    sc.stop()
  }
}
