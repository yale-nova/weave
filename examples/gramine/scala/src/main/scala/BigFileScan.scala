import java.nio.file._
import java.io._
import scala.util.Using

object BigFileScan {
  def main(args: Array[String]): Unit = {
    val file = Files.createTempFile("bigfile-", ".txt")
    println(s"📄 Creating big temp file at $file")

    // Write 1 million lines
    Using.resource(Files.newBufferedWriter(file)) { out =>
      for (_ <- 1 to 1000000) {
        out.write("This is a heavy test line.\n")
      }
    }

    println("🔍 Reading large file...")
    val start = System.nanoTime()

    val lines = Files.lines(file)
    val count = lines.count()
    lines.close()

    val end = System.nanoTime()
    println(s"🧮 Line count: $count")
    println(f"⏱ Took ${(end - start) / 1e6}%.2f ms")

    Files.delete(file)
    println(s"🧹 Temp file $file deleted.")
    if (count == 1000000) {
  	println("✅ BigFileScan passed")
  	System.exit(0)
    } else {
       	println("❌ BigFileScan failed: wrong line count")
  	System.exit(1)
    }
  }
}
