import org.apache.spark.sql.SparkSession

object TextJobs {

  object WordCount {
    def run(spark: SparkSession, inputPath: String, outputPath: String): Unit = {
      val sc = spark.sparkContext
      sc.hadoopConfiguration.set("mapreduce.input.fileinputformat.input.dir.recursive", "true")

      val filesRDD = sc.wholeTextFiles(inputPath)

      val wordCounts = filesRDD
        .flatMap { case (_, content) =>
          content.split("\\W+").filter(_.nonEmpty).map(_.toLowerCase)
        }
        .map(word => (word, 1))
        .reduceByKey(_ + _)

      wordCounts.saveAsTextFile(outputPath)
    }
  }

  object InvertedIndex {
    def run(spark: SparkSession, inputPath: String, outputPath: String): Unit = {
      val sc = spark.sparkContext
      sc.hadoopConfiguration.set("mapreduce.input.fileinputformat.input.dir.recursive", "true")

      val filesRDD = sc.wholeTextFiles(inputPath)

      val wordFilePairs = filesRDD.flatMap { case (filePath, content) =>
        content.split("\\W+")
          .filter(_.nonEmpty)
          .map(_.toLowerCase)
          .map(word => ((word, filePath), 1))
      }

      val wordFileCounts = wordFilePairs.reduceByKey(_ + _)
      wordFileCounts.saveAsTextFile(outputPath)
    }
  }

  def main(args: Array[String]): Unit = {
    if (args.length < 2 || !args.contains("--dir")) {
      println("Usage: spark-submit --class TextJobs <jar> <wordcount|inverted> --dir <input_dir> [--out <output_dir>]")
      sys.exit(1)
    }

    val mode = args(0)
    val inputPath = args(args.indexOf("--dir") + 1)
    val outputPath = if (args.contains("--out")) args(args.indexOf("--out") + 1)
                     else s"output/${mode}_result"

    val spark = SparkSession.builder()
      .appName(s"Text Processing: $mode")
      .master("local[*]")
      .getOrCreate()

    mode match {
      case "wordcount" => WordCount.run(spark, inputPath, outputPath)
      case "inverted" => InvertedIndex.run(spark, inputPath, outputPath)
      case _ =>
        println(s"Unknown mode '$mode'. Use 'wordcount' or 'inverted'.")
        sys.exit(1)
    }

    spark.stop()
  }
}
