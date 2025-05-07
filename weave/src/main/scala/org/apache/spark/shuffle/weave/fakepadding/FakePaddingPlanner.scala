package org.apache.spark.shuffle.weave.fakepadding

trait FakePaddingPlanner {
  /**
   * Computes the number of fake records to send to each reducer.
   *
   * @param realCounts An array of real record counts sent to each reducer (sampled counts).
   * @param d The global target number of records per reducer (computed by driver).
   * @return Array of fake record counts per reducer (same length as realCounts).
   */
  def computeFakeCounts(realCounts: Array[Int], d: Double): Array[Int]
}
