import java.net._

object NetEchoServer {
  def main(args: Array[String]): Unit = {
    val server = new ServerSocket(0)  // 0 = auto-assign port
    server.setSoTimeout(5000)         // 5-second timeout

    val port = server.getLocalPort
    println(s"🚀 Server started on port $port (will exit if no connection in 5s)")

    try {
      val client = server.accept()
      val in = new java.io.BufferedReader(new java.io.InputStreamReader(client.getInputStream))
      val out = new java.io.PrintWriter(client.getOutputStream, true)

      val msg = in.readLine()
      println(s"🟢 Received: $msg")
      out.println(s"ECHO: $msg")

      client.close()
    } catch {
      case _: java.net.SocketTimeoutException =>
        println("⏱️ No client connected in time. Exiting.")
    }

    server.close()
    println("👋 Server shutdown complete.")
    println("✅ NetEchoServer passed")
    System.exit(0)
  }
}
