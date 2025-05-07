package org.apache.spark.shuffle.weave.codec

import org.scalatest.funsuite.AnyFunSuite
import org.sparkweave.schema.WeaveRecord
import org.sparkweave.schema.WeaveRecord.{Key, Value}
import java.io._

class ProtobufBatchCodecTest extends AnyFunSuite {

  test("ProtobufBatchEncoder and Decoder round-trip") {
    val records = Seq(
      WeaveRecord(isFake = false, key = Key.KeyStr("key1"), value = Value.ValInt(100)),
      WeaveRecord(isFake = true, key = Key.KeyInt(42), value = Value.ValLong(123456789L))
    )

    val baos = new ByteArrayOutputStream()
    ProtobufBatchEncoder.writeBatch(records, baos)

    val bais = new ByteArrayInputStream(baos.toByteArray)
    val decoded = ProtobufBatchDecoder.readBatch(bais)

    assert(decoded == records)
  }
}
