import org.scalatest.funsuite.AnyFunSuite
import org.apache.spark.TaskContext
import org.apache.spark.shuffle.weave.WeaveShuffleWriter
import org.apache.spark.shuffle.weave.config.WeaveShuffleConf

class WeaveShuffleWriterTest extends AnyFunSuite {

  test("WeaveShuffleWriter processes map output and prints record stats") {
    val conf = WeaveShuffleConf(
      c = 2,
      alpha = 0.05,
      delta = 0.1,
      beta = 0.2,
      randomShuffleStrategy = "PRG",
      histogramStrategy = "DirectCount",
      balancedShuffleStrategy = "hashcode",
      balancedShuffleOrder = "hashCode",
      fakePaddingStrategy = "RepeatReal",
      shuffleMode = "TaggedBatch",
      globalSeed = 42L,
      batchSize = 100,
      numWeavers = 4,
      bufferSize = 4096,
      enableProfiling = true,
      binomialMode = "normal"
    )

    val writer = new WeaveShuffleWriter[String, String](
      handle = null, // You can pass mock handle if needed
      mapId = 0,
      //context = TaskContext.empty(),
      context = null,
      conf = conf
    )

    val records = (1 to 1000).map(i => (s"key_${i % 100}", s"value_$i")).iterator
    writer.write(records)
  }
}
