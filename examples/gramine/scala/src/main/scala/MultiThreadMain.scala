import java.util.concurrent.{Executors, TimeUnit}

class SyncedCounter {
  private var counter = 0

  def getCounter: Int = counter

  def increment(): Unit = this.synchronized {
    counter += 1
  }
}

object MultiThreadMain {
  def main(args: Array[String]): Unit = {
    val executorService = Executors.newFixedThreadPool(8)
    val syncedCounter = new SyncedCounter

    for (_ <- 1 to 10000) {
      executorService.submit(new Runnable {
        def run(): Unit = syncedCounter.increment()
      })
    }

    executorService.shutdown()
    executorService.awaitTermination(30, TimeUnit.SECONDS)

    println(s"Final Count is: ${syncedCounter.getCounter}")
    
    if (syncedCounter.getCounter == 10000) {
  	println("✅ MultiThreadMain passed")
  	System.exit(0)
    } else {
        println(s"❌ MultiThreadMain failed: got ${syncedCounter.getCounter}")
        System.exit(1)
    }
  }
}
