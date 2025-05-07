package org.apache.spark.shuffle.weave.io

import org.scalatest.funsuite.AnyFunSuite
import java.io._
import java.net._
import scala.concurrent._
import scala.concurrent.duration._
import ExecutionContext.Implicits.global

class WeaveTCPSocketIOTest extends AnyFunSuite {

  test("TCP socket registry and stream connectivity") {
    val testData = "hello weave"
    val partitionId = 42

    val (serverSocket, _) = WeaveTCPSocketIO.openServerSocket(partitionId)

    val serverFuture = Future {
      val in = WeaveTCPSocketIO.waitForConnection(serverSocket)
      val reader = new BufferedReader(new InputStreamReader(in))
      val received = reader.readLine()
      serverSocket.close()
      received
    }

    val clientFuture = Future {
      Thread.sleep(100) // wait for server to start
      val out = WeaveTCPSocketIO.connectTo(partitionId)
      val writer = new BufferedWriter(new OutputStreamWriter(out))
      writer.write(testData + "\n")
      writer.flush()
      writer.close()
    }

    val result = Await.result(serverFuture, 2.seconds)
    Await.result(clientFuture, 2.seconds)

    assert(result == testData)
  }

  test("Multiple partitions register and connect successfully") {
    val numPartitions = 4
    val data = (0 until numPartitions).map(i => (i, s"msg-$i"))

    val servers = data.map { case (pid, _) =>
      val (sock, _) = WeaveTCPSocketIO.openServerSocket(pid)
      (pid, sock)
    }.toMap

    val serverFutures = servers.map { case (pid, sock) =>
      Future {
        val in = WeaveTCPSocketIO.waitForConnection(sock)
        val reader = new BufferedReader(new InputStreamReader(in))
        val received = reader.readLine()
        sock.close()
        (pid, received)
      }
    }

    val clientFutures = data.map { case (pid, msg) =>
      Future {
        Thread.sleep(100)
        val out = WeaveTCPSocketIO.connectTo(pid)
        val writer = new BufferedWriter(new OutputStreamWriter(out))
        writer.write(msg + "\n")
        writer.flush()
        writer.close()
      }
    }

    val results = Await.result(Future.sequence(serverFutures), 4.seconds).toMap
    Await.result(Future.sequence(clientFutures), 4.seconds)

    data.foreach { case (pid, expected) =>
      assert(results(pid) == expected)
    }
  }
}  

