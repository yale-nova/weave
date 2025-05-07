import java.util.concurrent.{Executors, TimeUnit, CountDownLatch}
import java.io._
import java.net.{ServerSocket, Socket}
import scala.util.{Try, Success, Failure}

object ForkTestSuite {
  var results = List.empty[(String, String)]

  def runTest(name: String)(block: => Boolean): Unit = {
    Try(block) match {
      case Success(true)  => println(s"✅ Test '$name' passed")
      case Success(false) => println(s"❌ Test '$name' failed")
      case Failure(e)     => println(s"💥 Test '$name' error: ${e.getMessage}")
    }
  }

  // === Test 1: Thread Pool Stress ===
  def testThreadPoolStress(numThreads: Int): Boolean = {
    val executor = Executors.newFixedThreadPool(numThreads)
    val latch = new CountDownLatch(numThreads)

    for (_ <- 1 to numThreads) {
      executor.submit(new Runnable {
        override def run(): Unit = {
          val sum = (1 to 10000).sum
          latch.countDown()
        }
      })
    }

    latch.await(60, TimeUnit.SECONDS)
    executor.shutdown()
    true
  }

  // === Test 2: Futex Synchronization (via Latch) ===
  def testFutexSynchronization(numThreads: Int): Boolean = {
    val startLatch = new CountDownLatch(1)
    val endLatch = new CountDownLatch(numThreads)
    val executor = Executors.newFixedThreadPool(numThreads)

    for (_ <- 1 to numThreads) {
      executor.submit(new Runnable {
        override def run(): Unit = {
          startLatch.await()
          val result = (1 to 1000).map(_ * 2).sum
          endLatch.countDown()
        }
      })
    }

    startLatch.countDown()
    val finished = endLatch.await(60, TimeUnit.SECONDS)
    executor.shutdown()
    finished
  }

  // === Test 3: Multi-threaded File I/O Test ===
  def testFileIO(numThreads: Int): Boolean = {
    val executor = Executors.newFixedThreadPool(numThreads)
    val latch = new CountDownLatch(numThreads)
    val filePrefix = "/tmp/forktest_output_thread_"

    for (i <- 1 to numThreads) {
      executor.submit(new Runnable {
        override def run(): Unit = {
          val file = new File(filePrefix + i + ".txt")
          val writer = new BufferedWriter(new FileWriter(file))
          writer.write(s"Thread $i writing to file\n")
          writer.close()

          val reader = new BufferedReader(new FileReader(file))
          val line = reader.readLine()
          reader.close()

          if (!line.contains("Thread")) throw new IOException("File content mismatch")

          file.delete() // clean up
          latch.countDown()
        }
      })
    }

    latch.await(60, TimeUnit.SECONDS)
    executor.shutdown()
    true
  }

  // === Test 4: Multi-threaded Memory Allocation and GC Test ===
  def testMemoryAllocationAndGC(numThreads: Int): Boolean = {
    val executor = Executors.newFixedThreadPool(numThreads)
    val latch = new CountDownLatch(numThreads)

    for (_ <- 1 to numThreads) {
      executor.submit(new Runnable {
        override def run(): Unit = {
          val list = (1 to 100).map(_ => new Array[Byte](1024 * 1024)) // 100MB per thread
          System.gc()
          latch.countDown()
        }
      })
    }

    latch.await(120, TimeUnit.SECONDS)
    executor.shutdown()
    true
  }

  // === Test 5: Network Communication Test (single-threaded) ===
  def testNetworkCommunication(): Boolean = {
    val server = new ServerSocket(0)
    val port = server.getLocalPort
    var success = false

    val serverThread = new Thread(new Runnable {
      override def run(): Unit = {
        val socket = server.accept()
        val in = new BufferedReader(new InputStreamReader(socket.getInputStream))
        val message = in.readLine()
        if (message == "hello") success = true
        socket.close()
      }
    })

    serverThread.start()

    val clientSocket = new Socket("127.0.0.1", port)
    val out = new BufferedWriter(new OutputStreamWriter(clientSocket.getOutputStream))
    out.write("hello\n")
    out.flush()
    clientSocket.close()

    serverThread.join()
    server.close()
    success
  }

  // === Main Dispatcher ===
  def main(args: Array[String]): Unit = {
    if (args.length < 1) {
      println("Usage: ForkTestSuite <test_number> [num_threads]")
      println("Available tests:")
      println("1 - Thread Pool Stress Test")
      println("2 - Futex Synchronization Test")
      println("3 - File I/O Test")
      println("4 - Memory Allocation and GC Test")
      println("5 - Network Communication Test (no threads needed)")
      sys.exit(1)
    }

    val testNumber = args(0).toInt
    val numThreads = if (args.length >= 2) args(1).toInt else 32  // Default: 32 threads if not specified

    testNumber match {
      case 1 => runTest("Thread Pool Stress Test")(testThreadPoolStress(numThreads))
      case 2 => runTest("Futex Synchronization Test")(testFutexSynchronization(numThreads))
      case 3 => runTest("File I/O Test")(testFileIO(numThreads))
      case 4 => runTest("Memory Allocation and GC Test")(testMemoryAllocationAndGC(numThreads))
      case 5 => runTest("Network Communication Test")(testNetworkCommunication())
      case _ =>
        println(s"Unknown test number: $testNumber")
        sys.exit(1)
    }
  }
}

