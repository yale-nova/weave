package org.apache.spark.shuffle.weave.codec

import com.esotericsoftware.kryo.Kryo
import org.apache.spark.shuffle.weave.io.WeaveTCPSocketIO
import org.apache.spark.shuffle.weave.registry.WeaveRegistry
import org.scalatest.funsuite.AnyFunSuite

import java.io._
import java.net._
import scala.concurrent._
import scala.concurrent.duration._
import scala.util.Random
import ExecutionContext.Implicits.global

class KryoCodecIntegrationTest extends AnyFunSuite {

  test("End-to-end Kryo TCP transmission with registry") {
    val partitionId = 99
    val kryo = new Kryo()
    kryo.register(classOf[String])
    kryo.register(classOf[Int])

    val testData = Seq.tabulate(1000)(i => (i % 2 == 0, s"key$i", i))

    WeaveRegistry.clear()
    val (serverSocket, port) = WeaveTCPSocketIO.openServerSocket(partitionId)
    val host = InetAddress.getLocalHost.getHostAddress
    WeaveRegistry.register(partitionId, host, port)

    val serverFut = Future {
      val in = WeaveTCPSocketIO.waitForConnection(serverSocket)
      val decoder = new KryoTaggedBatchDecoder[String, Int](in, kryo, classOf[String], classOf[Int])
      val received = decoder.decode().toList
      decoder.close()
      serverSocket.close()
      received
    }

    val clientFut = Future {
      Thread.sleep(100)
      val out = WeaveTCPSocketIO.connectTo(partitionId)
      val encoder = new KryoTaggedBatchEncoder[String, Int](out, kryo)
      encoder.writeBatch(testData)
      encoder.close()
    }

    val received = Await.result(serverFut, 4.seconds)
    Await.result(clientFut, 4.seconds)

    val expected = testData.map { case (f, k, v) => (k, v, f) }
    assert(received == expected)
  }

  test("Kryo benchmark with 1 million records") {
    val kryo = new Kryo()
    kryo.register(classOf[String])
    kryo.register(classOf[Int])

    val records = (0 until 1000000).map(i => (Random.nextBoolean(), s"k$i", i)).toSeq

    val start = System.nanoTime()

    val baos = new ByteArrayOutputStream()
    val encoder = new KryoTaggedBatchEncoder[String, Int](baos, kryo)
    encoder.writeBatch(records)
    encoder.close()

    val bytes = baos.toByteArray
    val decoder = new KryoTaggedBatchDecoder[String, Int](new ByteArrayInputStream(bytes), kryo, classOf[String], classOf[Int])
    
    println(s"[DEBUG] Writing ${records.size} records")
    val result = decoder.decode().toVector
    println(s"[DEBUG] Read ${result.size} records")
    decoder.close()
    assert(result.length == 1000000)

    val end = System.nanoTime()
    val ms = (end - start) / 1e6

    println(f"[Kryo Benchmark] Serialized and decoded 1M records in $ms%.2f ms")
    assert(result.length == 1000000)
  }
}  
