package org.apache.spark.shuffle.weave.histogram

import org.scalatest.funsuite.AnyFunSuite

import scala.util.Random

class HistogramBuilderTest extends AnyFunSuite {

  test("sampling = 0 produces only fake records") {
    val hb = new HistogramBuilder[String](alpha = 0.0, seed = 42L, histogramStrategy = "DirectCount")
    val keys = Seq("apple", "banana", "carrot", "apple")

    keys.foreach(hb.maybeAdd)

    val serialized = hb.serialize()

    assert(serialized.real.isEmpty, "Expected no real keys")
    assert(serialized.fake.isEmpty, "Expected no fake keys (unsampled means no record at all)")
  }

  test("sampling = 1 produces all real, no fakes") {
    val hb = new HistogramBuilder[String](alpha = 1.0, seed = 42L, histogramStrategy = "DirectCount")
    val keys = Seq("apple", "banana", "carrot", "apple")

    keys.foreach(hb.maybeAdd)

    val serialized = hb.serialize()
assert(serialized.real == Map("apple" -> 1L, "banana" -> 1L, "carrot" -> 1L))
assert(serialized.fake == List(("apple", 1L)))
  }

  test("sampling = 1 should match a manually built histogram") {
    val keys = Seq("apple", "banana", "banana", "apple", "banana", "carrot")
    val groundTruth = keys.groupBy(identity).mapValues(_.size.toLong)

    val hb = new HistogramBuilder[String](alpha = 1.0, seed = 999L, histogramStrategy = "DirectCount")
    keys.foreach(hb.maybeAdd)

    val serialized = hb.serialize()
    val realHistogram = serialized.real
    val padded = serialized.fake.groupBy(_._1).mapValues(_.map(_._2).sum)

    // Combine real and fake for true match
    val combined = (realHistogram.keySet ++ padded.keySet).map { k =>
      val r = realHistogram.getOrElse(k, 0L)
      val f = padded.getOrElse(k, 0L)
      k -> (r + f)
    }.toMap

    assert(combined == groundTruth)
  }

  test("DecentralizedMerge + HistogramBuilder integration") {
    val hb1 = new HistogramBuilder[String](1.0, 123L, histogramStrategy = "DirectCount")
    val hb2 = new HistogramBuilder[String](1.0, 456L, histogramStrategy = "DirectCount")

    Seq("a", "b", "a", "c").foreach(hb1.maybeAdd)
    Seq("b", "b", "d").foreach(hb2.maybeAdd)

    val h1 = hb1.serialize().real
    val h2 = hb2.serialize().real

    val merged = DecentralizedMerge.merge[String](h1, Seq(h2))

    val expected = Map(
      "a" -> 1L, // appeared once in hb1
      "b" -> 2L, // once in hb1, once in hb2
      "c" -> 1L,
      "d" -> 1L
    )

    assert(merged == expected)
  }

  test("CentralizedMerge drops fake records and merges real only") {
    val hb = new HistogramBuilder[String](1.0, 777L, histogramStrategy = "DirectCount")
    Seq("x", "y", "x").foreach(hb.maybeAdd)

    val remote1 = Map("y" -> 1L, "z" -> 1L)
    val remote2 = Map("x" -> 1L)

    val merged = CentralizedMerge.merge[String](hb.serialize().real, Seq(remote1, remote2))

    val expected = Map(
      "x" -> 2L,
      "y" -> 2L,
      "z" -> 1L
    )

    assert(merged == expected)
  }

test("sampling correctness under various alpha values") {
  val totalRecords = 1000
  val numKeys = 50
  val keys = (0 until numKeys).map(i => s"key$i").toVector
  val input = (1 to totalRecords).map(_ => keys(Random.nextInt(keys.length)))

  val alphas = Seq(0.1, 0.3, 0.5, 0.7, 0.9)
  val margin = 150

  for (alpha <- alphas) {
    val builder = new HistogramBuilder[String](alpha, seed = 1337L + (alpha * 1000).toLong, histogramStrategy = "DirectCount")
    input.foreach(builder.maybeAdd)

    val serialized = builder.serialize()
    val real = serialized.real
    val fake = serialized.fake

    val totalSampled = real.values.sum + fake.length
    val expectedSampled = alpha * totalRecords

    assert(real.nonEmpty, s"Real records should not be empty for alpha=$alpha")
    assert(fake.nonEmpty, s"Fake records should not be empty for alpha=$alpha")
    assert(
      math.abs(totalSampled - expectedSampled) <= margin,
      s"Total sampled ($totalSampled) deviates too much from expected ($expectedSampled)"
    )
    assert(
      real.size <= numKeys,
      s"Too many real distinct keys (${real.size})"
    )
    assert(
      real.size >= (alpha * numKeys - 10),
      s"Too few real keys for alpha=$alpha"
    )
  }
}
}
