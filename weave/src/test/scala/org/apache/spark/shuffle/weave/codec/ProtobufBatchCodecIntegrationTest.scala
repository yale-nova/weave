package org.apache.spark.shuffle.weave.codec

import org.scalatest.funsuite.AnyFunSuite
import org.sparkweave.schema.WeaveRecord
import org.sparkweave.schema.WeaveRecord.{Key, Value}
import org.apache.spark.shuffle.weave.io.WeaveTCPSocketIO
import org.apache.spark.shuffle.weave.registry.WeaveRegistry

import java.io._
import java.net._
import scala.concurrent._
import scala.concurrent.duration._
import scala.util.Random
import ExecutionContext.Implicits.global

class ProtobufCodecIntegrationTest extends AnyFunSuite {

  test("Protobuf TCP transmission round-trip 1M records") {
    val partitionId = 77
    val records = (0 until 1000000).map { i =>
      WeaveRecord(
        isFake = i % 2 == 0,
        key = Key.KeyStr(s"key$i"),
        value = Value.ValInt(i)
      )
    }

    WeaveRegistry.clear()
    val (serverSocket, port) = WeaveTCPSocketIO.openServerSocket(partitionId)
    val host = InetAddress.getLocalHost.getHostAddress
    WeaveRegistry.register(partitionId, host, port)

    val serverFut = Future {
      val in = WeaveTCPSocketIO.waitForConnection(serverSocket)
      val decoded = ProtobufBatchDecoder.readBatch(in)
      in.close()
      serverSocket.close()
      decoded
    }

    val clientFut = Future {
      val out = WeaveTCPSocketIO.connectTo(partitionId)
      ProtobufBatchEncoder.writeBatch(records, out)
      out.close()
    }

    val received = Await.result(serverFut, 30.seconds)
    Await.result(clientFut, 30.seconds)

    assert(received.length == records.length)
    assert(received.head.key == records.head.key)
    assert(received.last.value == records.last.value)
  }
}  
