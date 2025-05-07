// SPDX-License-Identifier: BSD-3-Clause
import java.io._
import java.nio.file.{Files, Paths}
import scala.collection.mutable

object WordCount {
  val EXPECTED_UNIQUE_WORDS = 359

  def main(args: Array[String]): Unit = {
    val inputFile = if (args.length > 0) args(0) else "data/input.txt"
    val outputFile = if (args.length > 1) args(1) else "output-data/output.txt"

    val wordCounts = mutable.Map[String, Int]().withDefaultValue(0)

    val reader = Files.newBufferedReader(Paths.get(inputFile))
    var line = reader.readLine()
    while (line != null) {
      line.trim.split("\\s+").foreach { word =>
        if (word.nonEmpty) {
          val cleaned = word.toLowerCase.replaceAll("[^a-z0-9]", "")
          wordCounts(cleaned) += 1
        }
      }
      line = reader.readLine()
    }
    reader.close()

    val sortedWords = wordCounts.keys.toList.sorted
    val writer = Files.newBufferedWriter(Paths.get(outputFile))
    sortedWords.foreach { word =>
      writer.write(s"$word: ${wordCounts(word)}\n")
    }
    writer.close()

    println(s"Word count completed: ${wordCounts.size} unique words.")

    if (wordCounts.size == EXPECTED_UNIQUE_WORDS) {
      println("✅ WordCount passed")
      System.exit(0)
    } else {
      println(s"❌ WordCount failed: expected $EXPECTED_UNIQUE_WORDS but got ${wordCounts.size}")
      System.exit(1)
    }
  }
}
