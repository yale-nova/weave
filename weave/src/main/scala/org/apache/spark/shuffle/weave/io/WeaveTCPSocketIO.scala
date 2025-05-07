package org.apache.spark.shuffle.weave.io

import java.io.{InputStream, OutputStream}
import java.net.{ServerSocket, Socket}
import java.util.concurrent.ConcurrentHashMap

/**
 * Simple TCP registry and helpers for setting up point-to-point socket streams.
 */
object WeaveTCPSocketIO {

  private val addressBook = new ConcurrentHashMap[Int, (String, Int)]()

  def registerEndpoint(partitionId: Int, host: String, port: Int): Unit = {
    addressBook.put(partitionId, (host, port))
  }

  def getEndpoint(partitionId: Int): Option[(String, Int)] = {
    Option(addressBook.get(partitionId))
  }

  def openServerSocket(partitionId: Int): (ServerSocket, Int) = {
    val serverSocket = new ServerSocket(0) // OS assigns free port
    val port = serverSocket.getLocalPort
    registerEndpoint(partitionId, "localhost", port)
    (serverSocket, port)
  }

  def waitForConnection(serverSocket: ServerSocket): InputStream = {
    val socket: Socket = serverSocket.accept()
    socket.getInputStream
  }

  def connectTo(partitionId: Int): OutputStream = {
    val (host, port) = addressBook.get(partitionId)
    val socket = new Socket(host, port)
    socket.getOutputStream
  }
}
