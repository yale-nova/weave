package org.apache.spark.shuffle.weave.codec

import java.io.{InputStream, OutputStream, DataInputStream, DataOutputStream}
import org.sparkweave.schema.WeaveRecord

object ProtobufBatchEncoder {
  def writeBatch(records: Seq[WeaveRecord], out: OutputStream): Unit = {
    val dos = new DataOutputStream(out)
    dos.writeInt(records.size)
    records.foreach { r =>
      val bytes = r.toByteArray
      dos.writeInt(bytes.length)
      dos.write(bytes)
    }
    dos.flush()
  }
}

object ProtobufBatchDecoder {
  def readBatch(in: InputStream): Seq[WeaveRecord] = {
    val dis = new DataInputStream(in)
    val count = dis.readInt()
    (0 until count).map { _ =>
      val len = dis.readInt()
      val bytes = new Array[Byte](len)
      dis.readFully(bytes)
      WeaveRecord.parseFrom(bytes)
    }
  }
}
