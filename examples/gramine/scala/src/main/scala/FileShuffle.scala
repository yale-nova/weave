import java.io._
import java.nio.file._
import scala.util.Random
import scala.jdk.CollectionConverters._

object FileShuffle {
  def main(args: Array[String]): Unit = {
    val input = Paths.get("data/input.txt")
    if (!Files.exists(input)) {
      println(s"❌ FileShuffle failed: input file $input not found")
      System.exit(1)
    }

    val shuffled = Files.createTempFile("shuffled-", ".txt")
    println(s"📁 Writing shuffled output to $shuffled")

    var exitCode = 1

    try {
      val lines = Files.readAllLines(input).asScala.toList
      val rand = new Random()
      val shuffledLines = rand.shuffle(lines)

      Files.write(shuffled, shuffledLines.asJava)

      if (Files.size(shuffled) > 0) {
        println("✅ FileShuffle passed")
        exitCode = 0
      } else {
        println("❌ FileShuffle failed: output file is empty")
      }
    } catch {
      case e: Exception =>
        println(s"❌ FileShuffle failed: ${e.getMessage}")
    } finally {
      try {
        Files.deleteIfExists(shuffled)
        println(s"🧹 Deleted temp file $shuffled")
      } catch {
        case _: IOException =>
          println(s"⚠️ Could not delete temp file $shuffled")
      }
      System.exit(exitCode) // 💡 Only exit after finally block finishes
    }
  }
}
