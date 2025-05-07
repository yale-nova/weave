import org.apache.spark.{SparkConf, SparkContext}

object WordCountBaselineTest {
  def main(args: Array[String]): Unit = {
    val conf = new SparkConf()
      .setAppName("WordCountBaselineTest")
      .setMaster("local[4]")
      .set("spark.shuffle.manager", "org.apache.spark.shuffle.weave.BaselineShuffleManager")

    val sc = new SparkContext(conf)

    val data = sc.parallelize(Seq(
      "hello world",
      "hello spark",
      "hello weave",
      "baseline shuffle"
    ), numSlices = 4)

    val counts = data
      .flatMap(_.split("\\s+"))
      .map(word => (word, 1))
      .reduceByKey(_ + _)
      .collect()

    println("✅ Word counts:")
    counts.foreach { case (word, count) =>
      println(s"$word: $count")
    }

    sc.stop()
  }
}
