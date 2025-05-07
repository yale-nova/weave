package org.apache.spark.shuffle.weave.codec

import java.io.{InputStream, OutputStream}
import com.esotericsoftware.kryo.Kryo
import com.esotericsoftware.kryo.io.{Input, Output}
import scala.collection.mutable

/**
 * Tagged batch encoder using Kryo.
 */
class KryoTaggedBatchEncoder[K, V](out: OutputStream, kryo: Kryo) {
  private val output = new Output(out)

  def writeBatch(batch: Seq[(Boolean, K, V)]): Unit = {
    output.writeInt(batch.size)
    batch.foreach { case (isFake, k, v) =>
      kryo.writeObject(output, isFake)
      kryo.writeObject(output, k)
      kryo.writeObject(output, v)
    }
    output.flush()
  }

  def close(): Unit = output.close()
}

/**
 * Tagged batch decoder using Kryo (automatically reads batch size).
 */
class KryoTaggedBatchDecoder[K, V](
    in: InputStream,
    kryo: Kryo,
    kClass: Class[K],
    vClass: Class[V]
) {
  private val input = new Input(in)
  private val totalRecords = input.readInt()

  def decode(): Iterator[(K, V, Boolean)] = new Iterator[(K, V, Boolean)] {
    private var remaining = totalRecords

    override def hasNext: Boolean = remaining > 0

    override def next(): (K, V, Boolean) = {
      if (!hasNext) throw new NoSuchElementException("No more records")
      val isFake = kryo.readObject(input, classOf[Boolean])
      val key = kryo.readObject(input, kClass)
      val value = kryo.readObject(input, vClass)
      remaining -= 1
      (key, value, isFake)
    }
  }

  def close(): Unit = input.close()
}  
