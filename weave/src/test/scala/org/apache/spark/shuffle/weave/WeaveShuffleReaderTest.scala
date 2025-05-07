import org.scalatest.funsuite.AnyFunSuite
import org.apache.spark.shuffle.weave.codec.{ProtobufBatchEncoder, ProtobufBatchDecoder}
import org.apache.spark.shuffle.weave.registry.WeaveRegistry
import org.sparkweave.schema.WeaveRecord
import org.sparkweave.schema.WeaveRecord.{Key, Value}

import java.io.{PipedInputStream, PipedOutputStream}
import scala.concurrent.duration._
import scala.concurrent.{Await, Future}
import scala.concurrent.ExecutionContext.Implicits.global

class WeaveShuffleReaderTest extends AnyFunSuite {

  test("WeaveShuffleReader reads and decodes records over stream") {
    val pipeOut = new PipedOutputStream()
    val pipeIn = new PipedInputStream(pipeOut)

    val partitionId = 0
    WeaveRegistry.register(partitionId, "localhost", 9999)

    val serverFuture = Future {
      ProtobufBatchEncoder.writeBatch(Seq(
        WeaveRecord(isFake = false, key = Key.KeyStr("k1"), value = Value.ValInt(1)),
        WeaveRecord(isFake = false, key = Key.KeyStr("k2"), value = Value.ValInt(2))
      ), pipeOut)
      pipeOut.close()
    }

    // Bypass BaseShuffleHandle entirely — test only deserialization
    val dummyReader = new {
      def read(): Iterator[(String, Int)] = {
        val records = ProtobufBatchDecoder.readBatch(pipeIn)
        records.iterator.map {
          case WeaveRecord(_, Key.KeyStr(k), Value.ValInt(v), _) => (k, v)
          case other => throw new RuntimeException(s"Unexpected record: $other")
        }
      }
    }

    val output = dummyReader.read().toList
    Await.result(serverFuture, 5.seconds)

    assert(output == List(("k1", 1), ("k2", 2)))
  }
}
