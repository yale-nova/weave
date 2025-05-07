import org.apache.spark.sql.SparkSession

object InvertedIndex {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder
      .appName("Enron Inverted Index")
      .master("local[*]")
      .getOrCreate()

    val sc = spark.sparkContext
    val inputDir = "data/enron_mail"

    val files = sc.wholeTextFiles(inputDir)

    val wordDocPairs = files.flatMap { case (filePath, content) =>
      val words = content.split("\\W+").filter(_.nonEmpty).map(_.toLowerCase)
      words.distinct.map(word => (word, filePath))
    }

    val index = wordDocPairs.groupByKey()

    index.saveAsTextFile("output/inverted_index")
    spark.stop()
  }
}
