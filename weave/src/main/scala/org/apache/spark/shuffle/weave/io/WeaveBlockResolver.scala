package org.apache.spark.shuffle.weave.io

import java.io.{InputStream, OutputStream}
import java.util.concurrent.ConcurrentHashMap

/**
 * Central block resolver mapping reducer IDs to input/output streams.
 */
object WeaveBlockResolver {

  private val inputMap = new ConcurrentHashMap[Int, InputStream]()
  private val outputMap = new ConcurrentHashMap[Int, OutputStream]()

  def registerInput(partitionId: Int, stream: InputStream): Unit = {
    inputMap.put(partitionId, stream)
  }

  def registerOutput(partitionId: Int, stream: OutputStream): Unit = {
    outputMap.put(partitionId, stream)
  }

  def getInput(partitionId: Int): Option[InputStream] = {
    Option(inputMap.get(partitionId))
  }

  def getOutput(partitionId: Int): Option[OutputStream] = {
    Option(outputMap.get(partitionId))
  }

  def clear(): Unit = {
    inputMap.clear()
    outputMap.clear()
  }
}

