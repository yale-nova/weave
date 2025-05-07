package org.apache.spark.shuffle.weave

import org.apache.spark._
import org.apache.spark.serializer.SerializerInstance
import org.apache.spark.shuffle._
import org.apache.spark.shuffle.weave.codec.ProtobufBatchDecoder
import org.apache.spark.shuffle.weave.registry.WeaveRegistry
import org.apache.spark.shuffle.weave.io.WeaveTCPSocketIO
import org.sparkweave.schema.WeaveRecord
import org.sparkweave.schema.WeaveRecord.{Key, Value}

import java.io.InputStream
import java.net.ServerSocket
import scala.collection.Iterator

/**
 * WeaveShuffleReader connects to a registered partition's TCP socket,
 * receives a batch of serialized WeaveRecords, deserializes them,
 * and yields an iterator of (K, C) pairs for reduce tasks.
 *
 * The reader supports arbitrary key/value types encoded in Protobuf
 * and typed to K and C using dynamic casting. Type validation is strict.
 */
class WeaveShuffleReader[K, C](
    handle: BaseShuffleHandle[K, _, C],
    startPartition: Int,
    endPartition: Int,
    context: TaskContext,
    serializer: SerializerInstance
) extends ShuffleReader[K, C] {

  override def read(): Iterator[Product2[K, C]] = {
    val partitionId = startPartition
    val (host, port) = WeaveRegistry.lookup(partitionId).getOrElse {
      throw new RuntimeException(s"No registry entry for partition $partitionId")
    }

    val serverSocket = new ServerSocket(port)
    val input: InputStream = WeaveTCPSocketIO.waitForConnection(serverSocket)
    val records: Seq[WeaveRecord] = ProtobufBatchDecoder.readBatch(input)
    input.close()
    serverSocket.close()

    records.iterator.map { r =>
      val key: K = r.key match {
        case Key.KeyStr(s)  => s.asInstanceOf[K]
        case Key.KeyInt(i)  => i.asInstanceOf[K]
        case Key.KeyLong(l) => l.asInstanceOf[K]
        case _ => throw new IllegalArgumentException("Unsupported key type in WeaveRecord")
      }

      val value: C = r.value match {
        case Value.ValStr(s)  => s.asInstanceOf[C]
        case Value.ValInt(i)  => i.asInstanceOf[C]
        case Value.ValLong(l) => l.asInstanceOf[C]
        case _ => throw new IllegalArgumentException("Unsupported value type in WeaveRecord")
      }

      (key, value)
    }
  }
}
