object GCStressTest {
  def main(args: Array[String]): Unit = {
    println("🏁 Starting GC stress test...")

    val big = Array.fill(10000000)("spamspamspam")
    println("🧠 Allocated big array")

    System.gc()
    println("✅ Triggered GC #1")

    Thread.sleep(1000)

    val more = Array.fill(5000000)(Array.fill(10)("eggs").mkString)
    println("🍳 Allocated nested spam")

    System.gc()
    println("✅ Triggered GC #2")

    println("✔️ Finished GC stress test")
    
    println("✅ GCStressTest passed")
    System.exit(0)
  }
}
