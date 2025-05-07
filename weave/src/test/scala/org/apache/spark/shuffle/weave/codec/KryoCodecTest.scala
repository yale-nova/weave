package org.apache.spark.shuffle.weave.codec

import org.scalatest.funsuite.AnyFunSuite
import com.esotericsoftware.kryo.Kryo
import java.io.{ByteArrayInputStream, ByteArrayOutputStream}

class KryoCodecTest extends AnyFunSuite {

  test("KryoTaggedBatchEncoder/Decoder round-trip with internal count") {
    val kryo = new Kryo()
    kryo.register(classOf[String])
    kryo.register(classOf[Int])
    val data = Seq(
      (false, "apple", 1),
      (true, "banana", 2),
      (false, "carrot", 3)
    )

    val baos = new ByteArrayOutputStream()
    val encoder = new KryoTaggedBatchEncoder[String, Int](baos, kryo)
    encoder.writeBatch(data)
    encoder.close()

    val bytes = baos.toByteArray
    val bais = new ByteArrayInputStream(bytes)
    val input = new com.esotericsoftware.kryo.io.Input(bais)

    val decoder = new KryoTaggedBatchDecoder[String, Int](
      bais,
      kryo,
      classOf[String],
      classOf[Int]
    )
    val result = decoder.decode().toList
    decoder.close()

    assert(result == data.map { case (f, k, v) => (k, v, f) })
  }
}
