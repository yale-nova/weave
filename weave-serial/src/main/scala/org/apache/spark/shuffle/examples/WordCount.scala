import org.apache.spark.sql.SparkSession

object WordCount {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder
      .appName("Enron WordCount")
      .master("local[*]")
      .getOrCreate()

    val sc = spark.sparkContext
    sc.hadoopConfiguration.set("mapreduce.input.fileinputformat.input.dir.recursive", "true")

    val lines = sc.textFile("data/enron_mail") // Folder with all text emails
    val words = lines.flatMap(_.split("\\W+")).filter(_.nonEmpty)
    val wordCounts = words.map(_.toLowerCase).map((_, 1)).reduceByKey(_ + _)

    wordCounts.saveAsTextFile("output/wordcount")
    spark.stop()
  }
}
