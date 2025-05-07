import java.net._
import java.io._
import scala.concurrent._
import scala.concurrent.duration._
import ExecutionContext.Implicits.global

object NetEchoRoundtrip {
  def main(args: Array[String]): Unit = {
    val portPromise = Promise[Int]()

    // === Start Server in Future ===
    val serverFuture = Future {
      val server = new ServerSocket(0) // OS picks free port
      val port = server.getLocalPort
      portPromise.success(port) // share port with main thread
      println(s"🚀 Server started on port $port")

      val clientSocket = server.accept()
      val in = new BufferedReader(new InputStreamReader(clientSocket.getInputStream))
      val out = new PrintWriter(clientSocket.getOutputStream, true)

      val msg = in.readLine()
      println(s"🟢 Server received: $msg")
      out.println(s"ECHO: $msg")

      clientSocket.close()
      server.close()

      msg
    }

    // === Wait for port from server thread ===
    val port = Await.result(portPromise.future, 5.seconds)

    // === Client logic ===
    Thread.sleep(300) // small delay for server to bind
    val client = new Socket("localhost", port)
    val out = new PrintWriter(client.getOutputStream, true)
    val in = new BufferedReader(new InputStreamReader(client.getInputStream))

    val message = "Hello from client"
    println(s"💬 Client sending: $message")
    out.println(message)

    val echoed = in.readLine()
    println(s"🔁 Client received: $echoed")

    client.close()

    // === Assert correctness ===
    assert(echoed == s"ECHO: $message", "Echo response mismatch!")
    println("✅ Echo test passed.")
    System.exit(0)
  }
}
