package org.apache.spark.shuffle.weave.registry

import org.apache.spark.shuffle.weave.io.WeaveTCPSocketIO
import org.scalatest.funsuite.AnyFunSuite
import java.io._
import java.net._
import scala.concurrent._
import scala.concurrent.duration._
import ExecutionContext.Implicits.global

class WeaveRegistryIntegrationTest extends AnyFunSuite {

  test("Registry correctly stores and looks up reducer locations") {
    WeaveRegistry.clear()
    WeaveRegistry.register(1, "127.0.0.1", 9090)
    WeaveRegistry.register(2, "127.0.0.1", 9091)

    assert(WeaveRegistry.lookup(1).contains(("127.0.0.1", 9090)))
    assert(WeaveRegistry.lookup(2).contains(("127.0.0.1", 9091)))
    assert(WeaveRegistry.lookup(3).isEmpty)
  }

  test("Reducer registers and mapper connects using registry + TCP") {
    val partitionId = 11
    WeaveRegistry.clear()

    val (serverSocket, port) = WeaveTCPSocketIO.openServerSocket(partitionId)
    val ip = InetAddress.getLocalHost.getHostAddress
    WeaveRegistry.register(partitionId, ip, port)

    val serverFut = Future {
      val in = WeaveTCPSocketIO.waitForConnection(serverSocket)
      val reader = new BufferedReader(new InputStreamReader(in))
      val line = reader.readLine()
      serverSocket.close()
      line
    }

    val clientFut = Future {
      Thread.sleep(100)
      val (host, port) = WeaveRegistry.lookup(partitionId).get
      val socket = new Socket(host, port)
      val writer = new BufferedWriter(new OutputStreamWriter(socket.getOutputStream))
      writer.write("weave-registry-test\n")
      writer.flush()
      writer.close()
    }

    val result = Await.result(serverFut, 2.seconds)
    Await.result(clientFut, 2.seconds)

    assert(result == "weave-registry-test")
  }
}
